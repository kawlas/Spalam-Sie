# Implementation Playbook — Phase 9
## Spalam Sie: Universal Disc Utility + Audio Player

**CEO Directive:** Implement in order 9A → 9C → 9D → 9B. Each module uses TDD (write tests first, then implement, then refactor).

---

## Execution Plan

### Sprint 1: Foundation + Data Disc (9A)
**Goal:** Mode selector in UI + data CD/DVD burning works

| Task | Files | Tests | TDD |
|---|---|---|---|
| 1.1 Add mode picker to ContentView | `ContentView.swift`, `DiscMode.swift` | — | UI-only |
| 1.2 Create DataDiscSession model | `DataDiscSession.swift` | `testAddFiles`, `testISOGeneration` | Red→Green |
| 1.3 Create ISOBuilder (mkisofs wrapper) | `ISOBuilder.swift` | `testMkisofsCatalog`, `testJolietRockRidge`, `testHybridHFS` | Red→Green |
| 1.4 Create DataDiscView | `DataDiscView.swift` | — | UI-only |
| 1.5 Extend BurnEngine for data tracks | `BurnEngine.swift` | `testBurnDataTOC`, `testDataWriteModes` | Red→Green |
| 1.6 Integration: data burn workflow | — | `testDataBurnFullFlow` | Red→Green |

**Tests to write first:**
```swift
// ISOBuilderTests.swift
func testMkisofsDetected()           // mkisofs binary exists
func testISOGenerationDryRun()       // mkisofs -print-size works
func testISOCreatesJoliet()          // ISO contains Joliet volume descriptor
func testISOCreatesRockRidge()       // ISO contains Rock Ridge SUSP records
func testHybridHFS()                 // ISO has HFS+ wrapper
func testMultiSessionParams()        // -C and -M params correct

// DataDiscSessionTests.swift
func testAddSingleFile()
func testAddFolderRecursive()
func testRemoveFileFromSession()
func testTotalSizeCalculation()
func testSessionToISOCommand()

// BurnEngineDataTests.swift
func testBurnDataTOCStructure()      // TOC has CD_ROM mode 1
func testDataWriteModes()            // SAO vs TAO for data tracks
```

---

### Sprint 2: Disc Copy (9C)
**Goal:** Clone audio CDs and data CDs

| Task | Files | Tests | TDD |
|---|---|---|---|
| 2.1 Create CloneEngine | `CloneEngine.swift` | `testCdrdaoDetected`, `testReadTOC`, `testCloneDataCD` | Red→Green |
| 2.2 Create DiscCopySession model | `DiscCopySession.swift` | `testSourceDriveSelection`, `testOnTheFlyCopy` | Red→Green |
| 2.3 Create CopyDiscView UI | `CopyDiscView.swift` | — | UI-only |
| 2.4 Add CD-TEXT preservation in copy | `CloneEngine.swift` | `testCDTEXTPreserved` | Red→Green |

**Tests to write first:**
```swift
// CloneEngineTests.swift
func testCdrdaoDetected()            // cdrdao binary exists
func testReadTOCParsing()            // parse cdrdao read-toc output
func testSimulateCopy()              // dry-run copy validation
func testSourceTargetConfig()        // different device paths for source/target
func testOnTheFlyFlag()              // --on-the-fly flag generation
func testCDTEXTCopyPreservation()    // CD-TEXT survives clone cycle
func testVerifyAfterClone()          // read-back TOC matches original
```

---

### Sprint 3: Audio Player (9D)
**Goal:** Gapless FLAC/MP3/WAV player in the app

| Task | Files | Tests | TDD |
|---|---|---|---|
| 3.1 Create AudioPlayerEngine | `AudioPlayerEngine.swift` | `testEngineInit`, `testPlayLocalFile`, `testDecodeFLAC` | Red→Green |
| 3.2 Add PCM buffer pipeline | `AudioPlayerEngine.swift` | `testPCMFormat`, `testBufferScheduling` | Red→Green |
| 3.3 Implement gapless queue | `AudioPlayerEngine.swift` | `testGaplessTransition`, `testQueueOrder` | Red→Green |
| 3.4 Create PlayerView UI | `PlayerView.swift` | — | UI-only |
| 3.5 Integrate with BurnSession | `BurnSession+Player.swift` | `testLoadTracksIntoPlayer`, `testMetadataSync` | Red→Green |
| 3.6 Add MediaRemote support | `AudioPlayerEngine.swift` | `testMediaKeyCommands` | Red→Green |

