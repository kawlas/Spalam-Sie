import Foundation

/// Represents a parsed CUE sheet
public struct ParsedCUE {
    public let fileName: String
    public let fileType: String
    public let tracks: [CueTrack]
    public let catalog: String?        // CATALOG
    public let cdTextFile: String?     // CDTEXTFILE
    public let performer: String?      // PERFORMER (album artist)
    public let title: String?          // TITLE (album title)
    public let songwriter: String?     // SONGWRITER
    public let remComments: [String]   // REM comments
    
    public init(fileName: String, fileType: String, tracks: [CueTrack],
                catalog: String? = nil, cdTextFile: String? = nil,
                performer: String? = nil, title: String? = nil,
                songwriter: String? = nil, remComments: [String] = []) {
        self.fileName = fileName
        self.fileType = fileType
        self.tracks = tracks
        self.catalog = catalog
        self.cdTextFile = cdTextFile
        self.performer = performer
        self.title = title
        self.songwriter = songwriter
        self.remComments = remComments
    }
}

/// Represents a track in a CUE sheet
public struct CueTrack {
    public var number: Int
    public var mode: String
    public var performer: String?    // Track artist
    public var title: String?        // Track title
    public var songwriter: String?   // Track songwriter
    public var composer: String?     // Track composer
    public var arranger: String?     // Track arranger
    public var message: String?      // Track message
    public var flags: [String]       // FLAGS (DCP, PRE, 4CH, SCMS)
    public var isrc: String?         // ISRC
    public var pregap: TimeInterval? // Pregap in seconds
    public var postgap: TimeInterval? // Postgap in seconds
    public var indices: [Int: TimeInterval] // INDEX entries (00, 01, 02, etc.) in seconds
    
    public init(number: Int, mode: String, performer: String? = nil,
                title: String? = nil, songwriter: String? = nil,
                composer: String? = nil, arranger: String? = nil,
                message: String? = nil, flags: [String] = [],
                isrc: String? = nil, pregap: TimeInterval? = nil,
                postgap: TimeInterval? = nil, indices: [Int: TimeInterval] = [:]) {
        self.number = number
        self.mode = mode
        self.performer = performer
        self.title = title
        self.songwriter = songwriter
        self.composer = composer
        self.arranger = arranger
        self.message = message
        self.flags = flags
        self.isrc = isrc
        self.pregap = pregap
        self.postgap = postgap
        self.indices = indices
    }
}

/// Errors that can occur during CUE parsing
public enum CUEParserError: LocalizedError {
    case fileNotFound
    case invalidFormat(String)
    case missingRequiredField(String)
    case unsupportedCommand(String)
    case parseFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "CUE file not found"
        case .invalidFormat(let details):
            return "Invalid CUE format: \(details)"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .unsupportedCommand(let command):
            return "Unsupported command: \(command)"
        case .parseFailed(let details):
            return "Failed to parse CUE: \(details)"
        }
    }
}

/// Parses CUE sheet files
public class CUEParser {
    public init() {}
    
    /// Parses a CUE sheet file
    /// - Parameter url: URL to the CUE file
    /// - Returns: Parsed CUE structure
    /// - Throws: CUEParserError if parsing fails
    public func parseCUE(from url: URL) throws -> ParsedCUE {
        if !FileManager.default.fileExists(atPath: url.path) {
            throw CUEParserError.fileNotFound
        }
        
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CUEParserError.parseFailed("Failed to read file: \(error.localizedDescription)")
        }
        
