# Spalam Sie - CD Burning Application for macOS Apple Silicon
## Project Plan & Roadmap

### Vision
Create a reliable, native macOS CD burning application that works correctly with USB optical drives on Apple Silicon Macs, bypassing the problematic DiscRecording framework and using cdrdao for SCSI passthrough.

**Long-term vision**: Evolve into a full-featured disc utility with data/audio/video burning, disc copy, and a lightweight high-quality audio player — a modern replacement for the classic macOS Burn.app.

### Core Principles
1. **Reliability First**: Must work consistently with user's specific hardware (TSSTcorp CDDVDW SU-208DB via XD013 USB hub)
2. **Native Experience**: Use SwiftUI for best macOS integration
3. **Modular Architecture**: Clean separation of concerns for testability
4. **Error Handling**: Comprehensive error handling and recovery
5. **Logging**: Detailed logging for debugging USB/SCSI issues

---

## Phase 0: Foundation & Research ✅ COMPLETE
- [x] Research CD burning best practices on Apple Silicon
- [x] Research GUI frameworks (tkinter vs SwiftUI vs AppKit vs Electron)
- [x] Audit existing codebase for issues
- [x] Research CUE sheet, CD-TEXT, and Red Book standards
- [x] Identified critical bugs and architectural issues

## Phase 1: Project Setup & Architecture ✅
- [x] Create proper project structure (SPM modules)
- [x] Set up build system (Swift Package Manager)
- [x] Define module boundaries and interfaces

## Phase 2: Core Infrastructure ✅
- [x] Logging system (session log with timestamps)
- [x] Configuration management (ConfigManager + UserDefaults persistence)
- [x] Error handling framework (BurnError, CUEParserError, CDTEXTError, AudioConversionError)
- [x] Device detection and SCSI utilities (BurnEngine — cdrdao scanbus, drutil, IOKit)
- [x] Thread-safe utilities (MainActor-isolated BurnSession)

## Phase 3: Audio Processing Pipeline ✅
- [x] Audio format detection
- [x] Lossless audio conversion (FLAC → WAV)
- [x] Lossy audio conversion (MP3 → WAV)
- [x] WAV validation (44.1kHz, 16-bit, stereo)
- [x] Sample rate conversion (via ffmpeg)
- [x] Temporary file management (defer cleanup)
- [x] CUE audio segment extraction (ffmpeg -ss / -t)

## Phase 4: Metadata & Parsing ✅
- [x] Audio metadata extraction (ffprobe wrapper)
- [x] CUE sheet parser (with phantom track fix)
- [x] CD-TEXT generator (proper escaping, encoding, Polish chars)
- [x] Metadata aggregation for album/track info

## Phase 5: Burning Engine ✅
- [x] cdrdao integration via Swift Process
- [x] cdrecord integration (fallback for direct WAV burning)
- [x] Device auto-detection (cdrdao scanbus + drutil status)
- [x] BurnProof/JustLink handling (via driver flags)
- [x] Progress reporting from cdrdao/cdrecord output
- [x] Error handling and recovery
- [x] Write modes (DAO, SAO, TAO)
- [x] Buffer underrun protection
- [x] Disc verification after burn (read-toc, track count check)
- [x] Unmount before access (diskutil)
- [x] Eject with fallbacks (drutil → cdrecord)

## Phase 6: User Interface (SwiftUI) ✅
- [x] Main window with drag-and-drop
- [x] File/folder addition dialogs (⌘O)
- [x] Track list with metadata display (sortable, removable)
- [x] CD-TEXT editing (album/artist + per-track inline editing)
- [x] Burn speed selector (1x-24x with kB/s display)
- [x] Burn simulation mode
- [x] Progress bar and status display
- [x] Post-burn verification feedback
- [x] Eject control (⌘⇧E)
- [x] File type associations (.wav, .flac, .mp3, .aiff, .cue, .toc)
- [x] Device status badge (green/red)
- [x] Duration summary with CD capacity bar

## Phase 7: Testing & Quality Assurance (ongoing)
- [x] Unit tests for core modules (29 tests)
- [ ] Integration tests for full workflows (user-managed)
- [ ] UI tests for critical flows
- [ ] Manual testing with actual hardware (TSSTcorp SU-208DB)
- [ ] Regression testing
- [ ] Performance benchmarks

## Phase 8: Polish & Release (in progress)
- [x] Application icon and branding (.icns, app bundle)
- [x] Build script for .app bundle generation
- [x] DMG/package creation
- [x] Help documentation (⌘?)
- [x] User-friendly error messages
- [ ] Code signing (Apple Developer Program)
- [ ] Final QA with target hardware

---

## Phase 9: Expansion Vision — Universal Disc Utility + Audio Player

### Motivation
The classic macOS `/Applications/Burn.app` has been discontinued since macOS Catalina. There's no modern native replacement that handles all disc operations on Apple Silicon. Spalam Sie has the right foundation — cdrdao SCSI passthrough, SwiftUI native UI, modular architecture — to become that replacement.

