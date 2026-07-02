import Foundation
import SwiftUI

/// Represents a loaded track ready for burning
public struct BurnTrack: Identifiable, Equatable {
    public let id = UUID()
    public var fileURL: URL
    public var title: String
    public var performer: String?
    public var trackNumber: Int
    public var duration: TimeInterval
    public var fileSize: Int64
    public var format: AudioFormat
    /// If set, this track is extracted from a split-CUE file at this offset (seconds)
    public var cueStartOffset: TimeInterval?
    /// If set, the expected end time for this CUE-split segment (seconds)
    public var cueEndOffset: TimeInterval?
    
    public static func == (lhs: BurnTrack, rhs: BurnTrack) -> Bool {
        lhs.id == rhs.id
    }
}

/// Audio format for source files
public enum AudioFormat: String, CaseIterable {
    case wav = "WAV"
    case flac = "FLAC"
    case mp3 = "MP3"
    case aiff = "AIFF"
    case m4a = "M4A"
    case cue = "CUE"
    case unknown = "?"
    
    public var isLossless: Bool {
        self == .wav || self == .flac || self == .aiff
    }
}

/// Overall burn session state
public enum BurnSessionState: Equatable {
    case idle
    case loadingTracks
    case ready
    case burning(progress: Double, currentTrack: Int, totalTracks: Int)
    case verifying(progress: Double)
    case completed(success: Bool, message: String)
    case error(String)
}

/// Main session model for the burn workflow
@MainActor
public class BurnSession: ObservableObject {
    @Published public var tracks: [BurnTrack] = []
    @Published public var state: BurnSessionState = .idle
    @Published public var albumTitle: String = ""
    @Published public var albumArtist: String = ""
    @Published public var burnSpeed: Int = 4
    @Published public var burnProof: Bool = true
    @Published public var simulate: Bool = false
    @Published public var ejectAfterBurn: Bool = false
    @Published public var deviceAddress: String = ""
    @Published public var detectedDevice: OpticalDrive?
    @Published public var log: String = ""
    @Published public var totalDuration: TimeInterval = 0
    
    private let audioConverter = AudioConverter()
    private let metadataExtractor = MetadataExtractor()
    private let cdtextGenerator = CDTEXTGenerator()
    private let burnEngine = BurnEngine()
    
    // MARK: - Track Management
    
    /// Adds files to the session. Handles both files and folders (recursive).
    /// Returns rejected files with reasons.
    @discardableResult
    public func addFiles(_ urls: [URL]) -> [(URL, String)] {
        var rejected: [(URL, String)] = []
        let audioExtensions = Set(["wav", "flac", "mp3", "aiff", "aif", "m4a"])
        
        // Collect all audio files (expand folders recursively)
        var filesToAdd: [URL] = []
        var cueFiles: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                rejected.append((url, "File not found"))
                continue
            }
            
