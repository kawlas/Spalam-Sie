import Foundation
import Combine

/// Copy mode for disc duplication.
public enum CopyMode: String, CaseIterable, Identifiable {
    case audioCD = "Audio CD"
    case dataCD  = "Data CD/DVD"
    case raw     = "Raw Clone"
    
    public var id: String { rawValue }
    
    /// Preferred tool for this copy mode.
    public var toolName: String {
        switch self {
        case .audioCD: return "cdrdao"
        case .dataCD:  return "readcd + cdrecord"
        case .raw:     return "dd"
        }
    }
}

/// Errors during disc copy operations.
public enum CloneError: LocalizedError {
    case invalidSource(String)
    case invalidTarget(String)
    case sameDevice
    case sourceBusy(String)
    case targetBusy(String)
    case noDiscInSource
    case noDiscInTarget
    case readFailed(String)
    case writeFailed(String)
    case verificationFailed(String)
    case toolNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidSource(let d): return "Nieprawidłowe źródło: \(d)"
        case .invalidTarget(let d): return "Nieprawidłowy cel: \(d)"
        case .sameDevice: return "Źródło i cel muszą być różnymi napędami"
        case .sourceBusy(let d): return "Źródło zajęte: \(d)"
        case .targetBusy(let d): return "Cel zajęty: \(d)"
        case .noDiscInSource: return "Brak płyty w źródłowym napędzie"
        case .noDiscInTarget: return "Brak płyty w docelowym napędzie"
        case .readFailed(let d): return "Błąd odczytu: \(d)"
        case .writeFailed(let d): return "Błąd zapisu: \(d)"
        case .verificationFailed(let d): return "Weryfikacja nie powiodła się: \(d)"
        case .toolNotFound(let t): return "Narzędzie nie znalezione: \(t). Zainstaluj przez brew"
        }
    }
}

/// Handles disc cloning/duplication via cdrdao read-cd + write.
public class CloneEngine: ObservableObject {
    public let cdrdaoPath: String
    public let readcdPath: String
    public let cdrecordPath: String
    
    @Published public var sourceDevice: String = ""
    @Published public var targetDevice: String = ""
    @Published public var copyMode: CopyMode = .audioCD
    @Published public var onTheFly: Bool = false
    @Published public var preserveCDTEXT: Bool = true
    @Published public var simulate: Bool = false
    @Published public var bufferSize: Int = 64
    
    public init(cdrdaoPath: String = "/opt/homebrew/bin/cdrdao",
                readcdPath: String = "/opt/homebrew/bin/readcd",
                cdrecordPath: String = "/opt/homebrew/bin/cdrecord") {
        self.cdrdaoPath = cdrdaoPath
        self.readcdPath = readcdPath
        self.cdrecordPath = cdrecordPath
    }
    
    // MARK: - Validation
    
    /// Validate that source and target devices are properly configured.
    /// Performs full validation when both devices are set; lenient when called
    /// for single-device operations (read or write separately).
    /// - Parameter requireBothDevices: When true, validates source != target.
    public func validateConfiguration(requireBothDevices: Bool = false) throws {
        switch copyMode {
        case .audioCD:
            guard FileManager.default.isExecutableFile(atPath: cdrdaoPath) else {
                throw CloneError.toolNotFound("cdrdao")
            }
        case .dataCD:
            guard FileManager.default.isExecutableFile(atPath: readcdPath) else {
                throw CloneError.toolNotFound("readcd")
            }
            guard FileManager.default.isExecutableFile(atPath: cdrecordPath) else {
                throw CloneError.toolNotFound("cdrecord")
            }
        case .raw:
            break // dd is always available
        }
        
        if requireBothDevices {
            guard !sourceDevice.isEmpty else { throw CloneError.invalidSource("empty") }
            guard !targetDevice.isEmpty else { throw CloneError.invalidTarget("empty") }
            guard sourceDevice != targetDevice else { throw CloneError.sameDevice }
        }
    }
    
    // MARK: - Command Generation
    
    /// Generate read-cd command for audio CD cloning.
    public func generateReadCommand(intermediateFile: String) throws -> String {
        try validateConfiguration()
        let args: [String]
        switch copyMode {
        case .audioCD:
            args = [
                cdrdaoPath, "read-cd",
                "--device", sourceDevice,
                "--paranoia-mode", "0",
                "--datafile", intermediateFile.replacingOccurrences(of: ".toc", with: ".bin"),
                intermediateFile
            ]
        case .dataCD:
            args = [
                readcdPath, "dev=\(sourceDevice)",
                "-clone",
                "f=\(intermediateFile.replacingOccurrences(of: ".toc", with: ".iso"))"
            ]
        case .raw:
            args = [
                "/bin/dd", "if=/dev/r\(sourceDevice)",
                "of=\(intermediateFile.replacingOccurrences(of: ".toc", with: ".img"))",
                "bs=2048", "conv=sync,noerror"
            ]
        }
        return args.joined(separator: " ")
    }
    