### 9A. Data CD/DVD Burning
- [ ] Burn data discs (CD-R/RW, DVD±R/RW) with Joliet/ISO 9660 filesystem
- [ ] Hybrid HFS+/ISO filesystem for macOS compatibility
- [ ] Drag-and-drop files/folders to build data session
- [ ] Multi-session support (add data to existing disc)
- [ ] Disc spanning for large datasets
- [ ] Packet writing (UDF) for DVD-RAM/DVD-RW

### 9B. Video DVD Burning
- [ ] Burn VIDEO_TS folders to DVD-Video
- [ ] Support for DVD+R/RW, DVD-R/RW
- [ ] Automatic VIDEO_TS structure validation
- [ ] Burn Blu-ray data discs (BD-R/RE) if drive supports it

### 9C. Disc Copy / Duplication
- [ ] Clone audio CD (read + burn in one operation)
- [ ] Clone data CD/DVD
- [ ] Create disc images (.iso, .img, .dmg, .toc)
- [ ] Write disc images to blank media
- [ ] On-the-fly copy (source→target with one drive)
- [ ] Batch duplication (multi-copy from one image)

### 9D. Audio Player — Lightweight & High-Quality
- [ ] Quick-listen panel for tracks before burning
- [ ] Simple playlist from burn session tracks
- [ ] High-quality audio output (CoreAudio, not ffmpeg)
- [ ] Gapless playback (important for live/classical albums)
- [ ] Waveform display / seek bar
- [ ] Playback of all supported formats (FLAC, WAV, MP3, AIFF, M4A)
- [ ] Transport controls (play/pause/next/prev/volume)
- [ ] Mini-player / floating window mode
- [ ] System media keys integration (MediaRemote)

### 9E. Advanced Features (Future)
- [ ] Batch processing (multi-disc burning queue)
- [ ] Print CD labels / jewel case inserts
- [ ] CD ripping (read audio tracks to FLAC/MP3)
- [ ] Metadata editor (per-track tag editing)
- [ ] MusicBrainz / AcoustID integration for auto-tagging
- [ ] Cover art display and printing
- [ ] Dark mode / accent color customization
- [ ] Multiple language support (localization)
- [ ] Command-line interface (spalam-cli for scripting)

### Architecture Notes for Expansion
- **Disc modes**: Switchable "mode" (Audio / Data / Video / Copy / Player) at the top of the window, similar to Xcode scheme selector
- **Data track**: New `DataTrack` model + `mkisofs`/`genisoimage` integration
- **Video track**: Validate VIDEO_TS structure, use `growisofs` for DVD burns
- **Copy mode**: Two-pane view (source drive → target drive) with sector-by-sector copy
- **Player**: Separate `AudioPlayerEngine` class using AVAudioEngine on macOS 14+
- **Modularity preserved**: Each new capability is its own target/framework within the SPM package

### Success Criteria for Phase 9
1. Application launches with mode selector
2. Data: Burns standard ISO 9660 + Joliet data discs readable on Mac/PC
3. Video: Burns VIDEO_TS DVD playable in set-top players
4. Copy: Clones audio CD and data CD/DVD correctly
5. Player: Plays all audio formats supported by the burner
6. All operations are logged and recoverable on error

---

## Current Status (July 2026)

| Module | Status | Notes |
|--------|--------|-------|
| AudioConverter | ✅ | FLAC/MP3/WAV/AIFF/M4A → 44.1kHz/16-bit WAV |
| MetadataExtractor | ✅ | ffprobe-based metadata extraction |
| CUEParser | ✅ | Full CUE parsing with multi-track files |
| CDTEXTGenerator | ✅ | TOC generation with CD-TEXT, Polish chars |
| BurnEngine | ✅ | cdrdao/cdrecord, device detection, progress, verify |
| SwiftUI UI | ✅ | Full interface: tracks, controls, log, drag-drop |
| ConfigManager | ✅ | Persistent settings via UserDefaults |
| HelpView | ✅ | In-app documentation (⌘?) |
| File Types | ✅ | Association with .wav .flac .mp3 .aiff .cue .toc |
| Per-track edit | ✅ | Double-click title to edit |
| CUE support | ✅ | Parse CUE, split audio, preserve metadata |
| Post-burn verify | ✅ | Read-TOC, track count comparison |
| Unit tests | ✅ | 29 tests |
| Integration tests | ⬜ | User-managed |
| Hardware testing | ⬜ | Pending with TSSTcorp SU-208DB |
| Code signing | ⬜ | Requires Apple Developer account |
| Audio Player | ⬜ | Phase 9 expansion |
| Data/Video/Copy | ⬜ | Phase 9 expansion |

### Build & Run
```bash
cd ~/Desktop/Spalam\ Sie
bash build-app.sh         # Build release .app bundle
open "Spalam Sie.app"     # Launch
```

### Test
```bash
cd ~/Desktop/Spalam\ Sie
swift test                # Run all tests
```
