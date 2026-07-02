import XCTest
@testable import Spalam_Sie

/// TDD tests for CloneEngine (disc copy/duplication).
final class CloneEngineTests: XCTestCase {
    
    func testCdrdaoDetected() {
        // RED: cdrdao must be present for audio CD cloning
        let fm = FileManager.default
        let exists = fm.isExecutableFile(atPath: "/opt/homebrew/bin/cdrdao")
        XCTAssertTrue(exists, "cdrdao not found. Run: brew install cdrdao")
    }
    
    func testCloneEngineInit() {
        // RED: CloneEngine initializes with default paths
        let engine = CloneEngine()
        XCTAssertNotNil(engine)
        XCTAssertEqual(engine.cdrdaoPath, "/opt/homebrew/bin/cdrdao")
    }
    
    func testSourceDeviceConfig() {
        // RED: Source device must be set separately from target
        var engine = CloneEngine()
        engine.sourceDevice = "IOService:/source"
        engine.targetDevice = "IOService:/target"
        
        XCTAssertEqual(engine.sourceDevice, "IOService:/source")
        XCTAssertEqual(engine.targetDevice, "IOService:/target")
        XCTAssertNotEqual(engine.sourceDevice, engine.targetDevice)
    }
    
    func testOnTheFlyMode() {
        // RED: On-the-fly mode reads and writes simultaneously
        var engine = CloneEngine()
        XCTAssertFalse(engine.onTheFly) // default off
        
        engine.onTheFly = true
        XCTAssertTrue(engine.onTheFly)
    }
    
    func testPreserveCDTEXT() {
        // RED: CD-TEXT preservation flag
        var engine = CloneEngine()
        XCTAssertTrue(engine.preserveCDTEXT) // default on
        
        engine.preserveCDTEXT = false
        XCTAssertFalse(engine.preserveCDTEXT)
    }
    
    func testGenerateReadCDCommand() throws {
        // RED: read-cd command for audio CD
        let engine = CloneEngine()
        engine.sourceDevice = "IOService:/source"
        
        let cmd = try engine.generateReadCommand(intermediateFile: "/tmp/copy.toc")
        XCTAssertTrue(cmd.contains("cdrdao"))
        XCTAssertTrue(cmd.contains("read-cd"))
        XCTAssertTrue(cmd.contains("--device"))
        XCTAssertTrue(cmd.contains("IOService:/source"))
        XCTAssertTrue(cmd.contains("/tmp/copy.toc"))
    }
    
    func testGenerateWriteCommand() throws {
        // RED: write command from TOC file
        let engine = CloneEngine()
        engine.targetDevice = "IOService:/target"
        
        let cmd = try engine.generateWriteCommand(tocFile: "/tmp/copy.toc")
        XCTAssertTrue(cmd.contains("cdrdao"))
        XCTAssertTrue(cmd.contains("write"))
        XCTAssertTrue(cmd.contains("--device"))
        XCTAssertTrue(cmd.contains("IOService:/target"))
        XCTAssertTrue(cmd.contains("/tmp/copy.toc"))
    }
    
    func testGenerateOnTheFlyCommand() throws {
        // RED: On-the-fly copy command
        let engine = CloneEngine()
        engine.sourceDevice = "IOService:/source"
        engine.targetDevice = "IOService:/target"
        engine.onTheFly = true
        
        let cmd = try engine.generateCopyCommand()
        XCTAssertTrue(cmd.contains("cdrdao"))
        XCTAssertTrue(cmd.contains("copy"))
        XCTAssertTrue(cmd.contains("--source-device"))
        XCTAssertTrue(cmd.contains("--device"))
        XCTAssertTrue(cmd.contains("--on-the-fly"))
    }
    
    func testSimulationMode() {
        // RED: Simulation flag for test runs
        var engine = CloneEngine()
        engine.simulate = true
        XCTAssertTrue(engine.simulate)
        
        // Default should be false
        XCTAssertFalse(CloneEngine().simulate)
    }
    
    func testBufferSizeConfig() {
        // RED: Configurable buffer size (in seconds)
        var engine = CloneEngine()
        XCTAssertEqual(engine.bufferSize, 64) // default 64 seconds
        
        engine.bufferSize = 128
        XCTAssertEqual(engine.bufferSize, 128)
    }
    
    func testReadCDParsing() throws {
        // RED: Parse cdrdao read-cd output for progress
        let engine = CloneEngine()
        let sampleOutput = """
        Reading CD...
        Process: 45.3%
        Process: 100.0%
        """
        let progress = engine.parseReadProgress(sampleOutput)
        XCTAssertEqual(progress, 1.0)
    }
    
    func testVerifyClone() throws {
        // RED: Verify after clone compares track count
        let engine = CloneEngine()
        // Source TOC has 10 tracks
        // Target TOC should have 10 tracks
        let sourceTOC = """
        CD_DA
        TRACK AUDIO
        TRACK AUDIO
        """
        let targetTOC = """
        CD_DA
        TRACK AUDIO
        TRACK AUDIO
        """
        let (match, sourceCount, targetCount) = engine.verifyTrackCount(sourceTOC: sourceTOC, targetTOC: targetTOC)
        XCTAssertTrue(match)
        XCTAssertEqual(sourceCount, 2)
        XCTAssertEqual(targetCount, 2)
    }
    
    func testVerifyMismatchDetected() throws {
        // RED: Mismatched track count fails verification
        let engine = CloneEngine()
        let sourceTOC = """
        CD_DA
        TRACK AUDIO
        TRACK AUDIO
        TRACK AUDIO
        """
        let targetTOC = """
        CD_DA
        TRACK AUDIO
        """
        let (match, _, _) = engine.verifyTrackCount(sourceTOC: sourceTOC, targetTOC: targetTOC)
        XCTAssertFalse(match)
    }
    
