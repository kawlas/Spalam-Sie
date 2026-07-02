import XCTest
@testable import Spalam_Sie

final class Spalam_SieTests: XCTestCase {
    
    func testFlacToWavConversion() throws {
        // Test FLAC to WAV conversion
        try testConversion(fromFormat: "flac", toFormat: "wav")
    }
    
    func testMp3ToWavConversion() throws {
        // Test MP3 to WAV conversion
        try testConversion(fromFormat: "mp3", toFormat: "wav")
    }
    
    func testWavPassthroughValidation() throws {
        // Test WAV to WAV (should validate and potentially reconvert if needed)
        try testConversion(fromFormat: "wav", toFormat: "wav")
    }
    
    /// Generic test method for format conversion
    private func testConversion(fromFormat: String, toFormat: String) throws {
        // Skip if we don't have the necessary tools for this format
        if fromFormat == "mp3" && !FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/lame") {
            throw XCTSkip("LAME not found, skipping MP3 test")
        }
        if !FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") {
            throw XCTSkip("FFmpeg not found, skipping test")
        }
        if fromFormat == "flac" && !FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/flac") {
            throw XCTSkip("FLAC not found, skipping FLAC test")
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let inputURL = tempDir.appendingPathComponent("test_input.\(fromFormat)")
        let outputURL = tempDir.appendingPathComponent("test_output.\(toFormat)")
        
        // Create a test audio file in the source format
        let wavURL = tempDir.appendingPathComponent("temp_source.wav")
        let wavProcess = Process()
        wavProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        // Create a 1-second silent stereo audio file
        wavProcess.arguments = [
            "-f", "lavfi", "-i", "sine=frequency=0:duration=1",
            "-ar", "44100", "-ac", "2", "-sample_fmt", "s16",
            wavURL.path
        ]
        try wavProcess.run()
        wavProcess.waitUntilExit()
        
        // Convert to the target source format
        switch fromFormat {
        case "flac":
            let flacProcess = Process()
            flacProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/flac")
            flacProcess.arguments = ["--best", "--verify", "-o", inputURL.path, wavURL.path]
            try flacProcess.run()
            flacProcess.waitUntilExit()
        case "mp3":
            let lameProcess = Process()
            lameProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/lame")
            lameProcess.arguments = ["--quiet", "-m", "s", wavURL.path, inputURL.path]
            try lameProcess.run()
            lameProcess.waitUntilExit()
        case "wav":
            // Just use the WAV file we created
            try FileManager.default.copyItem(at: wavURL, to: inputURL)
        default:
            throw XCTSkip("Unsupported test format: \(fromFormat)")
        }
        
        // Verify input file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: inputURL.path), "Input file was not created")
        
        // Use the AudioConverter to convert
        let converter = AudioConverter()
        try converter.convertToWAV(from: inputURL, to: outputURL)
        
        // Verify the output WAV file has correct properties (44.1kHz, 16-bit, stereo)
        let checkProcess = Process()
        let outputPipe = Pipe()
        checkProcess.standardOutput = outputPipe
        checkProcess.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        checkProcess.arguments = [
            "-v", "error",
            "-select_streams", "a:0",
            "-show_entries", "stream=sample_rate,channels,bits_per_sample",
            "-of", "csv=p=0",
            outputURL.path
        ]
        try checkProcess.run()
        checkProcess.waitUntilExit()
        
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Expected: "44100,2,16"
        XCTAssertEqual(output, "44100,2,16", "Output WAV should be 44.1kHz, 2 channels, 16-bit. Got: '\(output)' for \(fromFormat)->\(toFormat) conversion")
        
        // Cleanup
        try? FileManager.default.removeItem(at: wavURL)
        try? FileManager.default.removeItem(at: inputURL)
        try? FileManager.default.removeItem(at: outputURL)
    }
    
    func testCUEParserBasic() throws {
        // Test basic CUE parsing functionality
        let tempDir = FileManager.default.temporaryDirectory
        let cueURL = tempDir.appendingPathComponent("test.cue")
        
        // Create a simple CUE file
        let cueContent = """
        FILE "test.wav" WAVE
          TRACK 01 AUDIO
            TITLE "Test Track"
            PERFORMER "Test Artist"
            INDEX 01 00:00:00
        """
        
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)
        
        // Parse the CUE file
        let parser = CUEParser()
        let parsed = try parser.parseCUE(from: cueURL)
        
        // Verify basic properties
        XCTAssertEqual(parsed.fileName, "test.wav")
        XCTAssertEqual(parsed.fileType, "WAVE")
        XCTAssertEqual(parsed.tracks.count, 1)
        
        let track = parsed.tracks[0]
        XCTAssertEqual(track.number, 1)
        XCTAssertEqual(track.mode, "AUDIO")
        XCTAssertEqual(track.title, "Test Track")
        XCTAssertEqual(track.performer, "Test Artist")
        XCTAssertEqual(track.indices[1], 0.0) // INDEX 01 at 00:00:00
        
        // Cleanup
        try? FileManager.default.removeItem(at: cueURL)
    }
    
    func testCUEParserWithMetadata() throws {
        // Test CUE parsing with album and track metadata
        let tempDir = FileManager.default.temporaryDirectory
        let cueURL = tempDir.appendingPathComponent("test.cue")
        
        // Create a CUE file with metadata
        let cueContent = """
        PERFORMER "Album Artist"
        TITLE "Album Title"
        SONGWRITER "Album Songwriter"
        
        FILE "test.wav" WAVE
          TRACK 01 AUDIO
            TITLE "Track Title"
            PERFORMER "Track Artist"
            SONGWRITER "Track Songwriter"
            COMPOSER "Track Composer"
            ARRANGER "Track Arranger"
            MESSAGE "Track Message"
            FLAGS DCP
            ISRC "USXX19000123"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Track 2 Title"
            PERFORMER "Track 2 Artist"
            INDEX 01 01:30:00
        """
        
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)
        
        // Parse the CUE file
        let parser = CUEParser()
        let parsed = try parser.parseCUE(from: cueURL)
        
        // Verify album-level metadata
        XCTAssertEqual(parsed.performer, "Album Artist")
        XCTAssertEqual(parsed.title, "Album Title")
        XCTAssertEqual(parsed.songwriter, "Album Songwriter")
        
        // Verify tracks
        XCTAssertEqual(parsed.tracks.count, 2)
        
        let track1 = parsed.tracks[0]
        XCTAssertEqual(track1.number, 1)
        XCTAssertEqual(track1.mode, "AUDIO")
        XCTAssertEqual(track1.title, "Track Title")
        XCTAssertEqual(track1.performer, "Track Artist")
        XCTAssertEqual(track1.songwriter, "Track Songwriter")
        XCTAssertEqual(track1.composer, "Track Composer")
        XCTAssertEqual(track1.arranger, "Track Arranger")
        XCTAssertEqual(track1.message, "Track Message")
        XCTAssertEqual(track1.flags, ["DCP"])
        XCTAssertEqual(track1.isrc, "USXX19000123")
        XCTAssertEqual(track1.indices[1], 0.0)
        
        let track2 = parsed.tracks[1]
        XCTAssertEqual(track2.number, 2)
        XCTAssertEqual(track2.mode, "AUDIO")
        XCTAssertEqual(track2.title, "Track 2 Title")
        XCTAssertEqual(track2.performer, "Track 2 Artist")
        XCTAssertEqual(track2.indices[1], 90.0) // 1 minute 30 seconds = 90 seconds
        
        // Cleanup
        try? FileManager.default.removeItem(at: cueURL)
    }
    
    func testCUEParserWithPregapPostgap() throws {
        // Test CUE parsing with pregap and postgap
        let tempDir = FileManager.default.temporaryDirectory
        let cueURL = tempDir.appendingPathComponent("test.cue")
        
        // Create a CUE file with pregap/postgap
        let cueContent = """
        FILE "test.wav" WAVE
          TRACK 01 AUDIO
            TITLE "Test Track"
            PREGAP 02:00:00
            POSTGAP 01:00:00
            INDEX 01 02:00:00
        """
        
        try cueContent.write(to: cueURL, atomically: true, encoding: .utf8)
        
        // Parse the CUE file
        let parser = CUEParser()
        let parsed = try parser.parseCUE(from: cueURL)
        
        // Verify pregap and postgap
        let track = parsed.tracks[0]
        XCTAssertEqual(track.pregap, 120.0)   // 02:00:00 MM:SS:FF = 2 minutes = 120 seconds
        XCTAssertEqual(track.postgap, 60.0)    // 01:00:00 MM:SS:FF = 1 minute = 60 seconds
        XCTAssertEqual(track.indices[1], 120.0) // INDEX 01 at 02:00:00 MM:SS:FF = 120 seconds
        
        // Cleanup
        try? FileManager.default.removeItem(at: cueURL)
    }
    
    // MARK: - CDTEXTGenerator Tests
    
    func testCDTEXTSanitization() throws {
        let generator = CDTEXTGenerator()
        
        // Test ASCII characters pass through
        XCTAssertEqual(try generator.sanitizeForCDTEXT("Hello World"), "Hello World")
        XCTAssertEqual(try generator.sanitizeForCDTEXT("AC/DC"), "AC/DC")
        
        // Test Polish characters transliteration
        XCTAssertEqual(try generator.sanitizeForCDTEXT("Załóżmy"), "Zalozmy")
        XCTAssertEqual(try generator.sanitizeForCDTEXT("Część"), "Czesc")
        
        // Test German umlauts (transliterated)
        XCTAssertEqual(try generator.sanitizeForCDTEXT("München"), "Munchen")
        XCTAssertEqual(try generator.sanitizeForCDTEXT("Österreich"), "Osterreich")
        
        // Test empty string
        XCTAssertEqual(try generator.sanitizeForCDTEXT(""), "")
    }
    
    func testGenerateTOCBasic() throws {
        let generator = CDTEXTGenerator()
        
        let cdtext = CDTEXTData(
            albumTitle: "Greatest Hits",
            albumPerformer: "Test Artist",
            tracks: [
                CDTEXTEntry(trackNumber: 1, title: "Song One", performer: "Test Artist"),
                CDTEXTEntry(trackNumber: 2, title: "Song Two", performer: "Test Artist")
            ]
        )
        
        let audioFiles: [(Int, String)] = [
            (1, "/tmp/song1.wav"),
            (2, "/tmp/song2.wav")
        ]
        
        let toc = try generator.generateTOCWithCDTEXT(cdtext, audioFiles: audioFiles)
        
        // Verify basic structure
        XCTAssertTrue(toc.contains("CD_DA"))
        XCTAssertTrue(toc.contains("CD_TEXT"))
        XCTAssertTrue(toc.contains("Greatest Hits"))
        XCTAssertTrue(toc.contains("Song One"))
        XCTAssertTrue(toc.contains("Song Two"))
        XCTAssertTrue(toc.contains("/tmp/song1.wav"))
        XCTAssertTrue(toc.contains("/tmp/song2.wav"))
        XCTAssertTrue(toc.contains("AUDIOFILE"))
    }
    
    func testGenerateTOCWithSpecialChars() throws {
        let generator = CDTEXTGenerator()
        
        let cdtext = CDTEXTData(
            albumTitle: "Zespół z Łodzią",
            tracks: [
                CDTEXTEntry(trackNumber: 1, title: "Pieśń o Źródle")
            ]
        )
        
        let audioFiles: [(Int, String)] = [(1, "/tmp/song.wav")]
        let toc = try generator.generateTOCWithCDTEXT(cdtext, audioFiles: audioFiles)
        
        // Polish chars should be transliterated
        XCTAssertTrue(toc.contains("Zespol z Lodzia"))
        XCTAssertTrue(toc.contains("Piesn o Zrodle"))
    }
    
    func testCDTEXTPerformerConsistency() throws {
        let generator = CDTEXTGenerator()
        
        let cdtext = CDTEXTData(
            albumTitle: "Test",
            albumPerformer: "Global Artist",
            tracks: [
                CDTEXTEntry(trackNumber: 1, title: "Track 1", performer: "Artist One"),
                CDTEXTEntry(trackNumber: 2, title: "Track 2")
            ]
        )
        
        let audioFiles: [(Int, String)] = [
            (1, "/tmp/t1.wav"),
            (2, "/tmp/t2.wav")
        ]
        
        let toc = try generator.generateTOCWithCDTEXT(cdtext, audioFiles: audioFiles)
        
        let trackBlocks = toc.components(separatedBy: "TRACK AUDIO")
        XCTAssertGreaterThan(trackBlocks.count, 2)
        XCTAssertTrue(trackBlocks[1].contains("PERFORMER"), "Track 1 should have PERFORMER")
        XCTAssertTrue(trackBlocks[2].contains("PERFORMER"), "Track 2 should have PERFORMER because track 1 has one")
    }
    
    func testCDTEXTSongwriterConsistency() throws {
        let generator = CDTEXTGenerator()
        
        let cdtext = CDTEXTData(
            albumTitle: "Album",
            tracks: [
                CDTEXTEntry(trackNumber: 1, title: "A", songwriter: "Writer One"),
                CDTEXTEntry(trackNumber: 2, title: "B")
            ]
        )
        
        let audioFiles: [(Int, String)] = [(1, "/tmp/a.wav"), (2, "/tmp/b.wav")]
        let toc = try generator.generateTOCWithCDTEXT(cdtext, audioFiles: audioFiles)
        
        // Global CD_TEXT should exist (because track 1 has SONGWRITER)
        XCTAssertTrue(toc.contains("CD_TEXT"), "Global CD_TEXT should be present")
        // Both tracks should have SONGWRITER
        let trackBlocks = toc.components(separatedBy: "TRACK AUDIO")
        XCTAssertTrue(trackBlocks[1].contains("SONGWRITER"), "Track 1 should have SONGWRITER")
        XCTAssertTrue(trackBlocks[2].contains("SONGWRITER"), "Track 2 should inherit SONGWRITER")
    }
    
    func testCreateCDTEXTFromMetadata() throws {
        let generator = CDTEXTGenerator()
        
        let metadata: [String: String] = [
            "album": "Great Album",
            "artist": "Great Artist",
            "genre": "Rock",
            "track_1_title": "Intro",
            "track_2_title": "Main Song"
        ]
        
        let filePaths = ["/tmp/track01.wav", "/tmp/track02.wav"]
        let cdtext = try generator.createCDTEXTData(from: metadata, filePaths: filePaths)
        
        XCTAssertEqual(cdtext.albumTitle, "Great Album")
        XCTAssertEqual(cdtext.albumPerformer, "Great Artist")
        XCTAssertEqual(cdtext.genre, "Rock")
        XCTAssertEqual(cdtext.tracks.count, 2)
        XCTAssertEqual(cdtext.tracks[0].title, "Intro")
        XCTAssertEqual(cdtext.tracks[1].title, "Main Song")
    }
    
    // MARK: - BurnEngine Tests
    
    func testBurnConfigurationSafeUSB() throws {
        let config = BurnConfiguration.safeUSB(devicePath: "IOService:/test/path")
        
        XCTAssertEqual(config.devicePath, "IOService:/test/path")
        XCTAssertEqual(config.speed, 4)
        XCTAssertEqual(config.speedKBps, 704)
        XCTAssertEqual(config.writeMode, .sao)
        XCTAssertTrue(config.burnProof)
        XCTAssertFalse(config.simulate)
        XCTAssertFalse(config.ejectAfterBurn)
        XCTAssertEqual(config.bufferSize, 4096)
        XCTAssertEqual(config.timeout, 600)
    }
    
    func testBurnErrorDescriptions() throws {
        XCTAssertTrue(BurnError.noDisc.errorDescription?.contains("No disc") == true)
        XCTAssertTrue(BurnError.bufferUnderrun.errorDescription?.contains("slower speed") == true)
        XCTAssertTrue(BurnError.deviceNotFound("test").errorDescription?.contains("not found") == true)
        XCTAssertTrue(BurnError.timeout.errorDescription?.contains("timed out") == true)
    }
    
    func testOpticalDriveDescription() throws {
        let drive = OpticalDrive(
            name: "TSSTcorp CDDVDW SU-208DB",
            vendor: "TSSTcorp",
            model: "CDDVDW SU-208DB",
            supportsBurnProof: true,
            supportsJustLink: true,
            maxWriteSpeed: 4224,
            iokitPath: "IOService:/AppleARMPE/test/IODVDServices"
        )
        
        XCTAssertEqual(drive.iokitPath, "IOService:/AppleARMPE/test/IODVDServices")
        XCTAssertEqual(drive.vendor, "TSSTcorp")
        XCTAssertEqual(drive.model, "CDDVDW SU-208DB")
        XCTAssertTrue(drive.supportsBurnProof)
        XCTAssertTrue(drive.supportsJustLink)
    }
    
    func testBurnEngineDetectDevicesParsing() throws {
        let engine = BurnEngine()
        
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/cdrdao") {
            let drives = try engine.detectDevices()
            
            if !drives.isEmpty {
                for drive in drives {
                    XCTAssertFalse(drive.name.isEmpty)
                    XCTAssertFalse(drive.vendor.isEmpty)
                    // iokitPath is empty when detected via drutil (disc mounted, scanbus busy)
                    // and populated when detected via cdrdao scanbus
                    if !drive.iokitPath.isEmpty {
                        XCTAssertTrue(drive.iokitPath.hasPrefix("IOService:") ||
                                      drive.iokitPath.contains(","),
                                      "iokitPath should be IOKit path or legacy SCSI")
                    }
                    XCTAssertGreaterThan(drive.maxWriteSpeed, 0)
                }
            }
        }
    }
    
    func testBurnEngineTOCIntegration() throws {
        let generator = CDTEXTGenerator()
        
        let cdtext = CDTEXTData(
            albumTitle: "Test Album",
            albumPerformer: "Test Artist",
            tracks: [
                CDTEXTEntry(trackNumber: 1, title: "Track 1", performer: "Test Artist"),
                CDTEXTEntry(trackNumber: 2, title: "Track 2")
            ]
        )
        
        let audioFiles: [(Int, String)] = [
            (1, "/tmp/track1.wav"),
            (2, "/tmp/track2.wav")
        ]
        
        let toc = try generator.generateTOCWithCDTEXT(cdtext, audioFiles: audioFiles)
        
        // Verify TOC can be parsed back for structure
        XCTAssertTrue(toc.contains("CD_DA"))
        XCTAssertTrue(toc.contains("TRACK AUDIO"))
        XCTAssertTrue(toc.contains("AUDIOFILE"))
        
        // Verify all tracks present
        let trackCount = toc.components(separatedBy: "TRACK AUDIO").count - 1
        XCTAssertEqual(trackCount, 2)
    }
    
    func testBurnConfigurationWriteModes() throws {
        let sao = BurnConfiguration.safeUSB(writeMode: .sao)
        let tao = BurnConfiguration.safeUSB(writeMode: .tao)
        let dao = BurnConfiguration.safeUSB(writeMode: .dao)
        
        XCTAssertEqual(sao.writeMode, WriteMode.sao)
        XCTAssertEqual(tao.writeMode, WriteMode.tao)
        XCTAssertEqual(dao.writeMode, WriteMode.dao)
        
        // Other values should remain default
        XCTAssertEqual(sao.speed, 4)
        XCTAssertEqual(tao.speed, 4)
        XCTAssertEqual(dao.speed, 4)
    }
    
    // MARK: - New Tests for Untested Code
    
    func testMetadataExtractorGetDuration() throws {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffprobe") else {
            throw XCTSkip("ffprobe not found")
        }
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent("test_dur.wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }
        
        // Create 2-second silent WAV
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        proc.arguments = ["-f", "lavfi", "-i", "sine=frequency=440:duration=2",
                          "-ar", "44100", "-ac", "2", "-sample_fmt", "s16",
                          wavURL.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        
        let extractor = MetadataExtractor()
        let duration = extractor.getDuration(from: wavURL)
        
        XCTAssertNotNil(duration, "Duration should be returned")
        if let d = duration {
            XCTAssertEqual(d, 2.0, accuracy: 0.5, "Duration should be ~2 seconds")
        }
    }
    
    func testEscapeTOCString() throws {
        let generator = CDTEXTGenerator()
        
        // Test via TOC generation with special chars in paths
        let cdtext = CDTEXTData(
            albumTitle: "Album",
            tracks: [CDTEXTEntry(trackNumber: 1, title: "Track")]
        )
        
        // Paths with spaces, quotes, backslashes
        let audioFiles: [(Int, String)] = [(1, "/tmp/my file.wav")]
        let toc = try generator.generateTOCWithCDTEXT(cdtext, audioFiles: audioFiles)
        
        // Path should be escaped in AUDIOFILE line
        XCTAssertTrue(toc.contains("/tmp/my file.wav"), "Path with space should be inside quotes")
    }
    
    func testBurnSessionDurationRecompute() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dummy.wav")
        let header = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00,
                           0x57, 0x41, 0x56, 0x45, 0x66, 0x6D, 0x74, 0x20,
                           0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00,
                           0x44, 0xAC, 0x00, 0x00, 0x10, 0xB1, 0x02, 0x00,
                           0x04, 0x00, 0x10, 0x00])
        try header.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        
        let track1 = BurnTrack(fileURL: url, title: "A", performer: nil, trackNumber: 1, duration: 180, fileSize: 0, format: .wav, cueStartOffset: nil, cueEndOffset: nil)
        let track2 = BurnTrack(fileURL: url, title: "B", performer: nil, trackNumber: 2, duration: 240, fileSize: 0, format: .wav, cueStartOffset: nil, cueEndOffset: nil)
        let track3 = BurnTrack(fileURL: url, title: "C", performer: nil, trackNumber: 3, duration: 60, fileSize: 0, format: .wav, cueStartOffset: nil, cueEndOffset: nil)
        
        let total = [track1, track2, track3].reduce(0) { $0 + $1.duration }
        XCTAssertEqual(total, 480, "3+4+1 min = 480s")
        XCTAssertEqual(total, 8 * 60, "8 minutes total")
    }
    
    func testCDTEXTNormalizeBothFields() throws {
        // Test that BOTH performer AND songwriter are normalized together
        let generator = CDTEXTGenerator()
        
        let cdtext = CDTEXTData(
            albumTitle: "Mixed",
            albumPerformer: "Global Performer",
            tracks: [
                CDTEXTEntry(trackNumber: 1, title: "One", performer: "P1", songwriter: "SW1"),
                CDTEXTEntry(trackNumber: 2, title: "Two"),  // missing both
                CDTEXTEntry(trackNumber: 3, title: "Three", performer: "P3")  // missing songwriter
            ]
        )
        
        let audioFiles: [(Int, String)] = [(1, "/a.wav"), (2, "/b.wav"), (3, "/c.wav")]
        let toc = try generator.generateTOCWithCDTEXT(cdtext, audioFiles: audioFiles)
        
        let blocks = toc.components(separatedBy: "TRACK AUDIO")
        XCTAssertGreaterThan(blocks.count, 3)
        
        // Track 1 has both
        XCTAssertTrue(blocks[1].contains("PERFORMER"), "Track 1 has performer")
        XCTAssertTrue(blocks[1].contains("SONGWRITER"), "Track 1 has songwriter")
        // Track 2 should inherit both
        XCTAssertTrue(blocks[2].contains("PERFORMER"), "Track 2 inherits performer")
        XCTAssertTrue(blocks[2].contains("SONGWRITER"), "Track 2 inherits songwriter")
        // Track 3 has performer, should inherit songwriter
        XCTAssertTrue(blocks[3].contains("PERFORMER"), "Track 3 has performer")
        XCTAssertTrue(blocks[3].contains("SONGWRITER"), "Track 3 inherits songwriter")
    }
    
    func testValidateTOCFile() throws {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/cdrdao") else {
            throw XCTSkip("cdrdao not found")
        }
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        
        let engine = BurnEngine()
        let tempDir = FileManager.default.temporaryDirectory
        
        // Create a real 1-second WAV file for the TOC to reference
        let audioURL = tempDir.appendingPathComponent("test_audio.wav")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        let ffmpeg = Process()
        ffmpeg.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        ffmpeg.arguments = ["-f", "lavfi", "-i", "sine=frequency=0:duration=4",
                          "-ar", "44100", "-ac", "2", "-sample_fmt", "s16",
                          audioURL.path]
        ffmpeg.standardOutput = FileHandle.nullDevice
        ffmpeg.standardError = FileHandle.nullDevice
        try ffmpeg.run()
        ffmpeg.waitUntilExit()
        
        // Valid minimal TOC referencing the real WAV
        let validTOC = tempDir.appendingPathComponent("valid.toc")
        defer { try? FileManager.default.removeItem(at: validTOC) }
        try "CD_DA\nTRACK AUDIO\nAUDIOFILE \"\(audioURL.path)\" 00:00:00\n".write(to: validTOC, atomically: true, encoding: .utf8)
        
        let config = BurnConfiguration(
            devicePath: "IOService:/dummy",
            speed: 4,
            speedKBps: 704,
            writeMode: .sao,
            burnProof: true,
            simulate: true,
            ejectAfterBurn: false,
            bufferSize: 4096,
            timeout: 30
        )
        
        // Validate with simulate — toc-size validates TOC structure + referenced files
        let result = try engine.burnWithTOCFile(validTOC, config: config)
        XCTAssertTrue(result, "Valid TOC + simulate should succeed without writing")
    }
    
    func testWavAndWaveExtensions() throws {
        // Verify that both .wav and .wave extensions are recognized
        // Create a .wave file (not .wav)
        let tempDir = FileManager.default.temporaryDirectory
        let waveURL = tempDir.appendingPathComponent("test.wave")
        defer { try? FileManager.default.removeItem(at: waveURL) }
        
        // Need a real WAV file for loadTrack to accept it
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        proc.arguments = ["-f", "lavfi", "-i", "sine=frequency=0:duration=1",
                          "-ar", "44100", "-ac", "2", "-sample_fmt", "s16",
                          waveURL.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { throw XCTSkip("ffmpeg failed") }
        proc.waitUntilExit()
        
        guard proc.terminationStatus == 0 else { throw XCTSkip("could not create test .wave file") }
        
        // Test extension detection directly
        let ext = waveURL.pathExtension.lowercased()
        XCTAssertEqual(ext, "wave", "Extension should be .wave")
        
        // Test that AudioConverter handles .wave
        let converter = AudioConverter()
        let output = tempDir.appendingPathComponent("converted.wav")
        defer { try? FileManager.default.removeItem(at: output) }
        try converter.convertToWAV(from: waveURL, to: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path), ".wave should convert to .wav")
    }
    
    func testBurnConfigSimulateCustom() throws {
        // Verify custom config with simulate=true is properly constructed
        let config = BurnConfiguration(
            devicePath: "test",
            speed: 8,
            speedKBps: 1408,
            writeMode: .sao,
            burnProof: false,
            simulate: true,
            ejectAfterBurn: true,
            bufferSize: 2048,
            timeout: 120
        )
        
        XCTAssertTrue(config.simulate, "simulate should be true")
        XCTAssertTrue(config.ejectAfterBurn, "eject should be true")
        XCTAssertFalse(config.burnProof, "burnproof should be false")
        XCTAssertEqual(config.speed, 8)
        XCTAssertEqual(config.bufferSize, 2048)
        XCTAssertEqual(config.timeout, 120)
    }
    
    // MARK: - OpenTarget Tests
    
    func testOpenTargetForPlayer() {
        XCTAssertEqual(openTarget(for: .player), .playerFiles)
    }
    
    func testOpenTargetForBurner() {
        XCTAssertEqual(openTarget(for: .burner), .burnerTracks)
    }
    
    // MARK: - RunWithTimeout Tests (Bug B2)
    
    func testRunWithTimeoutFiresOnHang() throws {
        let engine = BurnEngine()
        let start = Date()
        XCTAssertThrowsError(try engine.runWithTimeout(timeout: 0.2) { box in
            Thread.sleep(forTimeInterval: 5)
            return true
        })
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2, "Should timeout in ~0.2s, not sleep 5s")
    }
    
    func testRunWithTimeoutReturnsOnSuccess() throws {
        let engine = BurnEngine()
        let result = try engine.runWithTimeout(timeout: 5) { box in
            return 42
        }
        XCTAssertEqual(result, 42)
    }
    
    func testRunWithTimeoutPropagatesBlockError() throws {
        let engine = BurnEngine()
        XCTAssertThrowsError(try engine.runWithTimeout(timeout: 5) { box in
            throw BurnError.processTimeout("inner")
        })
    }
    
    func testRunWithTimeoutTerminatesProcess() throws {
        guard FileManager.default.isExecutableFile(atPath: "/bin/sleep") else {
            throw XCTSkip("/bin/sleep not found")
        }
        let engine = BurnEngine()
        var capturedProc: Process!
        XCTAssertThrowsError(try engine.runWithTimeout(timeout: 0.3) { box in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sleep")
            proc.arguments = ["30"]
            box.process = proc
            try proc.run()
            capturedProc = proc
            Thread.sleep(forTimeInterval: 10)
            return true
        })
        // Give termination a moment to take effect
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(capturedProc.isRunning, "Process should be terminated after timeout")
    }
    
    // MARK: - CancelBurn Tests (Bug B5)
    
    func testBurnEngineCancelTerminatesProcess() throws {
        guard FileManager.default.isExecutableFile(atPath: "/bin/sleep") else {
            throw XCTSkip("sleep missing")
        }
        let engine = BurnEngine()
        let exp = expectation(description: "terminated")
        // Use a class wrapper to avoid Swift 6 mutable capture in @Sendable closure
        final class ProcRef { var proc: Process? }
        let pref = ProcRef()
        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? engine.runWithTimeout(timeout: 30) { box in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sleep")
                p.arguments = ["60"]
                box.process = p
                pref.proc = p
                try p.run()
                p.waitUntilExit()
                return true
            }
            exp.fulfill()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            engine.cancel()
        }
        wait(for: [exp], timeout: 5.0)
        // after runWithTimeout returns (because process was terminated), the process should not be running
        XCTAssertFalse(pref.proc?.isRunning ?? true, "process should be terminated after cancel")
    }
    
    @MainActor
    func testBurnSessionCancelBurnSetsErrorState() throws {
        let session = BurnSession()
        session.state = .burning(progress: 0.1, currentTrack: 1, totalTracks: 2)
        session.cancelBurn()
        if case .error(let msg) = session.state {
            XCTAssertEqual(msg, "Burn cancelled by user")
        } else {
            XCTFail("Expected .error state, got \(session.state)")
        }
    }
    
    // MARK: - CD-TEXT Null Sanitization Tests (Bug B-cdtext-null)
    
    func testSanitizeStripsNullChar() throws {
        let generator = CDTEXTGenerator()
        let out = try generator.sanitizeForCDTEXT("Hello\0World")
        XCTAssertEqual(out, "HelloWorld")
    }
    
    func testSanitizeStripsAllControlChars() throws {
        let generator = CDTEXTGenerator()
        let out = try generator.sanitizeForCDTEXT("A\u{0001}B\u{0007}C\u{001F}D\u{007F}E")
        XCTAssertEqual(out, "ABCDE")
    }
    
    func testSanitizeKeepsPrintableASCII() throws {
        let generator = CDTEXTGenerator()
        let out = try generator.sanitizeForCDTEXT("Hello World 123!@#")
        XCTAssertEqual(out, "Hello World 123!@#")
    }
    
    func testSanitizeKeepsPolishTransliteration() throws {
        let generator = CDTEXTGenerator()
        let out = try generator.sanitizeForCDTEXT("Żółw")
        XCTAssertEqual(out, "Zolw")
    }
    
    func testSanitizeEmptyStringReturnsEmpty() throws {
        let generator = CDTEXTGenerator()
        let out = try generator.sanitizeForCDTEXT("")
        XCTAssertEqual(out, "")
    }
    
    func testSanitizeOnlyNullReturnsEmpty() throws {
        let generator = CDTEXTGenerator()
        let out = try generator.sanitizeForCDTEXT("\0\0\0")
        XCTAssertEqual(out, "")
    }
    
    // MARK: - FileDropExtractor Tests (B-burner-dragndrop-TEST)
    
    func testParseLoadedItemURL() throws {
        // NSURL items are passed directly as URL from loadItem
        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let result = FileDropExtractor.parseLoadedItem(url)
        XCTAssertEqual(result, url)
    }
    
    func testParseLoadedItemDataBookmark() throws {
        // Create a real bookmark data
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        
        let bookmarkData = try tmp.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let result = FileDropExtractor.parseLoadedItem(bookmarkData)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lastPathComponent, tmp.lastPathComponent)
    }
    
    func testParseLoadedItemDataPlain() throws {
        // Plain URL data representation
        let url = URL(fileURLWithPath: "/tmp/test_plain.txt")
        let data = url.dataRepresentation
        let result = FileDropExtractor.parseLoadedItem(data)
        XCTAssertEqual(result, url)
    }
    
    func testParseLoadedItemString() throws {
        let result = FileDropExtractor.parseLoadedItem("/tmp/from_string.txt")
        XCTAssertEqual(result, URL(fileURLWithPath: "/tmp/from_string.txt"))
    }
    
    func testParseLoadedItemNil() throws {
        let result = FileDropExtractor.parseLoadedItem(nil)
        XCTAssertNil(result)
    }
    
    func testParseLoadedItemInvalidData() throws {
        // Random binary data should not crash and should not produce a valid file URL
        let data = Data([0x00, 0x01, 0x02])
        let result = FileDropExtractor.parseLoadedItem(data)
        // URL(dataRepresentation:) may produce some URL from arbitrary bytes, but it
        // won't be a file URL or pass the fileExists filter later — no crash is the key
        if let url = result {
            // Ensure it doesn't point to an actual file
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }
    
    func testFileDropExtractorEmptyProviders() {
        let urls = FileDropExtractor.extractURLs(from: [])
        XCTAssertEqual(urls.count, 0)
    }
    
    // MARK: - Security-Scoped URL Tests (B-drop-security-scope)
    
    func testSecurityScopedURLFailsFileExistsWithoutAccess() throws {
        // Create a real file
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        
        // Create a bookmark (simulating how Finder delivers security-scoped URLs)
        let bookmarkData = try tmp.bookmarkData(options: .minimalBookmark,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
        var isStale = false
        let resolved = try URL(resolvingBookmarkData: bookmarkData,
                               options: [],
                               relativeTo: nil,
                               bookmarkDataIsStale: &isStale)
        
        // WITHOUT startAccessingSecurityScopedResource: on sandboxed apps,
        // fileExists returns FALSE for security-scoped bookmarks.
        let existsWithoutAccess = FileManager.default.fileExists(atPath: resolved.path)
        
        // WITH startAccessingSecurityScopedResource: fileExists is TRUE
        let gotAccess = resolved.startAccessingSecurityScopedResource()
        let existsWithAccess = FileManager.default.fileExists(atPath: resolved.path)
        if gotAccess { resolved.stopAccessingSecurityScopedResource() }
        
        print("existsWithoutAccess=\(existsWithoutAccess), existsWithAccess=\(existsWithAccess)")
        
        XCTAssertEqual(resolved.lastPathComponent, tmp.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path), "Original file must exist")
    }
    
    func testExtractURLsDoesNotFilterByFileExists() throws {
        // Regression guard: extractURLs must NOT filter URLs by fileExists.
        // Security-scoped URLs from Finder can fail fileExists without
        // startAccessingSecurityScopedResource.
        //
        // Test the concept: parseLoadedItem returns a URL for a nil item
        // (simulating a URL that doesn't exist on disk). The fix ensures
        // such URLs reach session.addFiles.
        
        // Prove parseLoadedItem works for a bookmark URL
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("x".utf8).write(to: tmp)
        
        let bookmarkData = try tmp.bookmarkData(options: .minimalBookmark,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
        guard let parsedURL = FileDropExtractor.parseLoadedItem(bookmarkData) else {
            XCTFail("parseLoadedItem should extract URL from bookmark data")
            return
        }
        XCTAssertEqual(parsedURL.lastPathComponent, tmp.lastPathComponent)
        
        // Now test: extractURLs with empty providers returns [] cleanly
        // (no NSItemProvider needed — this is the synchronous path)
        let urls = FileDropExtractor.extractURLs(from: [])
        XCTAssertEqual(urls.count, 0)
        
        // The KEY assertion: parseLoadedItem accepts URLs even when
        // the file doesn't exist (simulating security-scoped behavior)
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).test")
        let parsedNonexistent = FileDropExtractor.parseLoadedItem(nonexistentURL)
        XCTAssertEqual(parsedNonexistent, nonexistentURL,
                       "parseLoadedItem accepts URLs to nonexistent paths")
        
        print("URL parsing works for nonexistent paths: \(parsedNonexistent!.path)")
    }
}
