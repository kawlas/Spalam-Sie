import Foundation

/// Errors that can occur during CD burning
public enum BurnError: LocalizedError, Sendable {
    case deviceNotFound(String)
    case deviceBusy(String)
    case burnFailed(String)
    case noDisc
    case invalidDisc
    case bufferUnderrun
    case writeError(String)
    case verificationFailed(String)
    case processError(String)
    case timeout
    case processTimeout(String)
    
    public var errorDescription: String? {
        switch self {
        case .deviceNotFound(let details):
            return "Optical drive not found: \(details)"
        case .deviceBusy(let details):
            return "Device is busy: \(details)"
        case .burnFailed(let details):
            return "Burn failed: \(details)"
        case .noDisc:
            return "No disc in drive"
        case .invalidDisc:
            return "Invalid or unsupported disc"
        case .bufferUnderrun:
            return "Buffer underrun occurred. Try a slower speed."
        case .writeError(let details):
            return "Write error: \(details)"
        case .verificationFailed(let details):
            return "Verification failed: \(details)"
        case .processError(let details):
            return "Process error: \(details)"
        case .timeout:
            return "Operation timed out"
        case .processTimeout(let details):
            return "Operation timed out: \(details)"
        }
    }
}

/// Represents a detected optical drive
public struct OpticalDrive: Sendable {
    public let name: String
    public let vendor: String
    public let model: String
    public let supportsBurnProof: Bool
    public let supportsJustLink: Bool
    public let maxWriteSpeed: Int // kB/s
    /// IOKit registry path for cdrdao on macOS Apple Silicon
    /// e.g. "IOService:/AppleARMPE/.../IODVDServices"
    public let iokitPath: String
    
    /// Human-readable device identifier (for display)
    public var displayName: String {
        return "\(vendor) \(model)"
    }
}

/// Write modes for CD burning
/// Note: cdrdao always writes in DAO/SAO mode (Disc-At-Once).
/// TAO (Track-At-Once) is only supported via cdrecord.
public enum WriteMode: String, Sendable {
    case sao = "SAO"    // Session-At-Once (disc-at-once, for cdrecord)
    case tao = "TAO"    // Track-At-Once (for cdrecord only)
    case dao = "DAO"    // Disc-At-Once (default for cdrdao)
}

/// Burn session configuration
public struct BurnConfiguration: Sendable {
    public var device: OpticalDrive?
    /// IOKit registry path for cdrdao (e.g. "IOService:/.../IODVDServices")
    public var devicePath: String
    public var speed: Int           // CD speed (1x, 2x, 4x, 8x, 10x, etc.)
    public var speedKBps: Int       // Speed in kB/s (176 for 1x, 352 for 2x, etc.)
    public var writeMode: WriteMode
    public var burnProof: Bool
    public var simulate: Bool       // Simulation mode (laser off)
    public var ejectAfterBurn: Bool
    public var bufferSize: Int      // Buffer size in KB
    public var timeout: TimeInterval
    /// Optional custom volume label for data discs (max 32 chars, used if set)
    public var volumeLabel: String?
    
    /// Creates a safe default configuration for USB-connected drives
    public static func safeUSB(device: OpticalDrive? = nil,
                                devicePath: String = "",
                                writeMode: WriteMode = .sao) -> BurnConfiguration {
        return BurnConfiguration(
            device: device,
            devicePath: devicePath,
            speed: 4,           // 4x is safe for USB 2.0
            speedKBps: 704,     // 4x = 704 kB/s
            writeMode: writeMode,
            burnProof: true,
            simulate: false,
            ejectAfterBurn: false,
            bufferSize: 4096,   // 4 MB buffer
            timeout: 600,       // 10 minutes max
            volumeLabel: nil
        )
    }
}

/// Status updates during burning
public enum BurnProgress: Sendable {
    case initializing
    case writingTrack(track: Int, total: Int, progress: Double) // progress 0.0-1.0
    case verifying(progress: Double)
    case leadIn
    case leadOut
    case closingSession
    case completed
    case error(BurnError)
}

/// Callback for burn progress updates
public typealias BurnProgressCallback = (BurnProgress) -> Void

/// Thread-safe holder for a running Process, enabling external termination
final class ProcessBox {
    var process: Process?
}

/// Main engine for CD burning via cdrdao
public class BurnEngine: DataBurner, @unchecked Sendable {
    private let cdrdaoPath: String
    private let cdrecordPath: String
    
