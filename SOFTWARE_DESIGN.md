# Spalam Sie - Software Design

## Architecture Overview

Spalam Sie follows a modular, layered architecture designed for maintainability, testability, and separation of concerns. The application is divided into distinct modules, each with a single responsibility.

### Modules

1. **App** (`Sources/App/`)
   - Contains the SwiftUI interface and application logic
   - Handles user interaction, view state, and coordinates between other modules
   - Entry point of the application

2. **Audio** (`Sources/Audio/`)
   - Responsible for audio format conversion
   - Converts various audio formats (FLAC, MP3, WAV, etc.) to CD-standard WAV (44.1kHz, 16-bit stereo)
   - Uses appropriate command-line tools (flac, lame, ffmpeg) for each format

3. **Metadata** (`Sources/Metadata/`)
   - Extracts metadata from audio files (title, artist, album, genre, year, track number)
   - Uses ffprobe to read metadata from various audio formats
   - Provides a unified interface regardless of source format

4. **Parsing** (`Sources/Parsing/`)
   - Parses cue sheets and other descriptor files
   - Handles CUE format parsing with support for various commands and options
   - Extracts track information, file references, and metadata cues

5. **CDText** (`Sources/CDText/`)
   - Generates CD-TEXT data from metadata
   - Creates properly formatted CD-TEXT blocks for inclusion in TOC files
   - Handles text
   - Ensures compatibility with cdrdao's TOC format expectations

6. **Burning** (`Sources/Burning/`)
   - Interface to cdrdao for CD burning operations
   - Handles device detection and selection
   - Manages the burning process with progress reporting
   - Implements error handling and recovery options

7. **Utilities** (`Sources/Utilities/`)
   - Shared utility functions and helpers
   - Logging system
   - Configuration management
   - File system helpers
   - String manipulation utilities

8. **Shared** (`Sources/Shared/`)
   - Common data models, protocols, and constants used across modules
   - Defines standard interfaces for communication between modules
   - Contains value objects like Track, Album, BurnJob, etc.

### Data Flow

1. **Input Acquisition**
   - User adds files via drag-drop, file dialog, or folder scan
   - Files are passed to the App module for initial processing

2. **Format Detection & Routing**
   - App determines file types and routes them to appropriate processors
   - Audio files go to Audio module for conversion
   - CUE files go to Parsing module for interpretation
   - Other files may be handled specially or rejected

3. **Processing Pipeline**
   - Audio Module: Converts source audio to 44.1kHz/16-bit stereo WAV
   - Metadata Module: Extracts metadata from source files
   - Parsing Module: Interprets CUE sheets to identify tracks and gaps
   - CDText Module: Generates CD-TEXT blocks from collected metadata
   - All processed data flows to the burning preparation stage

4. **Burn Preparation**
   - Temporary working directory created
   - All audio tracks converted to WAV format
   - TOC (Table of Contents) file generated with CD-TEXT blocks
   - Reference to audio files embedded in TOC

5. **Burning Process**
   - Burns executes with the generated TOC file
   - Progress monitored and reported back to UI
   - Post-burn verification options available
   - Cleanup of temporary files

### Key Design Principles

1. **Separation of Concerns**
   - Each module has a single, well-defined responsibility
   - Modules communicate through clearly defined interfaces
   - Minimizes coupling and maximizes cohesion

2. **Testability**
   - Each module can be unit tested in isolation
   - Dependencies are injected where appropriate
   - Mock objects can be used for testing complex interactions

3. **Error Handling**
   - Comprehensive error handling throughout
   - Meaningful error messages for users
   - Graceful degradation when possible
   - Proper resource cleanup on errors

4. **Extensibility**
   - New audio formats can be added by extending AudioConverter
   - New metadata sources can be plugged into MetadataExtractor
   - Additional subtitle/formats can be supported in Parsing module

5. **Performance**
   - Efficient use of system resources
   - Parallel processing where beneficial (e.g., multi-track conversion)
   - Memory-efficient streaming of large files when possible

### Technology Choices

- **SwiftUI**: Chosen for modern, declarative UI development with excellent macOS integration
- **Command Line Tools**: Leveraging existing, well-tested tools (ffmpeg, flac, lame, cdrdao) rather than reimplementing complex algorithms
- **Modular Design**: Facilitates testing, maintenance, and future enhancements
- **Async/Await**: Utilizing modern Swift concurrency for responsive UI

### Interface Contracts

#### AudioConverter Protocol
```swift
protocol AudioConverter {
    func convertToWAV(from sourceURL: URL, to destinationURL: URL) throws
}
```

#### MetadataExtractor Protocol
```swift
protocol MetadataExtractor {
    func extractMetadata(from fileURL: URL) throws -> [String: String]
    func getMetadataValue(for key: String, from fileURL: URL) throws -> String?
}
```

#### CUEParser Protocol
```swift
protocol CUEParser {
    func parseCUE(from url: URL) throws -> ParsedCUE
    func validateCUE(_ parsed: ParsedCUE) throws
}
```

#### BurnEngine Protocol
```swift
protocol BurnEngine {
    func detectDevices() throws -> [OpticalDrive]
    func burnImage(tocURL: URL, to drive: OpticalDrive, options: BurnOptions) throws -> BurnProgress
    func cancelBurn()
}
```

## Data Models

### Track
- title: String
- artist: String
- album: String
- duration: TimeInterval
- fileURL: URL
- trackNumber: Int
- isAudio: Bool
- hasPreGap: Bool
- preGapDuration: TimeInterval

### Album
- title: String
- artist: String
- year: String?
- genre: String?
- tracks: [Track]
- totalDuration: TimeInterval

### BurnJob
- source: BurnSource (files, folder, CUE)
- temporaryDirectory: URL
- tocFileURL: URL
- audioFiles: [URL]
- selectedDrive: OpticalDrive?
- burnOptions: BurnOptions
- status: BurnStatus
- progress: Double (0.0 to 1.0)

## Security Considerations

- All file operations use security-scoped URLs when required
- Input validation prevents path traversal attacks
- Temporary files are created in secure, unique locations
- Privilege separation considered for future enhancement (privileged helper tool for burning if needed)

## Localization & Internationalization

- All user-facing strings marked for localization
- Support for Unicode metadata (UTF-8 encoding)
- Right-to-left language support in UI where appropriate
- Formatters respect user locale preferences

## Accessibility

- Full VoiceOver support
- Keyboard navigation for all controls
- Appropriate accessibility labels and hints
- Dynamic type support for text scaling
- Color contrast compliance

This design provides a solid foundation for a reliable, maintainable, and extensible CD burning application that meets the needs of users while adhering to software engineering best practices.
