import Foundation

/// Errors that can occur during CD-TEXT generation
public enum CDTEXTError: LocalizedError {
    case invalidCharacter(String)
    case encodingFailed(String)
    case tooManyTracks(Int)
    case invalidFieldLength(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidCharacter(let details):
            return "Invalid character for CD-TEXT: \(details)"
        case .encodingFailed(let details):
            return "CD-TEXT encoding failed: \(details)"
        case .tooManyTracks(let count):
            return "Too many tracks for CD-TEXT (max 99): \(count)"
        case .invalidFieldLength(let details):
            return "CD-TEXT field length exceeded: \(details)"
        }
    }
}

/// Represents CD-TEXT data for a single track
public struct CDTEXTEntry {
    public let trackNumber: Int
    public let title: String
    public let performer: String?
    public let songwriter: String?
    public let composer: String?
    public let arranger: String?
    public let message: String?
    
    public init(trackNumber: Int, title: String,
                performer: String? = nil,
                songwriter: String? = nil,
                composer: String? = nil,
                arranger: String? = nil,
                message: String? = nil) {
        self.trackNumber = trackNumber
        self.title = title
        self.performer = performer
        self.songwriter = songwriter
        self.composer = composer
        self.arranger = arranger
        self.message = message
    }
}

/// Represents the full CD-TEXT data for an album
public struct CDTEXTData {
    public let albumTitle: String?
    public let albumPerformer: String?
    public let albumSongwriter: String?
    public let genre: String?
    public var tracks: [CDTEXTEntry]
    
    public init(albumTitle: String? = nil, albumPerformer: String? = nil,
                albumSongwriter: String? = nil, genre: String? = nil,
                tracks: [CDTEXTEntry]) {
        self.albumTitle = albumTitle
        self.albumPerformer = albumPerformer
        self.albumSongwriter = albumSongwriter
        self.genre = genre
        self.tracks = tracks
    }
}

/// Generates CD-TEXT blocks and TOC content for cdrdao
public class CDTEXTGenerator {
    public init() {}
    
    /// Validates and sanitizes a string for CD-TEXT encoding
    /// - Parameter input: The input string
    /// - Returns: Sanitized string safe for CD-TEXT
    /// - Throws: CDTEXTError if invalid characters found
    public func sanitizeForCDTEXT(_ input: String) throws -> String {
        var sanitized = ""
        for char in input {
            if let ascii = char.asciiValue, ascii >= 0x20 && ascii <= 0x7E {
                // printable ASCII — accept
                sanitized.append(char)
            } else if char.isASCII {
                // ASCII but control char (0x00-0x1F or 0x7F) — silently drop
                continue
            } else {
                // Try to transliterate common Unicode characters
                switch char {
                case "ą": sanitized.append("a")
                case "ć": sanitized.append("c")
                case "ę": sanitized.append("e")
                case "ł": sanitized.append("l")
                case "ń": sanitized.append("n")
                case "ó": sanitized.append("o")
                case "ś": sanitized.append("s")
                case "ź", "ż": sanitized.append("z")
                case "Ą": sanitized.append("A")
                case "Ć": sanitized.append("C")
                case "Ę": sanitized.append("E")
                case "Ł": sanitized.append("L")
                case "Ń": sanitized.append("N")
                case "Ó": sanitized.append("O")
                case "Ś": sanitized.append("S")
                case "Ź", "Ż": sanitized.append("Z")
                case "ü": sanitized.append("u")
                case "ö": sanitized.append("o")
                case "ä": sanitized.append("a")
                case "Ü": sanitized.append("U")
                case "Ö": sanitized.append("O")
                case "Ä": sanitized.append("A")
                case "ñ": sanitized.append("n")
                case "Ñ": sanitized.append("N")
                case "é": sanitized.append("e")
                case "è": sanitized.append("e")
                case "ê": sanitized.append("e")
                case "ë": sanitized.append("e")
                case "É": sanitized.append("E")
                case "à": sanitized.append("a")
                case "â": sanitized.append("a")
                case "À": sanitized.append("A")
                case "Â": sanitized.append("A")
                case "ç": sanitized.append("c")
                case "Ç": sanitized.append("C")
                case "î": sanitized.append("i")
                case "ï": sanitized.append("i")
                case "Î": sanitized.append("I")
                case "Ï": sanitized.append("I")
                default:
                    throw CDTEXTError.invalidCharacter("Character '\(char)' (U+\(String(format: "%04X", char.asciiValue ?? 0))) is not valid for CD-TEXT")
                }
            }
        }
        return sanitized
    }
    
