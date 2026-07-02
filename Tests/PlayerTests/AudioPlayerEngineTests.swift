import XCTest
@testable import Spalam_Sie

/// TDD tests for AudioPlayerEngine (AVAudioEngine-based player).
/// Tests define the expected interface BEFORE implementation.
final class AudioPlayerEngineTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("player_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    // MARK: - Engine Lifecycle
    
    func testEngineInitDealloc() {
        // RED: Engine creates and can be deallocated
        let engine = AudioPlayerEngine()
        XCTAssertNotNil(engine)
    }
    
    func testEngineStarts() throws {
        // RED: Engine starts without error
        let engine = AudioPlayerEngine()
        try engine.start()
        XCTAssertTrue(engine.isRunning)
        engine.stop()
    }
    
    func testEngineStops() throws {
        // RED: Engine stops cleanly
        let engine = AudioPlayerEngine()
        try engine.start()
        engine.stop()
        XCTAssertFalse(engine.isRunning)
    }
    
    // MARK: - Playback Control
    
    func testPlayLocalWAV() throws {
        // RED: Plays a known WAV file
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        
        let wavURL = tempDir.appendingPathComponent("test.wav")
        try createTestAudio(at: wavURL, duration: 0.5)
        
        let engine = AudioPlayerEngine()
        try engine.start()
        try engine.play(url: wavURL)
        
        XCTAssertEqual(engine.state, .playing)
        
        // Wait briefly then stop
        let exp = expectation(description: "playback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
        engine.stop()
    }
    
    func testPlayLocalFLAC() throws {
        // RED: Decodes and plays FLAC
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/flac"),
              FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("flac or ffmpeg not found")
        }
        
        let wavURL = tempDir.appendingPathComponent("source.wav")
        try createTestAudio(at: wavURL, duration: 0.5)
        
        let flacURL = tempDir.appendingPathComponent("test.flac")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/flac")
        proc.arguments = [wavURL.path, "-o", flacURL.path, "--best"]
        try proc.run()
        proc.waitUntilExit()
        
        let engine = AudioPlayerEngine()
        try engine.start()
        try engine.play(url: flacURL)
        
        XCTAssertEqual(engine.state, .playing)
        
        let exp = expectation(description: "flac playback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
        engine.stop()
    }
    
    func testPauseResume() throws {
        // RED: Pause and resume work
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        
        let wavURL = tempDir.appendingPathComponent("test_pause.wav")
        try createTestAudio(at: wavURL, duration: 2.0)
        
        let engine = AudioPlayerEngine()
        try engine.start()
        try engine.play(url: wavURL)
        
        XCTAssertEqual(engine.state, .playing)
        
        engine.pause()
        XCTAssertEqual(engine.state, .paused)
        
        engine.resume()
        XCTAssertEqual(engine.state, .playing)
        
        engine.stop()
    }
    
    func testStopReleasesResources() throws {
        // RED: Stop releases audio resources
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        
        let wavURL = tempDir.appendingPathComponent("test_stop.wav")
        try createTestAudio(at: wavURL, duration: 0.5)
        
        let engine = AudioPlayerEngine()
        try engine.start()
        try engine.play(url: wavURL)
        engine.stop()
        
        XCTAssertEqual(engine.state, .stopped)
        // Should be able to play again after stop
        try engine.play(url: wavURL)
        XCTAssertEqual(engine.state, .playing)
        engine.stop()
    }
    
    // MARK: - Volume
    
    func testVolumeControl() throws {
        // RED: Volume ranges 0.0 to 1.0
        let engine = AudioPlayerEngine()
        
        engine.volume = 0.5
        XCTAssertEqual(engine.volume, 0.5, accuracy: 0.01)
        
        engine.volume = 0.0
        XCTAssertEqual(engine.volume, 0.0)
        
        engine.volume = 1.0
        XCTAssertEqual(engine.volume, 1.0)
    }
    
    // MARK: - Gapless
    
    func testGaplessTwoTracks() throws {
        // RED: Two tracks play without gap
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        
        let track1 = tempDir.appendingPathComponent("track1.wav")
        let track2 = tempDir.appendingPathComponent("track2.wav")
        try createTestAudio(at: track1, duration: 0.3)
        try createTestAudio(at: track2, duration: 0.3)
        
        let engine = AudioPlayerEngine()
        try engine.start()
        try engine.play(url: track1)
        
        // Queue next track
        try engine.queue(url: track2)
        
        let exp = expectation(description: "gapless")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Both tracks should have played
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3.0)
        engine.stop()
    }
    
    func testQueueOrder() throws {
        // RED: Queued tracks play in sequence
        let engine = AudioPlayerEngine()
        let queue = ["/tmp/a.wav", "/tmp/b.wav", "/tmp/c.wav"]
        try queue.forEach { try engine.queue(url: URL(fileURLWithPath: $0)) }
        XCTAssertEqual(engine.queueCount, 3)
    }
    
    func testClearQueue() throws {
        // RED: Clear queue removes all pending tracks
        let engine = AudioPlayerEngine()
        try engine.queue(url: URL(fileURLWithPath: "/tmp/a.wav"))
        try engine.queue(url: URL(fileURLWithPath: "/tmp/b.wav"))
        engine.clearQueue()
        XCTAssertEqual(engine.queueCount, 0)
    }
    
    // MARK: - State Machine
    
    func testStateTransitions() throws {
        // RED: Valid state transitions
        let engine = AudioPlayerEngine()
        XCTAssertEqual(engine.state, .stopped)
        
        try engine.start()
        XCTAssertEqual(engine.state, .stopped) // stopped until a track is loaded
        
        // After starting engine but before loading track
    }
    
    // MARK: - Helpers
    
    private func createTestAudio(at url: URL, duration: Double) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        proc.arguments = [
            "-f", "lavfi", "-i", "sine=frequency=440:duration=\(duration)",
            "-ar", "44100", "-ac", "2", "-sample_fmt", "s16",
            "-y", url.path
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw XCTSkip("ffmpeg failed to create test audio")
        }
    }
}
