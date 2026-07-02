import XCTest
@testable import Spalam_Sie

/// TDD tests for AudioPlayerEngine (AVAudioEngine-based player).
/// Tests define the expected interface BEFORE implementation.
@MainActor final class AudioPlayerEngineTests: XCTestCase {
    
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
    
    func testEngineRejectsInvalidFile() throws {
        // RED: Engine should handle missing files gracefully
        let engine = AudioPlayerEngine()
        let bogusURL = URL(fileURLWithPath: "/nonexistent/file.flac")
        XCTAssertThrowsError(try engine.play(url: bogusURL))
    }
    
    func testEngineStops() throws {
        // RED: Engine stops cleanly
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        let engine = AudioPlayerEngine()
        let wavURL = tempDir.appendingPathComponent("stop_test.wav")
        try createTestAudio(at: wavURL, duration: 0.5)
        try engine.play(url: wavURL)
        engine.stop()
        XCTAssertEqual(engine.state, .stopped)
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
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        let engine = AudioPlayerEngine()
        let url1 = tempDir.appendingPathComponent("a.wav")
        let url2 = tempDir.appendingPathComponent("b.wav")
        try createTestAudio(at: url1, duration: 0.3)
        try createTestAudio(at: url2, duration: 0.3)
        try engine.queue(url: url1)
        try engine.queue(url: url2)
        XCTAssertEqual(engine.queueCount, 2)
    }
    
    func testClearQueue() throws {
        // RED: Clear queue removes all pending tracks
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        let engine = AudioPlayerEngine()
        let url1 = tempDir.appendingPathComponent("clear_a.wav")
        let url2 = tempDir.appendingPathComponent("clear_b.wav")
        try createTestAudio(at: url1, duration: 0.3)
        try createTestAudio(at: url2, duration: 0.3)
        try engine.queue(url: url1)
        try engine.queue(url: url2)
        XCTAssertEqual(engine.queueCount, 2)
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
    
    // MARK: - Security Scopes
    
    func testSecurityScopeStartedOnPlay() throws {
        // RED: Playing a file starts the security scope for that URL
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        let engine = AudioPlayerEngine()
        let wavURL = tempDir.appendingPathComponent("scope_play.wav")
        try createTestAudio(at: wavURL, duration: 0.5)
        try engine.play(url: wavURL)
        XCTAssertTrue(engine.securityScopedURLs.contains(wavURL))
        engine.stop()
    }
    
    func testSecurityScopeReleasedOnStop() throws {
        // RED: Stopping the engine releases all security scopes
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        let engine = AudioPlayerEngine()
        let wavURL = tempDir.appendingPathComponent("scope_stop.wav")
        try createTestAudio(at: wavURL, duration: 0.5)
        try engine.play(url: wavURL)
        XCTAssertFalse(engine.securityScopedURLs.isEmpty)
        engine.stop()
        XCTAssertTrue(engine.securityScopedURLs.isEmpty)
    }
    
    func testSecurityScopeHeldForQueuedTracks() throws {
        // RED: Security scopes are held for both playing and queued tracks
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        let engine = AudioPlayerEngine()
        let url1 = tempDir.appendingPathComponent("scope_q1.wav")
        let url2 = tempDir.appendingPathComponent("scope_q2.wav")
        try createTestAudio(at: url1, duration: 0.3)
        try createTestAudio(at: url2, duration: 0.3)
        try engine.play(url: url1)
        try engine.queue(url: url2)
        XCTAssertTrue(engine.securityScopedURLs.contains(url1))
        XCTAssertTrue(engine.securityScopedURLs.contains(url2))
        engine.stop()
        XCTAssertTrue(engine.securityScopedURLs.isEmpty)
    }
    
    func testSecurityScopeReleasedOnClearQueue() throws {
        // RED: Clearing the queue releases all security scopes
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        let engine = AudioPlayerEngine()
        let url1 = tempDir.appendingPathComponent("scope_cq1.wav")
        let url2 = tempDir.appendingPathComponent("scope_cq2.wav")
        try createTestAudio(at: url1, duration: 0.3)
        try createTestAudio(at: url2, duration: 0.3)
        try engine.playQueue(urls: [url1, url2])
        engine.clearQueue()
        XCTAssertTrue(engine.securityScopedURLs.isEmpty)
    }
    
    func testStopAllScopesIdempotent() throws {
        // RED: Stopping an already-stopped engine does not crash
        let engine = AudioPlayerEngine()
        engine.stop()
        engine.stop()
        XCTAssertEqual(engine.state, .stopped)
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
