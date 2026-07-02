import XCTest
@testable import Spalam_Sie

/// TDD tests for DVDAuthorController (video DVD authoring via ffmpeg + dvdauthor).
final class DVDAuthorControllerTests: XCTestCase {
    
    var tempDir: URL!
    
    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dvd_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    func testFfmpegDetected() {
        // RED: ffmpeg must be installed for video conversion
        let fm = FileManager.default
        let exists = fm.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg")
        XCTAssertTrue(exists, "ffmpeg not found. Run: brew install ffmpeg")
    }
    
    func testDvdauthorDetected() throws {
        // RED: dvdauthor must be installed for VIDEO_TS authoring
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: "/opt/homebrew/bin/dvdauthor") else {
            throw XCTSkip("dvdauthor not found. Run: brew install dvdauthor")
        }
        XCTAssertTrue(fm.isExecutableFile(atPath: "/opt/homebrew/bin/dvdauthor"))
    }
    
    func testDVDAuthorControllerInit() {
        let ctrl = DVDAuthorController()
        XCTAssertNotNil(ctrl)
    }
    
    func testAddVideoFile() throws {
        // RED: Adding a video file populates the session
        let ctrl = DVDAuthorController()
        let videoURL = tempDir.appendingPathComponent("test.mp4")
        try Data().write(to: videoURL) // placeholder
        
        try ctrl.addVideo(videoURL)
        XCTAssertEqual(ctrl.videoFiles.count, 1)
    }
    
    func testDetectNTSC() throws {
        // RED: 29.97 fps video detected as NTSC
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        
        let videoURL = tempDir.appendingPathComponent("ntsc_test.mkv")
        try createTestVideo(at: videoURL, fps: 29.97, duration: 1)
        
        let ctrl = DVDAuthorController()
        let system = try ctrl.detectVideoSystem(videoURL)
        XCTAssertEqual(system, .ntsc)
    }
    
    func testDetectPAL() throws {
        // RED: 25 fps video detected as PAL
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") else {
            throw XCTSkip("ffmpeg not found")
        }
        
        let videoURL = tempDir.appendingPathComponent("pal_test.mkv")
        try createTestVideo(at: videoURL, fps: 25.0, duration: 1)
        
        let ctrl = DVDAuthorController()
        let system = try ctrl.detectVideoSystem(videoURL)
        XCTAssertEqual(system, .pal)
    }
    
    func testMPEG2ConversionCommand() throws {
        // RED: ffmpeg MPEG-2 conversion command structure
        let ctrl = DVDAuthorController()
        let input = URL(fileURLWithPath: "/tmp/input.mp4")
        let output = URL(fileURLWithPath: "/tmp/output.mpg")
        
        let cmd = try ctrl.generateConvertCommand(input: input, output: output, system: .pal)
        XCTAssertTrue(cmd.contains("ffmpeg"))
        XCTAssertTrue(cmd.contains("-target pal-dvd"))
        XCTAssertTrue(cmd.contains(input.path))
        XCTAssertTrue(cmd.contains(output.path))
    }
    
    func testGenerateXML() throws {
        // RED: dvdauthor XML configuration
        let ctrl = DVDAuthorController()
        ctrl.videoFiles = [
            (url: URL(fileURLWithPath: "/tmp/title.mpg"), duration: 120)
        ]
        
        let xml = try ctrl.generateAuthorXML(outputDir: tempDir.path)
        XCTAssertTrue(xml.contains("dvdauthor"))
        XCTAssertTrue(xml.contains("vmgm"))
        XCTAssertTrue(xml.contains("title.mpg"))
    }
    
    func testGrowisofsCommand() throws {
        // RED: growisofs burn command for DVD-Video
        let ctrl = DVDAuthorController()
        let dvdDir = URL(fileURLWithPath: "/tmp/dvd_volume")
        let devicePath = "IOService:/dvd"
        
        let cmd = try ctrl.generateBurnCommand(dvdDir: dvdDir, devicePath: devicePath, speed: 4)
        XCTAssertTrue(cmd.contains("growisofs"))
        XCTAssertTrue(cmd.contains("-Z"))
        XCTAssertTrue(cmd.contains("-dvd-video"))
        XCTAssertTrue(cmd.contains(devicePath))
    }
    
    func testTotalDuration() throws {
        // RED: Calculates total duration from all files
        let ctrl = DVDAuthorController()
        ctrl.videoFiles = [
            (url: URL(fileURLWithPath: "/tmp/a.mpg"), duration: 120),
            (url: URL(fileURLWithPath: "/tmp/b.mpg"), duration: 180)
        ]
        XCTAssertEqual(ctrl.totalDuration, 300)
    }
    
    // MARK: - Helpers
    
    private func createTestVideo(at url: URL, fps: Double, duration: Double) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        proc.arguments = [
            "-f", "lavfi", "-i",
            "testsrc=duration=\(duration):size=720x480:rate=\(fps)",
            "-f", "lavfi", "-i",
            "sine=frequency=440:duration=\(duration)",
            "-c:v", "libx264", "-preset", "ultrafast",
            "-c:a", "aac",
            "-shortest",
            "-y", url.path
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
    }
}