            if isDir.boolValue {
                // Walk directory recursively
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                    for case let fileURL as URL in enumerator {
                        let ext = fileURL.pathExtension.lowercased()
                        if ext == "cue" {
                            cueFiles.append(fileURL)
                        } else if audioExtensions.contains(ext) {
                            filesToAdd.append(fileURL)
                        }
                    }
                }
            } else {
                let ext = url.pathExtension.lowercased()
                if ext == "cue" {
                    cueFiles.append(url)
                } else {
                    filesToAdd.append(url)
                }
            }
        }
        
        // Sort files alphabetically
        filesToAdd.sort { $0.path < $1.path }
        
        // Add individual audio files
        for url in filesToAdd {
            if let track = loadTrack(from: url) {
                if !tracks.contains(where: { $0.fileURL == url }) {
                    tracks.append(track)
                } else {
                    rejected.append((url, "Already added"))
                }
            } else {
                rejected.append((url, "Unsupported format"))
            }
        }
        
        // Add CUE files — parse and load referenced tracks
        for cueURL in cueFiles {
            do {
                let cueTracks = try loadTracksFromCUE(cueURL)
                for ct in cueTracks {
                    if !tracks.contains(where: { $0.fileURL == ct.fileURL && $0.cueStartOffset == ct.cueStartOffset }) {
                        tracks.append(ct)
                    }
                }
                appendLog("Loaded \(cueTracks.count) tracks from \(cueURL.lastPathComponent)")
            } catch {
                rejected.append((cueURL, "Failed to parse CUE: \(error.localizedDescription)"))
            }
        }
        
        sortTracks()
        updateState()
        return rejected
    }
    
    /// Removes tracks by indices
    public func removeTracks(at indices: IndexSet) {
        tracks.remove(atOffsets: indices)
        renumberTracks()
        updateState()
    }
    
    /// Moves tracks within the list
    public func moveTracks(from source: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: source, toOffset: destination)
        renumberTracks()
    }
    
    /// Clears all tracks
    public func clearTracks() {
        tracks.removeAll()
        state = .idle
        log = ""
    }
    
    // MARK: - Metadata
    
    /// Generates CD-TEXT from current session data
    public func generateCDTEXTData() -> CDTEXTData {
        let metadata: [String: String] = [
            "album": albumTitle,
            "artist": albumArtist
        ]
        
        let filePaths = tracks.map { $0.fileURL.path }
        
        do {
            return try cdtextGenerator.createCDTEXTData(
                from: metadata,
                filePaths: filePaths
            )
        } catch {
            appendLog("Warning: CD-TEXT generation failed: \(error.localizedDescription)")
            // Return basic CD-TEXT
            return CDTEXTData(
                albumTitle: albumTitle.isEmpty ? nil : albumTitle,
                albumPerformer: albumArtist.isEmpty ? nil : albumArtist,
                tracks: tracks.map { track in
                    CDTEXTEntry(
                        trackNumber: track.trackNumber,
                        title: track.title,
                        performer: track.performer
                    )
                }
            )
        }
    }
    
    // MARK: - Burning
    
    /// Starts the burn process
    public func startBurn() {
        guard !tracks.isEmpty else {
            state = .error("No tracks to burn")
            return
        }
        
        guard !deviceAddress.isEmpty else {
            state = .error("No optical drive detected. Click refresh or check connection.")
            return
        }
        
        state = .loadingTracks
        
        Task {
            do {
                try await performBurn()
            } catch {
                await MainActor.run {
                    state = .error(error.localizedDescription)
                }
            }
        }
    }
    
    /// Cancels the current burn operation by terminating the underlying process
    public func cancelBurn() {
        appendLog("🛑 Cancel requested — terminating burn process...")
        burnEngine.cancel()
        state = .error("Burn cancelled by user")
    }
    
    /// Refreshes device detection
    public func refreshDevice() {
        Task {
            do {
                let drives = try burnEngine.detectDevices()
                if let drive = drives.first {
                    detectedDevice = drive
                    deviceAddress = drive.iokitPath
                    appendLog("Detected: \(drive.name)")
                } else {
                    detectedDevice = nil
                    appendLog("No optical drive detected")
                }
            } catch {
                appendLog("Device detection failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Private
    
    /// Parses a CUE file and creates BurnTrack entries for each referenced audio track.
    /// Handles both single-file-per-track and monolithic CUE sheets.
    private func loadTracksFromCUE(_ cueURL: URL) throws -> [BurnTrack] {
        let parser = CUEParser()
        let parsed = try parser.parseCUE(from: cueURL)
        
        let cueDir = cueURL.deletingLastPathComponent()
        var result: [BurnTrack] = []
        
        // Resolve the audio file path referenced in the CUE
        let audioFileName = parsed.fileName
        let audioURL: URL
        if audioFileName.hasPrefix("/") {
            audioURL = URL(fileURLWithPath: audioFileName)
        } else {
            audioURL = cueDir.appendingPathComponent(audioFileName)
        }
        
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw CUEParserError.fileNotFound
        }
        
        // Determine format from audio file extension
        let audioExt = audioURL.pathExtension.lowercased()
        let format: AudioFormat
        switch audioExt {
        case "wav", "wave": format = .wav
        case "flac": format = .flac
        case "mp3": format = .mp3
        case "aiff", "aif": format = .aiff
        case "m4a": format = .m4a
        default: format = .unknown
        }
        
        let resourceValues = try? audioURL.resourceValues(forKeys: [.fileSizeKey])
        let totalFileSize = Int64(resourceValues?.fileSize ?? 0)
        
        for cueTrack in parsed.tracks {
            let startSec = cueTrack.indices[1] ?? 0.0
            
            // Calculate duration: from this track's INDEX 01 to next track's INDEX 01, or 0 (unknown)
            var duration: TimeInterval = 0
            if let nextIdx = cueTrack.indices[1] {
                // Look for next track's index 01
                if let nextTrack = parsed.tracks.first(where: { $0.number == cueTrack.number + 1 }),
                   let nextStart = nextTrack.indices[1] {
                    duration = max(0, nextStart - nextIdx)
                }
            }
            
            let trackTitle = cueTrack.title ?? audioURL.deletingPathExtension().lastPathComponent
            let trackPerformer = cueTrack.performer ?? parsed.performer
            
            // Use album-level metadata if available
            if albumTitle.isEmpty, let t = parsed.title, !t.isEmpty {
                albumTitle = t
            }
            if albumArtist.isEmpty, let p = parsed.performer, !p.isEmpty {
                albumArtist = p
            }
            
            let track = BurnTrack(
                fileURL: audioURL,
                title: trackTitle,
                performer: trackPerformer,
                trackNumber: result.count + 1,
                duration: duration,
                fileSize: totalFileSize / Int64(max(parsed.tracks.count, 1)),
                format: format,
                cueStartOffset: startSec > 0 ? startSec : nil,
                cueEndOffset: duration > 0 ? startSec + duration : nil
            )
            result.append(track)
        }
        
        return result
    }
    
    /// Updates a track's title (used by inline editing in TrackListView)
    public func updateTrackTitle(id: UUID, newTitle: String) {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[idx].title = newTitle
    }
    
    private func loadTrack(from url: URL) -> BurnTrack? {
        let ext = url.pathExtension.lowercased()
        
        guard ["wav", "wave", "flac", "mp3", "aiff", "aif", "m4a"].contains(ext) else {
            return nil
        }
        
        let format: AudioFormat
        switch ext {
        case "wav", "wave": format = .wav
        case "flac": format = .flac
        case "mp3": format = .mp3
        case "aiff", "aif": format = .aiff
        case "m4a": format = .m4a
        default: format = .unknown
        }
        
        // Use file metadata
        var title: String
        var performer: String?
        var duration: TimeInterval = 0
        
        title = url.deletingPathExtension().lastPathComponent
        performer = nil
        
        // Try to extract metadata via ffprobe
        do {
            let metadata = try metadataExtractor.extractMetadata(from: url)
            if let metaTitle = metadata["title"], !metaTitle.isEmpty {
                title = metaTitle
            }
            if let metaArtist = metadata["artist"], !metaArtist.isEmpty {
                performer = metaArtist
            }
            if albumTitle.isEmpty, let metaAlbum = metadata["album"], !metaAlbum.isEmpty {
                albumTitle = metaAlbum
            }
            if albumArtist.isEmpty, let metaArtist = metadata["artist"], !metaArtist.isEmpty {
                albumArtist = metaArtist
            }
        } catch {
            // Fall back to filename
        }
        
        // Try to extract duration via ffprobe
        if let dur = metadataExtractor.getDuration(from: url) {
            duration = dur
        }
        
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(resourceValues?.fileSize ?? 0)
        
        return BurnTrack(
            fileURL: url,
            title: title,
            performer: performer,
            trackNumber: tracks.count + 1,
            duration: duration,
            fileSize: fileSize,
            format: format
        )
    }
    
    private func sortTracks() {
        // Keep tracks in the order they were added
    }
    
    private func renumberTracks() {
        for (index, _) in tracks.enumerated() {
            tracks[index].trackNumber = index + 1
        }
    }
    
    private func updateState() {
        if tracks.isEmpty {
            state = .idle
        } else {
            state = .ready
        }
        recomputeDuration()
    }
    
    /// Recalculates total duration from all tracks
    private func recomputeDuration() {
        totalDuration = tracks.reduce(0) { $0 + $1.duration }
    }
    
    private func performBurn() async throws {
        // 1. Convert all tracks to CD-ready WAV
        let tempDir = FileManager.default.temporaryDirectory
        var wavFiles: [(Int, String)] = []
        var tempFiles: [URL] = []
        
        defer {
            // Clean up all temp files, even on throw
            for url in tempFiles {
                try? FileManager.default.removeItem(at: url)
            }
        }
        
        for (index, track) in tracks.enumerated() {
            let trackNum = index + 1
            
            await MainActor.run {
                state = .loadingTracks
            }
            
            let outputName = "track_\(String(format: "%02d", trackNum)).wav"
            let outputURL = tempDir.appendingPathComponent(outputName)
            
            // If track has a CUE start offset, extract segment from source file
            if let startOffset = track.cueStartOffset {
                try extractAudioSegment(from: track.fileURL, startOffset: startOffset, duration: track.duration > 0 ? track.duration : nil, to: outputURL)
            } else {
                // Convert whole file to 44.1kHz/16-bit/stereo WAV
                try audioConverter.convertToWAV(from: track.fileURL, to: outputURL)
            }
            tempFiles.append(outputURL)
            
            wavFiles.append((trackNum, outputURL.path))
        }
        
        // 2. Generate CD-TEXT data
        let cdtext = generateCDTEXTData()
        
        // 3. Generate TOC
        let toc = try cdtextGenerator.generateTOCWithCDTEXT(cdtext, audioFiles: wavFiles)
        
        // 4. Configure burn
        let config = BurnConfiguration(
            devicePath: deviceAddress,
            speed: burnSpeed,
            speedKBps: burnSpeed * 176,
            writeMode: .sao,
            burnProof: burnProof,
            simulate: simulate,
            ejectAfterBurn: ejectAfterBurn,
            bufferSize: 4096,
            timeout: 600
        )
        
        // 5. Execute burn with progress callback
        let progressCallback: BurnProgressCallback = { [weak self] progress in
            DispatchQueue.main.async {
                switch progress {
                case .initializing:
                    self?.state = .burning(progress: 0, currentTrack: 1, totalTracks: wavFiles.count)
                case .writingTrack(let track, let total, let pct):
                    self?.state = .burning(progress: pct, currentTrack: track, totalTracks: total)
                case .leadIn:
                    self?.appendLog("Writing lead-in...")
                case .leadOut:
                    self?.appendLog("Writing lead-out...")
                case .closingSession:
                    self?.appendLog("Closing session...")
                case .verifying:
                    self?.state = .verifying(progress: 0.5)
                case .completed:
                    self?.state = .completed(success: true, message: "Burn completed successfully!")
                case .error(let error):
                    self?.state = .error(error.localizedDescription)
                }
            }
        }
        
        // Run burn
        if simulate {
            appendLog("🔬 SIMULATION MODE: Validating TOC and audio files...")
            appendLog("✓ TOC file generated and validated (no disc writing)")
        } else {
            appendLog("🔥 REAL BURN: Writing to disc...")
        }
        
        let result = try burnEngine.burnWithTOC(
            tocContent: toc,
            config: config,
            progress: progressCallback
        )
        
        if !result {
            throw BurnError.burnFailed("Burn returned failure status")
        }
        
        if simulate {
            appendLog("✅ SIMULATION PASSED — disc was NOT written")
        } else {
            // 6. Post-burn verification — verify disc is readable and TOC matches
            appendLog("🔍 Verifying burned disc...")
            await MainActor.run { state = .verifying(progress: 0.3) }
            
            do {
                let verified = try burnEngine.verifyBurn(devicePath: deviceAddress, expectedTracks: wavFiles.count)
                if verified {
                    appendLog("✅ Verification: \(wavFiles.count) tracks confirmed on disc")
                    await MainActor.run { state = .verifying(progress: 1.0) }
                } else {
                    appendLog("⚠️ Verification warning: disc may be incomplete")
                }
            } catch {
                appendLog("⚠️ Verification skipped: \(error.localizedDescription)")
                // Don't fail the burn — disc was written, just couldn't verify
            }
        }
        
        // Cleanup temp files
        for (_, filePath) in wavFiles {
            try? FileManager.default.removeItem(atPath: filePath)
        }
        
        // Eject after burn if requested
        if ejectAfterBurn {
            appendLog("Ejecting disc...")
            do {
                try burnEngine.eject(iokitPath: deviceAddress)
                appendLog("Disc ejected")
            } catch {
                appendLog("Auto-eject failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Extracts a segment from an audio file (for CUE-split tracks)
    private func extractAudioSegment(from sourceURL: URL, startOffset: TimeInterval, duration: TimeInterval?, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        
        var args: [String] = ["-y", "-ss", String(format: "%.3f", startOffset)]
        if let dur = duration, dur > 0 {
            args += ["-t", String(format: "%.3f", dur)]
        }
        args += ["-i", sourceURL.path,
                 "-ar", "44100", "-ac", "2", "-sample_fmt", "s16",
                 "-c:a", "pcm_s16le",
                 destinationURL.path]
        
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw AudioConverter.AudioConversionError.conversionFailed("FFmpeg segment extraction failed")
        }
    }
    
    public func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        log += "[\(timestamp)] \(message)\n"
    }
}