    /// Generate write command from TOC/image file.
    public func generateWriteCommand(tocFile: String) throws -> String {
        try validateConfiguration()
        let args: [String]
        switch copyMode {
        case .audioCD:
            var base = [cdrdaoPath, "write", "--device", targetDevice]
            if preserveCDTEXT { base.append("--cdtext") }
            if simulate { base.append("--simulate") }
            base.append(tocFile)
            args = base
        case .dataCD:
            args = [
                cdrecordPath, "-v", "-dao",
                "dev=\(targetDevice)",
                simulate ? "-dummy" : "",
                tocFile.replacingOccurrences(of: ".toc", with: ".iso")
            ].filter { !$0.isEmpty }
        case .raw:
            args = [
                "/bin/dd", "if=\(tocFile.replacingOccurrences(of: ".toc", with: ".img"))",
                "of=/dev/r\(targetDevice)",
                "bs=2048", "conv=sync,noerror"
            ]
        }
        return args.joined(separator: " ")
    }
    
    /// Generate on-the-fly copy command (cdrdao only).
    public func generateCopyCommand() throws -> String {
        guard copyMode == .audioCD else {
            throw CloneError.toolNotFound("on-the-fly is only supported for audio CD via cdrdao")
        }
        try validateConfiguration(requireBothDevices: true)
        var args = [cdrdaoPath, "copy",
                    "--source-device", sourceDevice,
                    "--device", targetDevice]
        if onTheFly { args.append("--on-the-fly") }
        args.append("--buffers"); args.append(String(bufferSize))
        if preserveCDTEXT { args.append("--cdtext") }
        if simulate { args.append("--simulate") }
        return args.joined(separator: " ")
    }
    
    /// Full copy pipeline as a shell command (read then write).
    public func generateFullCopyPipeline(intermediateFile: String) throws -> String {
        let readCmd = try generateReadCommand(intermediateFile: intermediateFile)
        let writeCmd = try generateWriteCommand(tocFile: intermediateFile)
        return "\(readCmd) && \(writeCmd)"
    }
    
    // MARK: - Progress Parsing
    
    /// Parse read progress from cdrdao output.
    public func parseReadProgress(_ output: String) -> Double {
        let lines = output.components(separatedBy: .newlines)
        for line in lines.reversed() {
            if let range = line.range(of: "[0-9.]+%", options: .regularExpression) {
                let pct = line[range].replacingOccurrences(of: "%", with: "")
                if let val = Double(pct) { return val / 100.0 }
            }
        }
        return 0.0
    }
    
    /// Parse write progress from cdrdao output.
    public func parseWriteProgress(_ output: String) -> (progress: Double, phase: String) {
        let lines = output.components(separatedBy: .newlines)
        var phase = ""
        var progress: Double = 0.0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("Writing lead-in") { phase = "Lead-in" }
            else if trimmed.contains("Writing lead-out") { phase = "Lead-out" }
            else if trimmed.contains("Processo") || trimmed.contains("Process") {
                if trimmed.contains("%") {
                    phase = "Writing"
                    if let pctRange = trimmed.range(of: "[0-9.]+%", options: .regularExpression) {
                        let pctStr = trimmed[pctRange].replacingOccurrences(of: "%", with: "")
                        progress = Double(pctStr) ?? 0
                    }
                }
            }
            else if trimmed.contains("Verifying") { phase = "Verifying" }
            else if trimmed.contains("Closing session") || trimmed.contains("Fixating") { phase = "Closing" }
        }
        return (progress / 100.0, phase)
    }
    
    /// Verify track count matches between source and target TOC.
    public func verifyTrackCount(sourceTOC: String, targetTOC: String) -> (match: Bool, sourceCount: Int, targetCount: Int) {
        let srcCount = sourceTOC.components(separatedBy: "TRACK AUDIO").count - 1
        let tgtCount = targetTOC.components(separatedBy: "TRACK AUDIO").count - 1
        return (srcCount == tgtCount, srcCount, tgtCount)
    }
    
    /// Run cdrdao read-toc on a device and return parsed output.
    public func readTOC(device: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cdrdaoPath)
        process.arguments = ["read-toc", "--device", device]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    
    /// Check if cdrdao is available. Used by UI to show status.
    public var isCdrdaoAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: cdrdaoPath)
    }
    
    /// Temporary file path for intermediate clone image.
    public func temporaryImagePath() -> String {
        let tmp = FileManager.default.temporaryDirectory.path
        return "\(tmp)/spalam_clone_\(UUID().uuidString.suffix(8)).toc"
    }
}