        return try parseCUEContent(content, fileURL: url)
    }
    
    /// Parses CUE content from a string
    /// - Parameters:
    ///   - content: The CUE file content as a string
    ///   - fileURL: The URL of the file (for resolving relative paths)
    /// - Returns: Parsed CUE structure
    /// - Throws: CUEParserError if parsing fails
    public func parseCUEContent(_ content: String, fileURL: URL) throws -> ParsedCUE {
        let lines = content.components(separatedBy: .newlines)
        var fileName: String = ""
        var fileType: String = ""
        var tracks: [CueTrack] = []
        var currentTrack: CueTrack? = nil
        var currentTrackNumber: Int = 0
        
        var catalog: String? = nil
        var cdTextFile: String? = nil
        var albumPerformer: String? = nil
        var albumTitle: String? = nil
        var albumSongwriter: String? = nil
        var remComments: [String] = []
        
        for (lineNumber, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            let components = trimmed.components(separatedBy: .whitespaces)
            guard let command = components.first?.uppercased(),
                  components.count > 1 else {
                continue
            }
            
            let arguments = Array(components[1...]).joined(separator: " ")
            
            switch command {
            case "CATALOG":
                catalog = unquoteString(arguments)
                
            case "CDTEXTFILE":
                cdTextFile = unquoteString(arguments)
                
            case "PERFORMER":
                if currentTrackNumber > 0 {
                    if var track = currentTrack {
                        track.performer = unquoteString(arguments)
                        currentTrack = track
                    }
                } else {
                    albumPerformer = unquoteString(arguments)
                }
                
            case "TITLE":
                if currentTrackNumber > 0 {
                    if var track = currentTrack {
                        track.title = unquoteString(arguments)
                        currentTrack = track
                    }
                } else {
                    albumTitle = unquoteString(arguments)
                }
                
            case "SONGWRITER":
                if currentTrackNumber > 0 {
                    if var track = currentTrack {
                        track.songwriter = unquoteString(arguments)
                        currentTrack = track
                    }
                } else {
                    albumSongwriter = unquoteString(arguments)
                }
                
            case "FILE":
                if let track = currentTrack {
                    tracks.append(track)
                    currentTrack = nil
                }
                
                let fileComponents = arguments.components(separatedBy: .whitespaces)
                guard fileComponents.count >= 2 else {
                    throw CUEParserError.invalidFormat("Invalid FILE command at line \(lineNumber + 1): \(arguments)")
                }
                
                let quotedFileName = fileComponents[0]
                let type = fileComponents[1]
                
                fileName = unquoteString(quotedFileName)
                fileType = type.uppercased()
                
            case "TRACK":
                if let track = currentTrack {
                    tracks.append(track)
                }
                
                let trackComponents = arguments.components(separatedBy: .whitespaces)
                guard trackComponents.count >= 2,
                      let trackNumber = Int(trackComponents[0]) else {
                    throw CUEParserError.invalidFormat("Invalid TRACK command at line \(lineNumber + 1): \(arguments)")
                }
                
                currentTrackNumber = trackNumber
                let mode = trackComponents[1].uppercased()
                
                currentTrack = CueTrack(number: trackNumber, mode: mode)
                
            case "COMPOSER":
                if var track = currentTrack {
                    track.composer = unquoteString(arguments)
                    currentTrack = track
                }
                
            case "ARRANGER":
                if var track = currentTrack {
                    track.arranger = unquoteString(arguments)
                    currentTrack = track
                }
                
            case "MESSAGE":
                if var track = currentTrack {
                    track.message = unquoteString(arguments)
                    currentTrack = track
                }
                
            case "FLAGS":
                if var track = currentTrack {
                    let flagComponents = arguments.components(separatedBy: .whitespaces)
                    track.flags = flagComponents.map { $0.uppercased() }
                    currentTrack = track
                }
                
            case "ISRC":
                if var track = currentTrack {
                    track.isrc = unquoteString(arguments)
                    currentTrack = track
                }
                
            case "PREGAP":
                if var track = currentTrack {
                    track.pregap = parseTime(arguments)
                    currentTrack = track
                }
                
            case "POSTGAP":
                if var track = currentTrack {
                    track.postgap = parseTime(arguments)
                    currentTrack = track
                }
                
            case "INDEX":
                if var track = currentTrack {
                    let indexComponents = arguments.components(separatedBy: .whitespaces)
                    guard indexComponents.count >= 2,
                          let indexNumber = Int(indexComponents[0]) else {
                        throw CUEParserError.invalidFormat("Invalid INDEX command at line \(lineNumber + 1): \(arguments)")
                    }
                    
                    let timeStr = Array(indexComponents[1...]).joined(separator: " ")
                    track.indices[indexNumber] = parseTime(timeStr)
                    currentTrack = track
                }
                
            case "REM":
                remComments.append(arguments)
                
            default:
                break
            }
        }
        
        if let track = currentTrack {
            tracks.append(track)
        }
        
        if tracks.isEmpty {
            throw CUEParserError.invalidFormat("No tracks found in CUE file")
        }
        
        guard !fileName.isEmpty else {
            throw CUEParserError.missingRequiredField("FILE")
        }
        
        return ParsedCUE(
            fileName: fileName,
            fileType: fileType,
            tracks: tracks,
            catalog: catalog,
            cdTextFile: cdTextFile,
            performer: albumPerformer,
            title: albumTitle,
            songwriter: albumSongwriter,
            remComments: remComments
        )
    }
    
    /// Unquotes a string if it's surrounded by quotes
    private func unquoteString(_ str: String) -> String {
        var result = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("\"") && result.hasSuffix("\"") && result.count >= 2 {
            let start = result.index(after: result.startIndex)
            let end = result.index(before: result.endIndex)
            result = String(result[start..<end])
        }
        return result
    }
    
    /// Parses a time string in MM:SS:FF format to seconds
    /// - Parameter timeString: Time string in MM:SS:FF format
    /// - Returns: Time in seconds as Double
    private func parseTime(_ timeString: String) -> TimeInterval {
        let components = timeString.components(separatedBy: ":")
        guard components.count == 3 else { return 0 }
        
        let minutes = Double(components[0]) ?? 0
        let seconds = Double(components[1]) ?? 0
        let frames = Double(components[2]) ?? 0
        
        return minutes * 60 + seconds + (frames / 75.0)
    }
    
    /// Validates a parsed CUE for common issues
    /// - Parameter parsed: The parsed CUE to validate
    /// - Throws: CUEParserError if validation fails
    public func validateCUE(_ parsed: ParsedCUE) throws {
        guard !parsed.tracks.isEmpty else {
            throw CUEParserError.invalidFormat("No tracks defined")
        }
        
        for (index, track) in parsed.tracks.enumerated() {
            if track.number != index + 1 {
                throw CUEParserError.invalidFormat(
                    "Track numbers must be sequential starting from 1. Found \(track.number) at position \(index + 1)"
                )
            }
        }
        
        for track in parsed.tracks {
            guard track.indices[1] != nil else {
                throw CUEParserError.invalidFormat("Track \(track.number) is missing INDEX 01")
            }
        }
    }
}
