import XCTest
@testable import Spalam_Sie

/// TDD tests for ISOBuilder (mkisofs wrapper for data CD/DVD creation).
/// These tests define the expected interface BEFORE implementation.
final class ISOBuilderTests: XCTestCase {
    
    func testMkisofsBinaryExists() throws {
        // RED: mkisofs must be installed via brew install cdrtools
        let fm = FileManager.default
        let paths = ["/opt/homebrew/bin/mkisofs", "/usr/local/bin/mkisofs", "/usr/bin/mkisofs"]
        let exists = paths.contains { fm.isExecutableFile(atPath: $0) }
        XCTAssertTrue(exists, "mkisofs not found. Run: brew install cdrtools")
    }
    
    func testISOBuilderInit() {
        // RED: ISOBuilder initializes with output path
        let builder = ISOBuilder()
        XCTAssertNotNil(builder)
    }
    
    func testAddSingleFile() throws {
        // RED: Adding a single file populates the session
        let builder = ISOBuilder()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_iso_data.txt")
        try "hello".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        try builder.addFile(tempFile)
        XCTAssertEqual(builder.files.count, 1)
        XCTAssertEqual(builder.files.first?.lastPathComponent, "test_iso_data.txt")
    }
    
    func testAddDirectoryRecursive() throws {
        // RED: Adding a directory adds all files recursively
        let builder = ISOBuilder()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("iso_test_dir_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create files inside
        let file1 = tempDir.appendingPathComponent("a.txt")
        let file2 = tempDir.appendingPathComponent("sub/b.txt")
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "a".write(to: file1, atomically: true, encoding: .utf8)
        try "b".write(to: file2, atomically: true, encoding: .utf8)
        
        try builder.addDirectory(tempDir)
        XCTAssertGreaterThanOrEqual(builder.files.count, 2)
    }
    
    func testSetVolumeLabel() {
        // RED: Volume label must be <= 32 chars for ISO 9660
        let builder = ISOBuilder()
        builder.volumeLabel = "MY_DATA_DISC"
        XCTAssertEqual(builder.volumeLabel, "MY_DATA_DISC")
        
        // Should truncate or reject > 32 chars
        builder.volumeLabel = String(repeating: "A", count: 40)
        XCTAssertLessThanOrEqual(builder.volumeLabel.count, 32)
    }
    
    func testEnableJoliet() {
        // RED: Joliet extension flag
        let builder = ISOBuilder()
        builder.joliet = true
        XCTAssertTrue(builder.joliet)
        // Default should be true (Windows compat)
        XCTAssertTrue(ISOBuilder().joliet)
    }
    
    func testEnableRockRidge() {
        // RED: Rock Ridge extension flag
        let builder = ISOBuilder()
        builder.rockRidge = true
        XCTAssertTrue(builder.rockRidge)
        // Default should be true (Unix/Linux compat)
        XCTAssertTrue(ISOBuilder().rockRidge)
    }
    
    func testEnableHybridHFS() {
        // RED: HFS hybrid flag for Mac compatibility
        let builder = ISOBuilder()
        builder.hybridHFS = false
        XCTAssertFalse(builder.hybridHFS)
        // Default false
        XCTAssertFalse(ISOBuilder().hybridHFS)
    }
    
    func testGenerateCommandDryRun() throws {
        // RED: -print-size generates a dry-run command
        let builder = ISOBuilder()
        builder.volumeLabel = "TEST"
        builder.joliet = true
        builder.rockRidge = true
        
        let cmd = try builder.generateCommand(dryRun: true)
        XCTAssertTrue(cmd.contains("mkisofs"))
        XCTAssertTrue(cmd.contains("-print-size"))
        XCTAssertTrue(cmd.contains("-J"))   // Joliet
        XCTAssertTrue(cmd.contains("-R"))   // Rock Ridge
        XCTAssertTrue(cmd.contains("-V"))   // Volume label
    }
    
    func testGenerateCommandRealRun() throws {
        // RED: Real burn command has no -print-size, has -o
        let builder = ISOBuilder()
        builder.volumeLabel = "TEST"
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.iso")
        builder.outputURL = outputURL
        
        let cmd = try builder.generateCommand(dryRun: false)
        XCTAssertTrue(cmd.contains("-o"))
        XCTAssertTrue(cmd.contains("test.iso"))
        XCTAssertFalse(cmd.contains("-print-size"))
    }
    
    func testDryRunSucceeds() throws {
        // RED: mkisofs -print-size against a real directory works
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/mkisofs") else {
            throw XCTSkip("mkisofs not installed")
        }
        
        let builder = ISOBuilder()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("iso_dryrun_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let file = tempDir.appendingPathComponent("hello.txt")
        try "world".write(to: file, atomically: true, encoding: .utf8)
        
        try builder.addDirectory(tempDir)
        let size = try builder.dryRun()
        XCTAssertGreaterThan(size, 0, "mkisofs should report ISO size > 0 sectors")
    }
    
    func testISOGeneration() throws {
        // RED: Full ISO image generation produces a valid file
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/mkisofs") else {
            throw XCTSkip("mkisofs not installed")
        }
        
        let builder = ISOBuilder()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("iso_gen_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let file = tempDir.appendingPathComponent("hello.txt")
        try "world".write(to: file, atomically: true, encoding: .utf8)
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).iso")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        
        builder.outputURL = outputURL
        try builder.addDirectory(tempDir)
        builder.volumeLabel = "TESTVOL"
        
        try builder.generateISO()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0, "ISO file should have content")
    }
    
    func testRemoveFile() throws {
        // RED: Removing a file updates the session
        let builder = ISOBuilder()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_remove.txt")
        try "data".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        try builder.addFile(tempFile)
        XCTAssertEqual(builder.files.count, 1)
        
        builder.removeFile(at: 0)
        XCTAssertEqual(builder.files.count, 0)
    }
    
    func testClearAll() throws {
        // RED: Clear removes all files
        let builder = ISOBuilder()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_clear.txt")
        try "data".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        try builder.addFile(tempFile)
        builder.clearAll()
        XCTAssertEqual(builder.files.count, 0)
    }
}