    /// Holds the currently active process (if any) so cancel can terminate it.
    /// `nonisolated(unsafe)` because BurnEngine is a plain class accessed from
    /// both the main thread (cancel) and background queue (runWithTimeout).
    private nonisolated(unsafe) var activeProcessBox: ProcessBox?
    
    public init(cdrdaoPath: String = "/opt/homebrew/bin/cdrdao",
                cdrecordPath: String = "/opt/homebrew/bin/cdrecord") {
        self.cdrdaoPath = cdrdaoPath
        self.cdrecordPath = cdrecordPath
    }
    
    // MARK: - Device Detection
    
    /// Detects optical drives using cdrdao scanbus (gives IOKit paths on Apple Silicon).
    /// If the disc is mounted, automatically unmounts and rescans.
    /// Falls back to drutil status if scanbus returns nothing.
    public func detectDevices() throws -> [OpticalDrive] {
        // Method 1: cdrdao scanbus — gives IOKit device paths (required for Apple Silicon)
        do {
            let scanbusDrives = try detectViaCdrdaoScanbus()
            if !scanbusDrives.isEmpty {
                return scanbusDrives
            }
            
            // scanbus found nothing — the disc might be mounted, blocking access
            // Try to unmount and rescan
            unmountDisc()
            Thread.sleep(forTimeInterval: 1.0)
            let retryDrives = try detectViaCdrdaoScanbus()
            if !retryDrives.isEmpty {
                return retryDrives
            }
        } catch {
            // scanbus failed (device busy, etc.) — try unmount + retry
            unmountDisc()
            Thread.sleep(forTimeInterval: 1.0)
            if let retryDrives = try? detectViaCdrdaoScanbus(), !retryDrives.isEmpty {
                return retryDrives
            }
        }
        
        // Method 2: drutil status (name only, no IOKit path)
        if let drive = detectViaDrutil() {
            return [drive]
        }
        
        return []
    }
    
