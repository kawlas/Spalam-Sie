import XCTest
import SFBAudioEngine

/// Verify SFBAudioEngine is properly linked and its key types are accessible.
@MainActor final class SFBAudioEngineIntegrationTests: XCTestCase {
    
    func testSFBAudioPlayerTypeExists() {
        // AudioPlayer should be available from the SFBAudioEngine module
        let player = AudioPlayer()
        XCTAssertNotNil(player)
    }
    
    func testAudioFileTypeExists() {
        // AudioFile should exist for reading metadata
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("nonexistent.flac")
        // Should throw file not found, not "type not available"
        XCTAssertThrowsError(try AudioFile(readingPropertiesAndMetadataFrom: url))
    }
    
    func testDecoderTypeExists() throws {
        // Decoder should be available
        // Just test that the type exists by checking we can initialize it
        let decoderType = Decoder.self
        XCTAssertNotNil(decoderType)
    }
    
    func testAudioFileProperties() throws {
        // Create a test WAV file and verify we can read its properties
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sfe_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create a test WAV with ffmpeg
        let wavURL = tempDir.appendingPathComponent("test_sine.wav")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        proc.arguments = [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-ar", "44100", "-ac", "2", "-sample_fmt", "s16",
            "-y", wavURL.path
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        
        guard FileManager.default.fileExists(atPath: wavURL.path) else {
            throw XCTSkip("ffmpeg failed to create test file")
        }
        
        // Read properties via SFBAudioEngine
        let audioFile = try AudioFile(readingPropertiesAndMetadataFrom: wavURL)
        let props = audioFile.properties
        
        XCTAssertEqual(props.sampleRate, 44100)
        XCTAssertEqual(props.channelCount, 2)
        XCTAssertEqual(props.bitDepth, 16)
        if let frames = props.frameLength {
            XCTAssertGreaterThan(frames, 0)
        }
        
        let metadata = audioFile.metadata
        XCTAssertNotNil(metadata)
    }
}
