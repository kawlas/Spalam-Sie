import Foundation

/// Handles audio format detection of audio format conversion to WAV (44.1kHz, 16-bit stereo) for CD burning
public class AudioConverter {
    public init() {}
    
    /// Converts an audio file to WAV format suitable for audio CD (44.1kHz, 16-bit stereo)
    /// - Parameters:
    ///   - sourceURL: URL of the source audio file
    ///   - destinationURL: URL where the converted WAV file will be saved
    /// - Throws: AudioConversionError if conversion fails
    public func convertToWAV(from sourceURL: URL, to destinationURL: URL) throws {
        // Check if source file exists
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw AudioConversionError.sourceFileNotFound
        }
        
        // Remove any existing destination file
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        // Always use ffmpeg — guarantees 44.1kHz / 16-bit / stereo dla CD-DA
        // Nie używamy lame --decode (zachowuje 48kHz) ani copy+validate
        try convertWithFFmpeg(from: sourceURL, to: destinationURL)
    }
    
    // MARK: - Private Conversion Methods
    
    /// Konwertuje dowolny format audio na WAV (44.1kHz, 16-bit, stereo) przez ffmpeg.
    /// Jest to JEDYNA metoda konwersji — gwarantuje poprawne parametry CD-DA za każdym razem.
    /// Nie używamy lame --decode (zachowuje sample rate źródła np. 48kHz)
    /// ani copyAndValidateWAV (kopiuje bez konwersji).
    private func convertWithFFmpeg(from sourceURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = [
            "-y",                  // Overwrite output file if it exists
            "-i", sourceURL.path,  // Input file
            "-ar", "44100",        // Sample rate: 44.1kHz (CD-DA)
            "-ac", "2",            // Channels: stereo
            "-sample_fmt", "s16",  // Sample format: 16-bit signed integer
            "-c:a", "pcm_s16le",   // Explicit WAV codec (pcm_s16le = 16-bit little-endian)
            destinationURL.path    // Output file
        ]
        
        // Discard stdout (ffmpeg reports progress there, we don't need it)
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        
        // Run the process
        try process.run()
        process.waitUntilExit()
        
        // Check if the process succeeded
        if process.terminationReason == .exit && process.terminationStatus == 0 {
            // Verify the output file exists and has reasonable size
            if FileManager.default.fileExists(atPath: destinationURL.path),
               let attributes = try? FileManager.default.attributesOfItem(atPath: destinationURL.path),
               let fileSize = attributes[.size] as? UInt64,
               fileSize > 0 {
                return // Success
            } else {
                throw AudioConversionError.conversionFailed("FFmpeg produced empty output file")
            }
        } else {
            // Get error output
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw AudioConversionError.conversionFailed("FFmpeg failed: \(errorMessage)")
        }
    }
    
    /// Validates that a WAV file is 44.1kHz, 16-bit stereo
    private func validateWAVFormat(at fileURL: URL) throws -> Bool {
        let process = Process()
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        process.arguments = [
            "-v", "error",
            "-select_streams", "a:0",
            "-show_entries", "stream=sample_rate,channels,bits_per_sample",
            "-of", "csv=p=0",
            fileURL.path
        ]
        
        try process.run()
        process.waitUntilExit()
        
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Expected: "44100,2,16"
        return output == "44100,2,16"
    }
    
    // MARK: - Error Types
    
    /// Errors that can occur during audio conversion
    public enum AudioConversionError: LocalizedError {
        case sourceFileNotFound
        case conversionFailed(String)
        case invalidOutputFormat
        
        public var errorDescription: String? {
            switch self {
            case .sourceFileNotFound:
                return "Source audio file not found"
            case .conversionFailed(let details):
                return "Audio conversion failed: \(details)"
            case .invalidOutputFormat:
                return "Output file is not in the expected format (44.1kHz, 16-bit stereo WAV)"
            }
        }
    }
}