**Tests to write first:**
```swift
// AudioPlayerEngineTests.swift
func testEngineInitDealloc()          // engine creates and tears down
func testPlayLocalWAV()               // plays a known WAV file
func testPlayLocalFLAC()              // decodes FLAC and plays
func testPCMOutputFormat()            // output is 44100/16/stereo
func testBufferNonEmpty()             // scheduleBuffer produces audio
func testGaplessTwoTracks()           // no gap between A→B transition
func testQueueOrder()                 // tracks play in correct sequence
func testPauseResume()                // state machine works
func testVolumeControl()              // volume 0.0..1.0
func testStopReleasesResources()      // cleanup after stop
func testDecodeAllFormats()           // WAV, FLAC, MP3, AIFF, M4A
func testMediaRemotePlayPause()       // responds to system media keys
```

---

### Sprint 4: Video DVD (9B)
**Goal:** Burn VIDEO_TS DVDs from video files

| Task | Files | Tests | TDD |
|---|---|---|---|
| 4.1 Create DVDAuthorController | `DVDAuthorController.swift` | `testFfmpegDetected`, `testMPEG2Conversion` | Red→Green |
| 4.2 Create VideoDVDSession model | `VideoDVDSession.swift` | `testAddVideoFile`, `testDetectNTSC_PAL` | Red→Green |
| 4.3 Implement growisofs bridge | `BurnEngine.swift` | `testBurnVideoDVD`, `testVDSSOFormat` | Red→Green |
| 4.4 Create VideoDVDView UI | `VideoDVDView.swift` | — | UI-only |

**Tests to write first:**
```swift
// DVDAuthorControllerTests.swift
func testFfmpegDetected()             // ffmpeg binary exists
func testMPEG2Conversion()            // ffmpeg produces DVD-compliant MPEG-2
func testDVDAuthorCreatesVDSS()       // dvdauthor creates VIDEO_TS structure
func testNTSCDetection()              // 29.97fps → NTSC
func testPALDetection()               // 25fps → PAL
func testAspectRatioPassthrough()     // 16:9 and 4:3 preserved
func testGrowisofsVideoFlag()         // -dvd-video flag in command
func testVideoBurnConfig()            // BurnConfiguration for DVD video

// VideoDVDSessionTests.swift
func testAddVideoFile()
func testRemoveVideo()
func testTotalDuration()
func testEstimatedDiscSize()
```

---

## TDD Workflow

For each task:
```
1. RED:   Write test(s) → compile → test fails as expected
2. GREEN: Implement minimal code to pass test
3. REFACTOR: Clean up, add comments, check edge cases
4. COMMIT: With conventional commit message
```

## Test Structure

```
Tests/
  DataDiscTests/
    ISOBuilderTests.swift
    DataDiscSessionTests.swift
    BurnEngineDataTests.swift
  CopyDiscTests/
    CloneEngineTests.swift
    DiscCopySessionTests.swift
  PlayerTests/
    AudioPlayerEngineTests.swift
  VideoDVDTests/
    DVDAuthorControllerTests.swift
    VideoDVDSessionTests.swift
```

Test target in `Package.swift`:
```swift
.testTarget(name: "DataDiscTests", dependencies: ["Spalam Sie"], path: "Tests/DataDiscTests"),
.testTarget(name: "CopyDiscTests", dependencies: ["Spalam Sie"], path: "Tests/CopyDiscTests"),
.testTarget(name: "PlayerTests", dependencies: ["Spalam Sie"], path: "Tests/PlayerTests"),
.testTarget(name: "VideoDVDTests", dependencies: ["Spalam Sie"], path: "Tests/VideoDVDTests"),
```

---

## Delegation Plan

| Task | Assign To | Method |
|---|---|---|
| PRD & Playbook | CEO (me) | Write docs |
| Sprint 1 (Data Disc) | worker agent | subagent with context fork |
| Sprint 2 (Copy) | worker agent | subagent with context fork |
| Sprint 3 (Player) | worker agent + researcher | researcher for AVAudioEngine deep dive |
| Sprint 4 (Video DVD) | worker agent | subagent with context fork |
| Code Review | reviewer agent | After each sprint |
| Architecture consistency | oracle agent | Before each sprint |

---

*End of Playbook v1.0*