    /// Generates CD-TEXT in binary format (pack type 0x80-0x8F)
    /// This produces raw CD-TEXT data suitable for writing to CD subcode
    /// - Parameter data: CD-TEXT data
    /// - Returns: Binary CD-TEXT bytes
    public func generateBinaryCDTEXT(_ data: CDTEXTData) throws -> Data {
        var output = Data()
        
        // CD-TEXT pack header: 18 bytes per pack
        // Pack type 0x80: Album/Track title
        // Pack type 0x81: Performer
        // Pack type 0x82: Songwriter
        // Pack type 0x83: Composer
        // Pack type 0x84: Arranger
        // Pack type 0x85: Message
        // Pack type 0x8E: Genre
        // Pack type 0x8F: TOC (position info)
        
        // Generate title packs (pack type 0x80)
        // Track 0 = album title, Track 1+ = per-track title
        try generatePacks(type: 0x80, data: data, output: &output)
        try generatePacks(type: 0x81, data: data, output: &output, field: \.performer)
        try generatePacks(type: 0x82, data: data, output: &output, field: \.songwriter)
        
        return output
    }
    
    /// Normalizes CD-TEXT data so cdrdao consistency rules are satisfied:
    /// If a CD-TEXT field (PERFORMER, SONGWRITER, etc.) is defined for ANY
    /// track or in the global section, it MUST be defined for ALL tracks
    /// AND in the global section.
    /// Missing values are filled from the global/album-level default, or empty string.
    private func normalizeCDTEXT(_ cdtext: inout CDTEXTData) throws {
        let globalPerformer = cdtext.albumPerformer
        let globalSongwriter = cdtext.albumSongwriter
        
        // Check if any track has performer/songwriter set
        let anyHasPerformer = cdtext.tracks.contains { $0.performer != nil } || globalPerformer != nil
        let anyHasSongwriter = cdtext.tracks.contains { $0.songwriter != nil } || globalSongwriter != nil
        
        // Normalize tracks: fill missing fields from global defaults
        cdtext.tracks = try cdtext.tracks.map { track in
            let performer: String?
            if track.performer != nil {
                performer = track.performer
            } else if anyHasPerformer {
                // Fill from global or empty
                performer = globalPerformer ?? ""
            } else {
                performer = nil
            }
            
            let songwriter: String?
            if track.songwriter != nil {
                songwriter = track.songwriter
            } else if anyHasSongwriter {
                songwriter = globalSongwriter ?? ""
            } else {
                songwriter = nil
            }
            
            return CDTEXTEntry(
                trackNumber: track.trackNumber,
                title: track.title,
                performer: performer,
                songwriter: songwriter,
                composer: track.composer,
                arranger: track.arranger,
                message: track.message
            )
        }
    }
    