    // MARK: - CopyMode
    
    func testCopyModeEnumCases() {
        XCTAssertEqual(CopyMode.allCases.count, 3)
        XCTAssertEqual(CopyMode.audioCD.rawValue, "Audio CD")
        XCTAssertEqual(CopyMode.dataCD.rawValue, "Data CD/DVD")
        XCTAssertEqual(CopyMode.raw.rawValue, "Raw Clone")
    }
    
    func testCopyModeToolNames() {
        XCTAssertEqual(CopyMode.audioCD.toolName, "cdrdao")
        XCTAssertEqual(CopyMode.dataCD.toolName, "readcd + cdrecord")
        XCTAssertEqual(CopyMode.raw.toolName, "dd")
    }
    
    // MARK: - Validation
    
    func testValidateEmptySource() {
        let engine = CloneEngine()
        engine.sourceDevice = ""
        engine.targetDevice = "IOService:/target"
        XCTAssertThrowsError(try engine.validateConfiguration(requireBothDevices: true))
    }
    
    func testValidateEmptyTarget() {
        let engine = CloneEngine()
        engine.sourceDevice = "IOService:/source"
        engine.targetDevice = ""
        XCTAssertThrowsError(try engine.validateConfiguration(requireBothDevices: true))
    }
    
    func testValidateSameDevice() {
        let engine = CloneEngine()
        engine.sourceDevice = "IOService:/same"
        engine.targetDevice = "IOService:/same"
        XCTAssertThrowsError(try engine.validateConfiguration(requireBothDevices: true)) { error in
            XCTAssertTrue(error is CloneError)
        }
    }
    
    func testValidateDifferentDevicesOK() throws {
        let engine = CloneEngine()
        engine.sourceDevice = "IOService:/source"
        engine.targetDevice = "IOService:/target"
        XCTAssertNoThrow(try engine.validateConfiguration(requireBothDevices: true))
    }
    
    // MARK: - Pipeline
    
    func testGenerateFullCopyPipeline() throws {
        let engine = CloneEngine()
        engine.sourceDevice = "IOService:/source"
        engine.targetDevice = "IOService:/target"
        let pipeline = try engine.generateFullCopyPipeline(intermediateFile: "/tmp/clone.toc")
        XCTAssertTrue(pipeline.contains("cdrdao"))
        XCTAssertTrue(pipeline.contains("read-cd"))
        XCTAssertTrue(pipeline.contains("write"))
        XCTAssertTrue(pipeline.contains("&&"))
    }
    
    // MARK: - Progress & Write Parsing
    
    func testParseWriteProgressLeadIn() {
        let engine = CloneEngine()
        let (_, phase) = engine.parseWriteProgress("Writing lead-in...")
        XCTAssertEqual(phase, "Lead-in")
    }
    
    func testParseWriteProgressLeadOut() {
        let engine = CloneEngine()
        let (_, phase) = engine.parseWriteProgress("Writing lead-out...")
        XCTAssertEqual(phase, "Lead-out")
    }
    
    func testParseWriteProgressPercent() {
        let engine = CloneEngine()
        let output = "Process: 45.3%\nWriting..."
        let (progress, phase) = engine.parseWriteProgress(output)
        XCTAssertEqual(progress, 0.453, accuracy: 0.001)
        XCTAssertEqual(phase, "Writing")
    }
    
    func testParseWriteProgressVerifying() {
        let engine = CloneEngine()
        let (_, phase) = engine.parseWriteProgress("Verifying...")
        XCTAssertEqual(phase, "Verifying")
    }
    
    func testParseWriteProgressClosing() {
        let engine = CloneEngine()
        let (_, phase) = engine.parseWriteProgress("Fixating...")
        XCTAssertEqual(phase, "Closing")
    }
    
    // MARK: - Temporary Path
    
    func testTemporaryImagePath() {
        let engine = CloneEngine()
        let path = engine.temporaryImagePath()
        XCTAssertTrue(path.hasSuffix(".toc"))
        XCTAssertTrue(path.contains("spalam_clone_"))
    }
    
    // MARK: - Tool Availability
    
    func testIsCdrdaoAvailable() {
        let engine = CloneEngine()
        // Should match actual installation
        let fm = FileManager.default
        let installed = fm.isExecutableFile(atPath: "/opt/homebrew/bin/cdrdao")
        XCTAssertEqual(engine.isCdrdaoAvailable, installed)
    }
    
    // MARK: - Data CD Mode
    
    func testDataCDReadCommand() throws {
        let engine = CloneEngine()
        engine.sourceDevice = "IOService:/source"
        engine.targetDevice = "IOService:/target"
        engine.copyMode = .dataCD
        let cmd = try engine.generateReadCommand(intermediateFile: "/tmp/clone.toc")
        XCTAssertTrue(cmd.contains("readcd"))
        XCTAssertTrue(cmd.contains("-clone"))
        XCTAssertFalse(cmd.contains("cdrdao"))
    }
    
    func testDataCDWriteCommand() throws {
        let engine = CloneEngine()
        engine.sourceDevice = "IOService:/source"
        engine.targetDevice = "IOService:/target"
        engine.copyMode = .dataCD
        let cmd = try engine.generateWriteCommand(tocFile: "/tmp/clone.toc")
        XCTAssertTrue(cmd.contains("cdrecord"))
        XCTAssertTrue(cmd.contains("-dao"))
    }
}
