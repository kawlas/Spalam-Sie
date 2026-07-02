import XCTest
@testable import Spalam_Sie

/// TDD tests for DataDiscSession (data disc session model).
@MainActor
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

// MARK: - Burn Orchestration Tests (I2b)

final class FakeDataBurner: DataBurner, @unchecked Sendable {
    var burnResult: Bool = true
    var burnError: Error?
    var capturedConfig: BurnConfiguration?
    var capturedSourcePath: String?
    var cancelCalled = false
    
    func burnData(config: BurnConfiguration, sourcePath: String, progress: BurnProgressCallback?) throws -> Bool {
        capturedConfig = config
        capturedSourcePath = sourcePath
        progress?(.writingTrack(track: 1, total: 1, progress: 0.5))
        progress?(.completed)
        if let e = burnError { throw e }
        return burnResult
    }
    
    func cancel() {
        cancelCalled = true
    }
}

@MainActor
final class DataDiscBurnTests: XCTestCase {
    
    func testPerformDataBurnEmptyFilesSetsError() {
        let fake = FakeDataBurner()
        let session = DataDiscSession(burner: fake)
        // No files added — should immediately set .error
        session.performDataBurn(
            sourcePath: "/tmp/staging",
            devicePath: "IO:/x",
            simulate: true,
            speed: 4,
            ejectAfterBurn: false
        )
        if case .error = session.burnState {
            // Expected
        } else {
            XCTFail("Expected .error state, got \(session.burnState)")
        }
    }
    
    func testPerformDataBurnCallsBurnerWithConfig() throws {
        let fake = FakeDataBurner()
        let session = DataDiscSession(burner: fake)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dds_burn_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let tempFile = tempDir.appendingPathComponent("test.txt")
        try "hello".write(to: tempFile, atomically: true, encoding: .utf8)
        try session.addFile(tempFile)
        
        let exp = expectation(description: "async burn")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        
        session.performDataBurn(
            sourcePath: tempDir.path,
            devicePath: "IO:/x",
            simulate: true,
            speed: 4,
            ejectAfterBurn: false
        )
        
        wait(for: [exp], timeout: 2)
        
        XCTAssertEqual(fake.capturedConfig?.simulate, true)
        XCTAssertEqual(fake.capturedConfig?.speed, 4)
        XCTAssertEqual(fake.capturedSourcePath, tempDir.path)
        XCTAssertEqual(fake.capturedConfig?.volumeLabel, session.volumeLabel)
    }
    
    func testPerformDataBurnSuccessSetsCompleted() throws {
        let fake = FakeDataBurner()
        fake.burnResult = true
        let session = DataDiscSession(burner: fake)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dds_success_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let tempFile = tempDir.appendingPathComponent("test.txt")
        try "hello".write(to: tempFile, atomically: true, encoding: .utf8)
        try session.addFile(tempFile)
        
        let exp = expectation(description: "async success")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        
        session.performDataBurn(
            sourcePath: tempDir.path,
            devicePath: "IO:/x",
            simulate: false,
            speed: 4,
            ejectAfterBurn: false
        )
        
        wait(for: [exp], timeout: 2)
        
        if case .completed(let success, _) = session.burnState {
            XCTAssertTrue(success)
        } else {
            XCTFail("Expected .completed state, got \(session.burnState)")
        }
    }
    
    func testPerformDataBurnFailureSetsError() throws {
        let fake = FakeDataBurner()
        fake.burnError = BurnError.burnFailed("nope")
        let session = DataDiscSession(burner: fake)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dds_fail_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let tempFile = tempDir.appendingPathComponent("test.txt")
        try "hello".write(to: tempFile, atomically: true, encoding: .utf8)
        try session.addFile(tempFile)
        
        let exp = expectation(description: "async error")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        
        session.performDataBurn(
            sourcePath: tempDir.path,
            devicePath: "IO:/x",
            simulate: false,
            speed: 4,
            ejectAfterBurn: false
        )
        
        wait(for: [exp], timeout: 2)
        
        if case .error = session.burnState {
            // Expected
        } else {
            XCTFail("Expected .error state, got \(session.burnState)")
        }
    }
    
    func testCancelBurnCallsBurnerCancelAndSetsError() throws {
        let fake = FakeDataBurner()
        let session = DataDiscSession(burner: fake)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dds_cancel_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let tempFile = tempDir.appendingPathComponent("test.txt")
        try "hello".write(to: tempFile, atomically: true, encoding: .utf8)
        try session.addFile(tempFile)
        
        session.performDataBurn(
            sourcePath: tempDir.path,
            devicePath: "IO:/x",
            simulate: true,
            speed: 4,
            ejectAfterBurn: false
        )
        // Cancel immediately without waiting
        session.cancelBurn()
        
        let exp = expectation(description: "async cancel")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        
        XCTAssertTrue(fake.cancelCalled, "burner.cancel() should have been called")
        if case .error(let msg) = session.burnState {
            XCTAssertEqual(msg, "Cancelled by user")
        } else {
            XCTFail("Expected .error state, got \(session.burnState)")
        }
    }
}
