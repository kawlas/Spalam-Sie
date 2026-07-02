import Foundation

/// Extracts metadata from audio files (artist, title, album, etc.) using ffprobe
public class MetadataExtractor {
    public init() {}
    
    /// Extracts duration of an audio file in seconds
    /// - Parameter fileURL: URL of the audio file
    /// - Returns: Duration in seconds, or nil if unavailable
    public func getDuration(from fileURL: URL) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "csv=p=0",
            fileURL.path
        ]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        return Double(output)
    }
    
    /// Extracts metadata from an audio file
    /// - Parameter fileURL: URL of the audio file
    /// - Returns: A dictionary containing metadata keys and values
    /// - Throws: MetadataExtractionError if extraction fails
    public func extractMetadata(from fileURL: URL) throws -> [String: String] {
        // Check if file exists
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            throw MetadataExtractionError.fileNotFound
        }
        
        // Use ffprobe to extract metadata in JSON format
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        process.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            fileURL.path
        ]
        
        // Set up pipes to capture output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Run the process
        try process.run()
        process.waitUntilExit()
        
        // Check if the process succeeded
        if process.terminationReason == .exit && process.terminationStatus == 0 {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            
            // Parse the JSON to extract metadata
            let metadata = try parseMetadataFromJSON(output)
            return metadata
        } else {
            // Get error output
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw MetadataExtractionError.extractionFailed("ffprobe failed: \(errorMessage)")
        }
    }
    
    /// Parses FFprobe JSON output to extract relevant metadata
    private func parseMetadataFromJSON(_ jsonString: String) throws -> [String: String] {
        guard let data = jsonString.data(using: .utf8) else {
            throw MetadataExtractionError.invalidData("Failed to convert JSON string to data")
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                var metadata: [String: String] = [:]
                
                // Extract format-level metadata (tags)
                if let format = json["format"] as? [String: Any],
                   let tags = format["tags"] as? [String: String] {
                    // Map common metadata fields
                    if let title = tags["title"] ?? tags["TITLE"] ?? tags["Title"] {
                        metadata["title"] = title
                    }
                    if let artist = tags["artist"] ?? tags["ARTIST"] ?? tags["Artist"] {
                        metadata["artist"] = artist
                    }
                    if let album = tags["album"] ?? tags["ALBUM"] ?? tags["Album"] {
                        metadata["album"] = album
                    }
                    if let genre = tags["genre"] ?? tags["GENRE"] ?? tags["Genre"] {
                        metadata["genre"] = genre
                    }
                    if let year = tags["date"] ?? tags["DATE"] ?? tags["year"] ?? tags["YEAR"] {
                        metadata["year"] = year
                    }
                    if let track = tags["track"] ?? tags["TRACK"] ?? tags["tracknumber"] ?? tags["TRACKNUMBER"] {
                        metadata["trackNumber"] = track
                    }
                    if let composer = tags["composer"] ?? tags["COMPOSER"] ?? tags["Composer"] {
                        metadata["composer"] = composer
                    }
                }
                
                // If we didn't find metadata in format tags, try the first audio stream
                if metadata.isEmpty,
                   let streams = json["streams"] as? [[String: Any]] {
                    for stream in streams {
                        if let codecType = stream["codec_type"] as? String, codecType == "audio",
                           let tags = stream["tags"] as? [String: String] {
                            // Map common metadata fields from audio stream
                            if let title = tags["title"] ?? tags["TITLE"] ?? tags["Title"] {
                                metadata["title"] = title
                            }
                            if let artist = tags["artist"] ?? tags["ARTIST"] ?? tags["Artist"] {
                                metadata["artist"] = artist
                            }
                            if let album = tags["album"] ?? tags["ALBUM"] ?? tags["Album"] {
                                metadata["album"] = album
                            }
                            if let genre = tags["genre"] ?? tags["GENRE"] ?? tags["Genre"] {
                                metadata["genre"] = genre
                            }
                            if let year = tags["date"] ?? tags["DATE"] ?? tags["year"] ?? tags["YEAR"] {
                                metadata["year"] = year
                            }
                            if let track = tags["track"] ?? tags["TRACK"] ?? tags["tracknumber"] ?? tags["TRACKNUMBER"] {
                                metadata["trackNumber"] = track
                            }
                            if let composer = tags["composer"] ?? tags["COMPOSER"] ?? tags["Composer"] {
                                metadata["composer"] = composer
                            }
                            break // Use first audio stream with metadata
                        }
                    }
                }
                
                return metadata
            } else {
                throw MetadataExtractionError.invalidData("Unexpected JSON structure")
            }
        } catch {
            throw MetadataExtractionError.invalidData("Failed to parse JSON: \(error.localizedDescription)")
        }
    }
    
    /// Convenience method to get a specific metadata value
    public func getMetadataValue(for key: String, from fileURL: URL) throws -> String? {
        let metadata = try extractMetadata(from: fileURL)
        return metadata[key.lowercased()]
    }
    
    /// Errors that can occur during metadata extraction
    public enum MetadataExtractionError: LocalizedError {
        case fileNotFound
        case extractionFailed(String)
        case invalidData(String)
        case noMetadataFound
        
        public var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Audio file not found"
            case .extractionFailed(let details):
                return "Metadata extraction failed: \(details)"
            case .invalidData(let details):
                return "Invalid data encountered: \(details)"
            case .noMetadataFound:
                return "No metadata found in the audio file"
            }
        }
    }
}
