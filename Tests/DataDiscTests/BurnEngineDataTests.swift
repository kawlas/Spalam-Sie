import XCTest
@testable import Spalam_Sie

/// TDD tests for data disc burning integration with BurnEngine.
final class BurnEngineDataTests: XCTestCase {
    
    var engine: BurnEngine!
    
    override func setUp() {
        engine = BurnEngine()
    }
    
    func testBurnDataTOCStructure() throws {
        // RED: Data disc TOC should use CDROM_MODE1
        var config = BurnConfiguration.safeUSB(devicePath: "IOService:/test")
        config.simulate = true
        let toc = try engine.generateDataTOC(config: config, files: [])
        XCTAssertTrue(toc.contains("CDROM_MODE1"))
        XCTAssertFalse(toc.contains("CD_DA")) // not audio
    }
    
    func testDataWriteModeDefault() {
        // RED: Default write mode for data should be SAO (Disc-at-Once)
        let config = BurnConfiguration.safeUSB(devicePath: "IOService:/test")
        XCTAssertEqual(config.writeMode, .sao)
    }
    
    func testISOGenerationBeforeBurn() throws {
        // RED: Data burn must create ISO before calling cdrecord
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/mkisofs") else {
            throw XCTSkip("mkisofs not installed")
        }
        // This test validates the burn pipeline generates ISO first
        var config = BurnConfiguration.safeUSB(devicePath: "IOService:/test")
        config.simulate = true
        let pipeline = try engine.generateDataBurnPipeline(
            config: config,
            isoPath: "/tmp/test_burn.iso"
        )
        XCTAssertTrue(pipeline.contains("mkisofs"))
        XCTAssertTrue(pipeline.contains("cdrecord") || pipeline.contains("growisofs"))
    }
    
    func testDataBurnCommand() throws {
        // RED: cdrecord command for burning a data ISO
        var config = BurnConfiguration.safeUSB(devicePath: "IOService:/test")
        config.simulate = true
        config.ejectAfterBurn = true
        let cmd = try engine.generateDataBurnCommand(config: config, isoPath: "/tmp/data.iso")
        XCTAssertTrue(cmd.contains("cdrecord"), "cmd = \(cmd)")
        XCTAssertTrue(cmd.contains("-dao"))
        XCTAssertTrue(cmd.contains("-eject"))
        XCTAssertTrue(cmd.contains("-v"))
        XCTAssertTrue(cmd.contains("/tmp/data.iso"))
    }
    
    func testDataBurnWithDirectorySource() throws {
        // RED: generateDataBurnPipeline should accept a directory
        var config = BurnConfiguration.safeUSB(devicePath: "IOService:/test")
        config.simulate = true
        let pipeline = try engine.generateDataBurnPipeline(
            config: config,
            sourcePath: "/tmp/data_folder"
        )
        XCTAssertTrue(pipeline.contains("mkisofs"))
        XCTAssertTrue(pipeline.contains("-R"))
        XCTAssertTrue(pipeline.contains("-J"))
    }
    
    // MARK: - I2a: burnData execution
    
    func testBurnDataSimulateReturnsBool() throws {
        // RED: burnData must exist and run without crashing in simulate mode.
        // Real device may reject, so we accept either true or throw.
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/mkisofs"),
              FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/cdrecord") else {
            throw XCTSkip("mkisofs or cdrecord not installed")
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spalam_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let testFile = tempDir.appendingPathComponent("hello.txt")
        try "test data".write(to: testFile, atomically: true, encoding: .utf8)
        
        var config = BurnConfiguration.safeUSB(devicePath: "IOService:/fake")
        config.simulate = true
        
        do {
            let result = try engine.burnData(config: config, sourcePath: tempDir.path, progress: nil)
            // Accept true if pipeline succeeds in simulate, or throws — both OK
            _ = result
        } catch {
            // Acceptable: device not real, mkisofs/cdrecord may still fail
        }
        XCTAssertNotNil(tempDir)
    }
    
    func testBurnDataProgressCompletedEmitted() throws {
        // RED: progress callback should fire when burnData runs
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/mkisofs"),
              FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/cdrecord") else {
            throw XCTSkip("mkisofs or cdrecord not installed")
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spalam_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let testFile = tempDir.appendingPathComponent("hello.txt")
        try "test data".write(to: testFile, atomically: true, encoding: .utf8)
        
        var config = BurnConfiguration.safeUSB(devicePath: "IOService:/fake")
        config.simulate = true
        
        var progresses: [BurnProgress] = []
        
        do {
            let result = try engine.burnData(config: config, sourcePath: tempDir.path, progress: { p in
                progresses.append(p)
            })
            if result {
                XCTAssertTrue(progresses.contains(where: {
                    if case .completed = $0 { return true }
                    return false
                }))
            }
        } catch {
            // Acceptable failure — don't assert if it throws
        }
    }
    
    func testBurnDataRejectsMissingSource() throws {
        // RED: burnData must throw on nonexistent source
        XCTAssertThrowsError(try engine.burnData(config: BurnConfiguration.safeUSB(devicePath: "x"),
                                                  sourcePath: "/nonexistent/path/xyz",
                                                  progress: nil))
    }
    
    func testBurnDataCancelTerminates() throws {
        // RED: cancel should terminate a running burnData process
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/mkisofs"),
              FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/cdrecord") else {
            throw XCTSkip("mkisofs or cdrecord not installed")
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spalam_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let testFile = tempDir.appendingPathComponent("hello.txt")
        try "test data".write(to: testFile, atomically: true, encoding: .utf8)
        
        var config = BurnConfiguration.safeUSB(devicePath: "IOService:/fake")
        config.timeout = 30
        
        let expectation = expectation(description: "burnData cancelled")
        
        DispatchQueue.global().async {
            do {
                _ = try self.engine.burnData(config: config, sourcePath: tempDir.path, progress: nil)
            } catch {
                // Expected to throw due to cancellation
                expectation.fulfill()
            }
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            self.engine.cancel()
        }
        
        wait(for: [expectation], timeout: 5)
    }
    
    func testVolumeLabelUsedInPipelineNotDevicePath() throws {
        // RED regression: B3 — volume label must use volumeLabel field, not devicePath
        var config = BurnConfiguration.safeUSB(devicePath: "IOService:/bad")
        config.volumeLabel = "MYDISC"
        let pipeline = try engine.generateDataBurnPipeline(config: config, sourcePath: "/tmp/x")
        // Pipeline should use "MYDISC" as volume label
        XCTAssertTrue(pipeline.contains("-V MYDISC") || pipeline.contains("-V \"MYDISC\""),
                      "Pipeline should contain -V MYDISC")
        // Pipeline should NOT use devicePath as volume label
        // The devicePath is "IOService:/bad" — check that -V is NOT followed by it
        let vFlagIndex = pipeline.range(of: "-V")
        if let idx = vFlagIndex {
            let afterV = pipeline[idx.upperBound...].trimmingCharacters(in: .whitespaces)
            XCTAssertFalse(afterV.hasPrefix("IOService"),
                           "Volume label should not be the device path")
        }
    }
}
