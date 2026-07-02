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
}