    /// Generates a TOC file string for cdrdao with CD-TEXT
    /// - Parameters:
    ///   - cdtext: CD-TEXT data
    ///   - audioFiles: Array of (trackNumber, filePath) tuples
    /// - Returns: TOC file content as a string
    public func generateTOCWithCDTEXT(_ cdtext: CDTEXTData, audioFiles: [(Int, String)]) throws -> String {
        var normalized = cdtext
        try normalizeCDTEXT(&normalized)
        
        var toc = ""
        
        toc += "// CD-TEXT enabled TOC file generated by Spalam Sie\n"
        toc += "// https://github.com/user/spalam-sie\n\n"
        
        // Disc type MUST come before global CD_TEXT
        toc += "CD_DA\n"
        
        // Global CD-TEXT block (album-level)
        if normalized.albumTitle != nil || normalized.albumPerformer != nil ||
           normalized.albumSongwriter != nil ||
           normalized.tracks.contains(where: { $0.performer != nil }) ||
           normalized.tracks.contains(where: { $0.songwriter != nil }) {
            let safeTitle = try sanitizeForCDTEXT(normalized.albumTitle ?? "")
            toc += "CD_TEXT {\n"
            toc += "    LANGUAGE_MAP {\n"
            toc += "\t0 : EN\n"
            toc += "    }\n"
            toc += "    LANGUAGE 0 {\n"
            if !safeTitle.isEmpty {
                toc += "\tTITLE \"\(escapeTOCString(safeTitle))\"\n"
            }
            
            if let performer = normalized.albumPerformer {
                let safePerformer = try sanitizeForCDTEXT(performer)
                toc += "\tPERFORMER \"\(escapeTOCString(safePerformer))\"\n"
            } else if normalized.tracks.contains(where: { $0.performer != nil }) {
                // If any track has performer, global must too — use first track's
                if let firstPerformer = normalized.tracks.first(where: { $0.performer != nil })?.performer {
                    let safe = try sanitizeForCDTEXT(firstPerformer)
                    toc += "\tPERFORMER \"\(escapeTOCString(safe))\"\n"
                }
            }
            
            if let songwriter = normalized.albumSongwriter {
                let safe = try sanitizeForCDTEXT(songwriter)
                toc += "\tSONGWRITER \"\(escapeTOCString(safe))\"\n"
            } else if normalized.tracks.contains(where: { $0.songwriter != nil }) {
                if let firstSw = normalized.tracks.first(where: { $0.songwriter != nil })?.songwriter {
                    let safe = try sanitizeForCDTEXT(firstSw)
                    toc += "\tSONGWRITER \"\(escapeTOCString(safe))\"\n"
                }
            }
            
            toc += "    }\n"
            toc += "}\n"
        }
        
        toc += "\n"
        
        // Track entries
        for (i, filePath) in audioFiles.enumerated() {
            let trackNumber = i + 1
            let entry = normalized.tracks.first { $0.trackNumber == trackNumber }
            let path = filePath.1
            
            toc += "TRACK AUDIO\n"
            
            // Per-track CD-TEXT (BEFORE AUDIOFILE, no LANGUAGE_MAP)
            if let e = entry {
                toc += "    CD_TEXT {\n"
                toc += "\tLANGUAGE 0 {\n"
                
                let safeTitle = try sanitizeForCDTEXT(e.title)
                toc += "\t    TITLE \"\(escapeTOCString(safeTitle))\"\n"
                
                if let performer = e.performer {
                    let safe = try sanitizeForCDTEXT(performer)
                    toc += "\t    PERFORMER \"\(escapeTOCString(safe))\"\n"
                }
                
                if let songwriter = e.songwriter {
                    let safe = try sanitizeForCDTEXT(songwriter)
                    toc += "\t    SONGWRITER \"\(escapeTOCString(safe))\"\n"
                }
                
                toc += "\t}\n"
                toc += "    }\n"
            }
            
            // AUDIOFILE uses MSF format for start (00:00:00 = start of file)
            toc += "    AUDIOFILE \"\(escapeTOCString(path))\" 00:00:00\n"
            toc += "\n"
        }
        
        return toc
    }
    
    // MARK: - Private Helpers
    
