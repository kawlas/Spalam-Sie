import XCTest
@testable import Spalam_Sie

/// TDD tests for DataDiscSession (data disc session model).
final class DataDiscSessionTests: XCTestCase {
    
    func testSessionInit() {
        let session = DataDiscSession()
        XCTAssertNotNil(session)
        XCTAssertEqual(session.files.count, 0)
        XCTAssertEqual(session.volumeLabel, "SPALAM_DATA")
    }
    
    func testAddSingleFile() throws {
        let session = DataDiscSession()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("dds_file.txt")
        try "data".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        try session.addFile(tempFile)
        XCTAssertEqual(session.files.count, 1)
    }
    
    func testRemoveFileFromSession() throws {
        let session = DataDiscSession()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("dds_remove.txt")
        try "data".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        try session.addFile(tempFile)
        XCTAssertEqual(session.files.count, 1)
        
        session.removeFile(at: 0)
        XCTAssertEqual(session.files.count, 0)
    }
    
    func testTotalSizeCalculation() throws {
        let session = DataDiscSession()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dds_size_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let file1 = tempDir.appendingPathComponent("a.txt")
        let file2 = tempDir.appendingPathComponent("b.txt")
        try "hello".write(to: file1, atomically: true, encoding: .utf8)
        try "world".write(to: file2, atomically: true, encoding: .utf8)
        
        try session.addFile(file1)
        try session.addFile(file2)
        
        XCTAssertEqual(session.totalFileSize, 10)
    }
    
    func testDiscTypeDetection() {
        let session = DataDiscSession()
        
        session.totalFileSize = 400_000_000 // 400 MB
        XCTAssertEqual(session.recommendedDiscType, .cdr)
        
        session.totalFileSize = 1_000_000_000 // 1 GB
        XCTAssertEqual(session.recommendedDiscType, .dvdr)
        
        session.totalFileSize = 10_000_000_000 // 10 GB
        XCTAssertEqual(session.recommendedDiscType, .bdr)
    }
    
    func testVolumeLabelDefaults() {
        let session = DataDiscSession()
        session.volumeLabel = "MY_BACKUP_2026"
        XCTAssertEqual(session.volumeLabel, "MY_BACKUP_2026")
    }
    
    func testClearAll() throws {
        let session = DataDiscSession()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("dds_clear.txt")
        try "data".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        try session.addFile(tempFile)
        session.clearAll()
        XCTAssertEqual(session.files.count, 0)
    }
}