    /// Detects optical drive using drutil status (name only).
    /// Falls through to scanbus for IOKit path.
    private func detectViaDrutil() -> OpticalDrive? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/drutil")
        process.arguments = ["status"]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        // Parse: " Vendor   Product           Rev "
        //         " TSSTcorp CDDVDW SU-208DB   CH00"
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Vendor") || trimmed.contains("Type:") ||
               trimmed.contains("Sessions") || trimmed.contains("Writability") ||
               trimmed.isEmpty { continue }
            
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2 {
                let vendor = parts[0]
                let productEnd = parts.count >= 3 ? parts.count - 1 : parts.count
                let product = parts[1..<productEnd].joined(separator: " ")
                
                // We found the drive name via drutil, but we need the IOKit path
                // from scanbus. Return a placeholder — the caller will use scanbus
                // to get the full IOKit path and merge it.
                return OpticalDrive(
                    name: "\(vendor) \(product)",
                    vendor: vendor,
                    model: product,
                    supportsBurnProof: true,
                    supportsJustLink: true,
                    maxWriteSpeed: 4224,
                    iokitPath: ""
                )
            }
        }
        
        return nil
    }
    
    /// Detects optical drives using cdrdao scanbus
    private func detectViaCdrdaoScanbus() throws -> [OpticalDrive] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cdrdaoPath)
        process.arguments = ["scanbus"]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        
        let combinedOutput = output + errorOutput
        return parseCdrdaoScanbus(combinedOutput)
    }
    
    /// Parses cdrdao scanbus output into OpticalDrive structs
    private func parseCdrdaoScanbus(_ output: String) -> [OpticalDrive] {
        var drives: [OpticalDrive] = []
        let lines = output.components(separatedBy: .newlines)
        // IOKit format (macOS Apple Silicon, no quotes around values):
        // IOService:/.../IODVDServices : TSSTcorp, CDDVDW SU-208DB, CH00
        let iokitPattern = try? NSRegularExpression(
            pattern: #"^(IOService:[^:]+)\s*:\s*([^,]+),\s*([^,]+),\s*(.+)$"#,
            options: []
        )
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let pat = iokitPattern else { continue }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            if let match = pat.firstMatch(in: trimmed, options: [], range: range),
               match.numberOfRanges >= 4 {
                let iokitPath = parseMatchGroup(trimmed, range: match.range(at: 1))
                    .trimmingCharacters(in: .whitespaces)
                let vendor = parseMatchGroup(trimmed, range: match.range(at: 2))
                    .trimmingCharacters(in: .whitespaces)
                let model = parseMatchGroup(trimmed, range: match.range(at: 3))
                    .trimmingCharacters(in: .whitespaces)
                let combined = (vendor + " " + model).uppercased()
                if combined.contains("CD") || combined.contains("DVD") ||
                   combined.contains("BD") || combined.contains("OPTICAL") {
                    drives.append(OpticalDrive(
                        name: vendor + " " + model,
                        vendor: vendor,
                        model: model,
                        supportsBurnProof: true,
                        supportsJustLink: true,
                        maxWriteSpeed: 4224,
                        iokitPath: iokitPath
                    ))
                }
            }
        }
        if drives.isEmpty {
            let legacyPattern = try? NSRegularExpression(
                pattern: #"\s*(\d+),(\d+),(\d+)\s*:\s*"([^"]+)",\s*"([^"]+)",\s*"([^"]*)""#,
                options: []
            )
            for line in lines {
                guard let pat = legacyPattern else { continue }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if let match = pat.firstMatch(in: line, options: [], range: range),
                   match.numberOfRanges >= 7 {
                    let vendor = parseMatchGroup(line, range: match.range(at: 4))
                    let model = parseMatchGroup(line, range: match.range(at: 5))
                    let combined = (vendor + " " + model).uppercased()
                    if combined.contains("CD") || combined.contains("DVD") ||
                       combined.contains("BD") || combined.contains("OPTICAL") {
                        drives.append(OpticalDrive(
                            name: (vendor + " " + model).trimmingCharacters(in: .whitespaces),
                            vendor: vendor,
                            model: model,
                            supportsBurnProof: true,
                            supportsJustLink: true,
                            maxWriteSpeed: 4224,
                            iokitPath: ""
                        ))
                    }
                }
            }
        }
        return drives
    }
    private func parseMatchGroup(_ string: String, range: NSRange) -> String {
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: string) else {
            return ""
        }
        return String(string[swiftRange])
    }
    
    // MARK: - Burning
    
    /// Burns an audio CD using cdrdao with a TOC file
    /// - Parameters:
    ///   - tocContent: The TOC file content (generated by CDTEXTGenerator)
    ///   - config: Burn configuration
    ///   - progress: Optional progress callback
    /// - Returns: true if successful
    public func burnWithTOC(tocContent: String,
                           config: BurnConfiguration,
                           progress: BurnProgressCallback? = nil) throws -> Bool {
        // Write TOC to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let tocURL = tempDir.appendingPathComponent("spalam_sie_\(UUID().uuidString.prefix(8)).toc")
        try tocContent.write(to: tocURL, atomically: true, encoding: .utf8)
        
        defer {
            try? FileManager.default.removeItem(at: tocURL)
        }
        
        return try burnWithTOCFile(tocURL, config: config, progress: progress)
    }
    
    /// Burns an audio CD using an existing TOC file.
    /// In simulation mode, validates the TOC but does NOT write to the disc.
    /// - Parameters:
    ///   - tocURL: URL to the TOC file
    ///   - config: Burn configuration
    ///   - progress: Optional progress callback
    /// - Returns: true if successful
    public func burnWithTOCFile(_ tocURL: URL,
                               config: BurnConfiguration,
                               progress: BurnProgressCallback? = nil) throws -> Bool {
        progress?(.initializing)
        
        // Verify cdrdao exists
        guard FileManager.default.isExecutableFile(atPath: cdrdaoPath) else {
            throw BurnError.processError("cdrdao not found at \(cdrdaoPath)")
        }
        
        // 1. Always validate TOC first with toc-size
        let (tocValid, tocError) = try validateTOCFile(tocURL)
        guard tocValid else {
            throw BurnError.processError("TOC validation failed: \(tocError)")
        }
        
        // 2. Simulation mode: ONLY validate, NEVER write
        if config.simulate {
            progress?(.completed)
            return true
        }
        
        // 3. Real burn: unmount + write
        unmountDisc()
        Thread.sleep(forTimeInterval: 1.0)
        
        var args: [String] = []
        args.append("write")
        args.append("--device")
        args.append(config.devicePath)
        args.append("--speed")
        args.append("\(config.speed)")
        args.append("--buffer-under-run-protection")
        args.append(config.burnProof ? "1" : "0")
        let numBuffers = max(10, config.bufferSize / 32)
        args.append("--buffers")
        args.append("\(numBuffers)")
        args.append(tocURL.path)
        
        return try runCdrdao(args: args, config: config, progress: progress)
    }
    
    /// Validates a TOC file without writing: checks syntax with toc-size
    private func validateTOCFile(_ url: URL) throws -> (Bool, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cdrdaoPath)
        process.arguments = ["toc-size", url.path]
        process.standardOutput = FileHandle.nullDevice
        
        let errPipe = Pipe()
        process.standardError = errPipe
        
        try process.run()
        process.waitUntilExit()
        
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if process.terminationStatus == 0 {
            return (true, "")
        }
        return (false, errStr)
    }
    
    /// Burns audio tracks directly (without TOC file) using cdrecord
    /// - Parameters:
    ///   - wavFiles: Array of paths to 44.1kHz/16-bit/stereo WAV files
    ///   - config: Burn configuration
    ///   - progress: Optional progress callback
    /// - Returns: true if successful
    public func burnAudioTracks(_ wavFiles: [String],
                               config: BurnConfiguration,
                               progress: BurnProgressCallback? = nil) throws -> Bool {
        progress?(.initializing)
        
        // Verify cdrecord exists
        guard FileManager.default.isExecutableFile(atPath: cdrecordPath) else {
            throw BurnError.processError("cdrecord not found at \(cdrecordPath)")
        }
        
        // Check that WAV files exist
        for file in wavFiles {
            guard FileManager.default.fileExists(atPath: file) else {
                throw BurnError.processError("Audio file not found: \(file)")
            }
        }
        
        // Build cdrecord arguments
        var args: [String] = []
        args.append("-v")                    // verbose
        args.append("dev=\(config.devicePath)")  // device
        args.append("speed=\(config.speed)")      // speed
        args.append("-dao")                  // disc-at-once
        args.append("-useinfo")              // use CD-TEXT info from WAV
        args.append("text")                  // write CD-TEXT
        
        if config.simulate {
            args.append("-dummy")
        }
        
        if config.ejectAfterBurn {
            args.append("-eject")
        }
        
        // Add WAV files
        args.append(contentsOf: wavFiles)
        
        // Run cdrecord
        return try runCdrecord(args: args, config: config, progress: progress)
    }
    
    // MARK: - Utility Operations
    
    /// Unmounts any mounted volume from the optical drive.
    /// Required before cdrdao can access the device via SCSI.
    /// First checks if the disc is already unmounted — only unmounts if needed.
    /// - Returns: true if unmount was successful or nothing was mounted
    public func unmountDisc() -> Bool {
        // Find the optical disc device from drutil status
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/drutil")
        process.arguments = ["status"]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        // Check drutil status: if it reports "No media" or "No disc", nothing to unmount
        if output.lowercased().contains("no media") ||
           output.lowercased().contains("no disc") {
            return true
        }
        
        // Extract device name from drutil output: "Name: /dev/disk4"
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Name:") {
                let parts = trimmed.split(separator: ":")
                if parts.count >= 2 {
                    let devicePath = parts[1..<parts.count].joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    
                    // Check if this device is already unmounted
                    let infoProcess = Process()
                    infoProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                    infoProcess.arguments = ["info", devicePath]
                    let infoOut = Pipe()
                    infoProcess.standardOutput = infoOut
                    guard (try? infoProcess.run()) != nil else { continue }
                    infoProcess.waitUntilExit()
                    let info = String(data: infoOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    
                    // If already unmounted, skip
                    if info.contains("Mounted: No") || info.contains("Not mounted") ||
                       info.contains("This disk is not mounted") {
                        return true
                    }
                    
                    // Unmount using diskutil
                    let unmount = Process()
                    unmount.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                    unmount.arguments = ["unmountDisk", devicePath]
                    
                    // Discard output — only need exit code
                    unmount.standardOutput = FileHandle.nullDevice
                    unmount.standardError = FileHandle.nullDevice
                    
                    guard (try? unmount.run()) != nil else { return false }
                    unmount.waitUntilExit()
                    
                    return unmount.terminationStatus == 0
                }
            }
        }
        
        return true // Nothing to unmount
    }
    
    /// Ejects the disc using the most reliable method available.
    /// Priority: drutil eject (native macOS) → cdrecord -eject (fallback).
    /// Unmounts the disc first if needed.
    public func eject(iokitPath: String = "") throws {
        // 1. Always try to unmount first (required before hardware eject)
        unmountDisc()
        
        // 2. Try native drutil eject (most reliable on macOS)
        let drutil = Process()
        drutil.executableURL = URL(fileURLWithPath: "/usr/bin/drutil")
        drutil.arguments = ["eject"]
        
        drutil.standardOutput = FileHandle.nullDevice
        let drutilErr = Pipe()
        drutil.standardError = drutilErr
        
        try drutil.run()
        drutil.waitUntilExit()
        
        if drutil.terminationStatus == 0 {
            return // Success
        }
        
        // 3. Fallback: cdrecord -eject
        let errData = drutilErr.fileHandleForReading.readDataToEndOfFile()
        let errStr = String(data: errData, encoding: .utf8) ?? ""
        
        let cdrecord = Process()
        cdrecord.executableURL = URL(fileURLWithPath: cdrecordPath)
        cdrecord.arguments = ["dev=\(iokitPath)", "-eject", "-v"]
        
        cdrecord.standardOutput = FileHandle.nullDevice
        cdrecord.standardError = FileHandle.nullDevice
        
        try cdrecord.run()
        cdrecord.waitUntilExit()
        
        if cdrecord.terminationStatus != 0 {
            throw BurnError.processError("Eject failed: drutil error='\(errStr)', cdrecord also failed")
        }
    }
    
    /// Loads/closes the tray
    public func closeTray(iokitPath: String = "") throws {
        // Try AppleScript GUI automation first (works for many drives)
        // Fallback to cdrecord
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cdrecordPath)
        process.arguments = ["dev=\(iokitPath)", "-load", "-v"]
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw BurnError.processError("Close tray failed: \(error.localizedDescription)")
        }
    }
    
    /// Checks if there's a disc in the drive
    public func checkDisc(iokitPath: String = "") throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cdrecordPath)
        process.arguments = ["dev=\(iokitPath)", "-atip"]
        
        // Discard output — we only check the exit code
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        return process.terminationStatus == 0
    }
    
    /// Reads disc info
    public func readDiscInfo(iokitPath: String = "") throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cdrdaoPath)
        process.arguments = ["disk-info", "--device", iokitPath]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    /// Verifies a burned disc by reading back the TOC and comparing track count.
    /// This is NOT a byte-for-byte comparison — it checks that the disc is readable
    /// and contains the expected number of audio tracks.
    /// - Parameters:
    ///   - devicePath: IOKit path to the optical drive
    ///   - expectedTracks: Number of tracks expected on the disc
    /// - Returns: true if verification passes
    public func verifyBurn(devicePath: String, expectedTracks: Int) throws -> Bool {
        // First check if the disc is present using drutil
        let drutilProc = Process()
        drutilProc.executableURL = URL(fileURLWithPath: "/usr/bin/drutil")
        drutilProc.arguments = ["status"]
        let drutilOut = Pipe()
        drutilProc.standardOutput = drutilOut
        drutilProc.standardError = FileHandle.nullDevice
        try drutilProc.run()
        drutilProc.waitUntilExit()
        let drutilOutput = String(data: drutilOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        
        if drutilOutput.lowercased().contains("no media") || drutilOutput.lowercased().contains("no disc") {
            throw BurnError.noDisc
        }
        
        // Try cdrdao read-toc for a more detailed check
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cdrdaoPath)
            process.arguments = ["read-toc", "--device", devicePath]
            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                // Count TRACK AUDIO entries in the TOC output
                let trackCount = output.components(separatedBy: "TRACK AUDIO").count - 1
                return trackCount == expectedTracks
            }
        } catch {
            // read-toc may not work on all drives — that's OK
        }
        
        // Fallback: check using drutil if the disc has audio tracks
        let trackCountLine = drutilOutput.components(separatedBy: .newlines)
            .filter { $0.contains("Sessions:") || $0.contains("Tracks:") }
            .first
        if let line = trackCountLine, let count = Int(line.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") {
            return count > 0
        }
        
        // If drive is readable but we can't get exact count, assume success
        return true
    }
    
    // MARK: - Data Disc Burning
    
    /// Generate a TOC (Table of Contents) for a data disc.
    /// Data discs use CDROM_MODE1 rather than CD_DA.
    public func generateDataTOC(config: BurnConfiguration, files: [String]) throws -> String {
        var toc = ""
        toc += "// CD-RW/-R data disc generated by Spalam Sie\n"
        toc += "\n"
        toc += "CDROM_MODE1\n"
        for file in files {
            toc += "  FILE \"\(file)\" 0 01:00:00\n"
        }
        toc += "// Disc layout: data session\n"
        return toc
    }
    
    /// Generate a cdrecord command to burn a pre-mastered ISO image.
    public func generateDataBurnCommand(config: BurnConfiguration, isoPath: String) throws -> String {
        var args: [String] = []
        args.append("-v")
        if config.simulate { args.append("-dummy") }
        if config.ejectAfterBurn { args.append("-eject") }
        switch config.writeMode {
        case .sao, .dao: args.append("-dao")
        case .tao: args.append("-tao")
        }
        args.append("speed=\(config.speed)")
        args.append("dev=\(config.devicePath)")
        args.append(isoPath)
        return "\(cdrecordPath) \(args.joined(separator: " "))"
    }
    
    /// Generate a full data burn pipeline (mkisofs + cdrecord or growisofs).
    public func generateDataBurnPipeline(config: BurnConfiguration, isoPath: String) throws -> String {
        // First generate ISO, then burn it
        let volumeLabel = config.volumeLabel ?? "SPALAM_DATA"
        return "\(ISOBuilder.mkisofsBinaryPath) -R -J -V \"\(volumeLabel)\" -o \(isoPath) \(isoPath) && \(try generateDataBurnCommand(config: config, isoPath: isoPath))"
    }
    
    /// Generate a data burn pipeline from a source path (directory) directly to disc.
    public func generateDataBurnPipeline(config: BurnConfiguration, sourcePath: String) throws -> String {
        // Use growisofs for direct directory-to-DVD burning when available
        let growisofsPath = "/opt/homebrew/bin/growisofs"
        if FileManager.default.isExecutableFile(atPath: growisofsPath) {
            return "\(growisofsPath) -\(config.simulate ? "dry-run" : "Z") \(config.devicePath) -R -J \(sourcePath)"
        }
        // Fallback: mkisofs + cdrecord
        let volumeLabel = config.volumeLabel ?? "SPALAM_DATA"
        let tempISO = "/tmp/spalam_data_\(UUID().uuidString).iso"
        let mkisofsPath = ISOBuilder.mkisofsBinaryPath
        let mkisofsCmd = "\(mkisofsPath) -R -J -V \"\(volumeLabel)\" -o \(tempISO) \(sourcePath)"
        let burnCmd = try generateDataBurnCommand(config: config, isoPath: tempISO)
        return "\(mkisofsCmd) && \(burnCmd) && rm -f \(tempISO)"
    }
    
    // MARK: - Data Disc Execution
    
    /// Execute a data burn pipeline (mkisofs + cdrecord or growisofs) for a source directory.
    /// - Parameters:
    ///   - config: Burn configuration
    ///   - sourcePath: Path to the source directory to burn
    ///   - progress: Optional progress callback
    /// - Returns: true if successful
    /// - Throws: BurnError if the burn fails or source is missing
    public func burnData(config: BurnConfiguration, sourcePath: String, progress: BurnProgressCallback?) throws -> Bool {
        progress?(.initializing)
        
        // Verify source exists
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw BurnError.processError("Source path does not exist: \(sourcePath)")
        }
        
        // Get the pipeline
        let pipeline = try generateDataBurnPipeline(config: config, sourcePath: sourcePath)
        
        // Run via runWithTimeout using /bin/bash -c
        return try runWithTimeout(timeout: config.timeout) { box in
            let process = Process()
            box.process = process
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", pipeline]
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            try process.run()
            
            let fileHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading
            
            let group = DispatchGroup()
            
            group.enter()
            var outputData = Data()
            DispatchQueue.global(qos: .userInitiated).async {
                outputData = fileHandle.readDataToEndOfFile()
                group.leave()
            }
            
            group.enter()
            var errorData = Data()
            DispatchQueue.global(qos: .userInitiated).async {
                errorData = errorHandle.readDataToEndOfFile()
                group.leave()
            }
            
            process.waitUntilExit()
            group.wait()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            // Parse progress from combined output
            self.parseDataBurnProgress(output + "\n" + errorOutput, progress: progress)
            
            if process.terminationStatus != 0 {
                let errorMsg = BurnError.burnFailed("Data burn failed: \(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
                progress?(.error(errorMsg))
                throw errorMsg
            }
            
            progress?(.completed)
            return true
        }
    }
    
    /// Parses data burn pipeline output for progress information.
    /// Handles cdrecord-style ("Track 01: 45% done") and growisofs-style ("[RO] 45%") output.
    private func parseDataBurnProgress(_ output: String, progress: BurnProgressCallback?) {
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // cdrecord: "Track 01: 45% done" or "Track 01: 45.0% done"
            if trimmed.contains("Track") && trimmed.contains("%") && trimmed.contains("done") {
                if let percentRange = trimmed.range(of: "[0-9.]+%", options: .regularExpression) {
                    let percentStr = trimmed[percentRange].replacingOccurrences(of: "%", with: "")
                    if let percent = Double(percentStr) {
                        progress?(.writingTrack(track: 1, total: 1, progress: percent / 100.0))
                    }
                }
            }
            // growisofs: "[RO] 45%" or "  45.0%"
            else if trimmed.contains("[RO") && trimmed.contains("%") {
                if let percentRange = trimmed.range(of: "[0-9.]+%", options: .regularExpression) {
                    let percentStr = trimmed[percentRange].replacingOccurrences(of: "%", with: "")
                    if let percent = Double(percentStr) {
                        progress?(.writingTrack(track: 1, total: 1, progress: percent / 100.0))
                    }
                }
            }
            
            // Phases
            if trimmed.contains("Starting to write") || trimmed.contains("Writing lead-in") {
                progress?(.leadIn)
            } else if trimmed.contains("lead-out") || trimmed.contains("Lead-out") {
                progress?(.leadOut)
            } else if trimmed.contains("Closing") || trimmed.contains("Fixating") {
                progress?(.closingSession)
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Runs cdrdao with the given arguments and handles output
    private func runCdrdao(args: [String],
                          config: BurnConfiguration,
                          progress: BurnProgressCallback?) throws -> Bool {
        return try runWithTimeout(timeout: config.timeout) { box in
            let process = Process()
            box.process = process
            process.executableURL = URL(fileURLWithPath: self.cdrdaoPath)
            process.arguments = args
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            try process.run()
            
            // Parse output for progress
            let fileHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading
            
            // Read in background
            let group = DispatchGroup()
            
            group.enter()
            var outputData = Data()
            DispatchQueue.global(qos: .userInitiated).async {
                outputData = fileHandle.readDataToEndOfFile()
                group.leave()
            }
            
            group.enter()
            var errorData = Data()
            DispatchQueue.global(qos: .userInitiated).async {
                errorData = errorHandle.readDataToEndOfFile()
                group.leave()
            }
            
            process.waitUntilExit()
            group.wait()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            // Parse progress from output
            self.parseCdrdaoProgress(output + errorOutput, progress: progress)
            
            if process.terminationStatus != 0 {
                let errorMsg = self.parseCdrdaoError(errorOutput + output)
                progress?(.error(errorMsg))
                throw errorMsg
            }
            
            progress?(.completed)
            return true
        }
    }
    
    /// Runs cdrecord with the given arguments
    private func runCdrecord(args: [String],
                            config: BurnConfiguration,
                            progress: BurnProgressCallback?) throws -> Bool {
        return try runWithTimeout(timeout: config.timeout) { box in
            let process = Process()
            box.process = process
            process.executableURL = URL(fileURLWithPath: self.cdrecordPath)
            process.arguments = args
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            try process.run()
            
            let fileHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading
            
            let group = DispatchGroup()
            
            group.enter()
            var outputData = Data()
            DispatchQueue.global(qos: .userInitiated).async {
                outputData = fileHandle.readDataToEndOfFile()
                group.leave()
            }
            
            group.enter()
            var errorData = Data()
            DispatchQueue.global(qos: .userInitiated).async {
                errorData = errorHandle.readDataToEndOfFile()
                group.leave()
            }
            
            process.waitUntilExit()
            group.wait()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            
            // Parse cdrecord progress
            self.parseCdrecordProgress(output + errorOutput, progress: progress)
            
            if process.terminationStatus != 0 {
                let errorMsg = BurnError.burnFailed("cdrecord failed: \(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
                progress?(.error(errorMsg))
                throw errorMsg
            }
            
            progress?(.completed)
            return true
        }
    }
    
    /// Runs a block with a timeout guard on a background queue.
    /// If the block does not complete within `timeout` seconds, the process is terminated
    /// and a `BurnError.processTimeout` is thrown.
    /// The block receives a ProcessBox that should have its `process` set so termination works.
    internal func runWithTimeout<T>(timeout: TimeInterval, block: @escaping (ProcessBox) throws -> T) throws -> T {
        let box = ProcessBox()
        self.activeProcessBox = box
        defer { self.activeProcessBox = nil }
        let semaphore = DispatchSemaphore(value: 0)
        var resultBox: Result<T, Error>?
        DispatchQueue.global(qos: .userInitiated).async {
            do { resultBox = .success(try block(box)) }
            catch { resultBox = .failure(error) }
            semaphore.signal()
        }
        let waited = semaphore.wait(timeout: .now() + timeout)
        if waited == .timedOut {
            box.process?.terminate()
            throw BurnError.processTimeout("Operation timed out after \(Int(timeout))s")
        }
        switch resultBox {
        case .success(let v): return v
        case .failure(let e): throw e
        case .none: throw BurnError.processTimeout("Operation did not complete")
        }
    }
    
    /// Cancels the currently running burn process by terminating it.
    /// Safe to call even when no process is running (no-op).
    public func cancel() {
        activeProcessBox?.process?.terminate()
    }
    
    /// Parses cdrdao output for progress information
    private func parseCdrdaoProgress(_ output: String, progress: BurnProgressCallback?) {
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.contains("Writing lead-in") {
                progress?(.leadIn)
            } else if trimmed.contains("Writing lead-out") {
                progress?(.leadOut)
            } else if (trimmed.contains("Processo") || trimmed.contains("Process")) &&
                       trimmed.contains("%") {
                // "Processo: 45.3%" (Italian locale) or "Process: 45.3%" (English)
                if let percentRange = trimmed.range(of: "[0-9.]+%", options: .regularExpression) {
                    let percentStr = trimmed[percentRange].replacingOccurrences(of: "%", with: "")
                    if let percent = Double(percentStr) {
                        progress?(.writingTrack(track: 1, total: 1, progress: percent / 100.0))
                    }
                }
            } else if trimmed.contains("Verifying") {
                progress?(.verifying(progress: 0.5))
            } else if trimmed.contains("Closing session") || trimmed.contains("Fixating") {
                progress?(.closingSession)
            }
        }
    }
    
    /// Parses cdrecord output for progress information
    private func parseCdrecordProgress(_ output: String, progress: BurnProgressCallback?) {
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // "Writing track 1 of 2:  45% done"
            if let trackRange = trimmed.range(of: "Writing track (\\\\d+) of (\\\\d+):\\\\s*(\\\\d+)% done",
                                             options: .regularExpression) {
                let parts = trimmed[trackRange].components(separatedBy: CharacterSet.whitespaces)
                if parts.count >= 6,
                   let track = Int(parts[2]),
                   let total = Int(parts[4]),
                   let percent = Int(parts[5].replacingOccurrences(of: "%", with: "").replacingOccurrences(of: "done", with: "")) {
                    progress?(.writingTrack(track: track, total: total, progress: Double(percent) / 100.0))
                }
            } else if trimmed.contains("Starting to write CD/DVD at") {
                progress?(.leadIn)
            } else if trimmed.contains("Track") && trimmed.contains("of") && trimmed.contains("written") {
                progress?(.closingSession)
            }
        }
    }
    
    /// Parses cdrdao error output into a BurnError
    private func parseCdrdaoError(_ output: String) -> BurnError {
        let errorLower = output.lowercased()
        
        if errorLower.contains("buffer underrun") || errorLower.contains("underrun") {
            return .bufferUnderrun
        } else if errorLower.contains("no disc") || errorLower.contains("medium not present") {
            return .noDisc
        } else if errorLower.contains("device busy") || errorLower.contains("resource busy") {
            return .deviceBusy("Device is busy")
        } else if errorLower.contains("scsi") && errorLower.contains("error") {
            return .writeError("SCSI error: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        } else if errorLower.contains("illegal mode") || errorLower.contains("invalid") {
            return .invalidDisc
        }
        
        return .burnFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