    /// Escapes special characters in TOC file strings
    private func escapeTOCString(_ str: String) -> String {
        var escaped = str
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "")
        escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
        return escaped
    }
    
    /// Generates CD-TEXT packs for a given field
    private func generatePacks(type: UInt8, data: CDTEXTData,
                              output: inout Data,
                              field: KeyPath<CDTEXTEntry, String?>? = nil) throws {
        // Pack structure (18 bytes):
        // Byte 0: Pack type (0x80-0x8F)
        // Byte 1: Track number (0=album, 1-99=tracks)
        // Byte 2-17: 16 characters of text (ISO 8859-1)
        
        let entries: [(trackNumber: Int, text: String)]
        
        if type == 0x80 { // Title
            var all: [(Int, String)] = []
            if let albumTitle = data.albumTitle {
                all.append((0, try sanitizeForCDTEXT(albumTitle)))
            }
            for track in data.tracks {
                all.append((track.trackNumber, try sanitizeForCDTEXT(track.title)))
            }
            entries = all
        } else if let field = field {
            var all: [(Int, String)] = []
            // Check album-level field
            switch field {
            case \.performer:
                if let performer = data.albumPerformer {
                    all.append((0, try sanitizeForCDTEXT(performer)))
                }
            case \.songwriter:
                if let sw = data.albumSongwriter {
                    all.append((0, try sanitizeForCDTEXT(sw)))
                }
            default:
                break
            }
            for track in data.tracks {
                if let text = track[keyPath: field] {
                    all.append((track.trackNumber, try sanitizeForCDTEXT(text)))
                }
            }
            entries = all
        } else {
            entries = []
        }
        
        for (trackNumber, text) in entries {
            // Pad or truncate to 16 characters
            let padded = text.padding(toLength: 16, withPad: " ", startingAt: 0)
            guard let textData = padded.prefix(16).data(using: .isoLatin1) else {
                throw CDTEXTError.encodingFailed("Failed to encode text '\(text)'")
            }
            
            var pack = Data()
            pack.append(type)
            pack.append(UInt8(trackNumber))
            pack.append(textData)
            
            // Ensure exactly 18 bytes
            if pack.count < 18 {
                pack.append(Data(count: 18 - pack.count))
            }
            
            output.append(pack)
        }
    }
    
    /// Creates CDTEXTData from parsed metadata dictionary and optional CUE data
    /// - Parameters:
    ///   - metadata: Dictionary of metadata (from MetadataExtractor)
    ///   - cueData: Optional parsed CUE data (takes precedence for track info)
    ///   - filePaths: Array of file paths in track order
    /// - Returns: CDTEXTData ready for TOC generation
    public func createCDTEXTData(from metadata: [String: String],
                                 cueData: ParsedCUE? = nil,
                                 filePaths: [String]) throws -> CDTEXTData {
        let albumTitle = cueData?.title ?? metadata["album"]
        let albumPerformer = cueData?.performer ?? metadata["artist"]
        let albumSongwriter = cueData?.songwriter
        let genre = metadata["genre"]
        
        var entries: [CDTEXTEntry] = []
        
        for (index, _) in filePaths.enumerated() {
            let trackNumber = index + 1
            
            if let cue = cueData, trackNumber <= cue.tracks.count {
                let cueTrack = cue.tracks[trackNumber - 1]
                let entry = CDTEXTEntry(
                    trackNumber: trackNumber,
                    title: cueTrack.title ?? metadata["track_\(trackNumber)_title"] ?? "Track \(trackNumber)",
                    performer: cueTrack.performer,
                    songwriter: cueTrack.songwriter,
                    composer: cueTrack.composer,
                    arranger: cueTrack.arranger,
                    message: cueTrack.message
                )
                entries.append(entry)
            } else {
                let entry = CDTEXTEntry(
                    trackNumber: trackNumber,
                    title: metadata["track_\(trackNumber)_title"] ?? "Track \(trackNumber)",
                    performer: metadata["track_\(trackNumber)_artist"],
                    songwriter: metadata["track_\(trackNumber)_songwriter"]
                )
                entries.append(entry)
            }
        }
        
        return CDTEXTData(
            albumTitle: albumTitle,
            albumPerformer: albumPerformer,
            albumSongwriter: albumSongwriter,
            genre: genre,
            tracks: entries
        )
    }
}
