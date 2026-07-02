# Product Requirements Document — Phase 9
## Spalam Sie: Universal Disc Utility + Audio Player

**Status:** Draft v1.0 | **Date:** 2026-07-02 | **Author:** CEO

---

## 1. Vision

Spalam Sie evolves from audio CD burner into a **universal macOS disc utility** — the modern replacement for the discontinued Apple Burn.app — with an integrated **lightweight high-quality audio player**.

## 2. Target Users

1. **Music enthusiasts** burning audio CDs from FLAC/MP3 collections
2. **Mac users** needing to burn data DVDs (no native Burn.app since macOS Catalina)
3. **Video archivists** creating DVD-Video discs from digital files
4. **Audiophiles** wanting gapless FLAC playback with minimal UI
5. **System admins** scripting disc operations via CLI

## 3. Feature Scope

### Phase 9A — Data CD/DVD Burning
- [ ] ISO 9660 filesystem with Rock Ridge + Joliet
- [ ] Hybrid HFS+/ISO for Mac+PC compatibility
- [ ] Drag-and-drop files/folders to build data session
- [ ] UDF support for DVD-Video and BD
- [ ] Multi-session append
- [ ] Blank CD-RW/DVD-RW before write
- [ ] Disc capacity gauge

### Phase 9B — Video DVD Burning
- [ ] ffmpeg → MPEG-2 conversion with correct aspect/PAR
- [ ] dvdauthor VIDEO_TS creation
- [ ] Burn with growisofs -dvd-video
- [ ] NTSC/PAL auto-detection
- [ ] Simple menu (optional, stretch goal)
- [ ] ISO image generation before burn

### Phase 9C — Disc Copy/Duplication
- [ ] Audio CD clone (cdrdao read-cd + write)
- [ ] Data CD clone (readcd -clone + cdrecord)
- [ ] DVD image creation (hdiutil)
- [ ] On-the-fly copy (source→target single pass)
- [ ] Batch duplication (multi-copy from one image)
- [ ] Verify after copy (TOC comparison)

### Phase 9D — Audio Player
- [ ] Gapless playback via AVAudioEngine + source node
- [ ] All source formats: FLAC, WAV, AIFF, MP3, M4A, Opus
- [ ] Decode via ffmpeg → PCM buffer
- [ ] Transport controls (play/pause/next/prev/volume)
- [ ] Now playing bar integrated with burn session
- [ ] Waveform overview
- [ ] System media keys (MediaRemote)
- [ ] Mini-player / floating window mode

## 4. Architecture Decisions

### 4.1 Mode Selector
Add a **mode picker** at the top of the window (segmented control):
- **Audio CD** (current UI)
- **Data Disc** (new: file browser + ISO options)
- **Copy Disc** (new: two-pane source/target)
- **Player** (new: playback controls overlay)

Each mode swaps the main content area. Shared components: device status, log, eject.

### 4.2 Module Organization

```
Sources/
  Burning/
    BurnEngine.swift              ← existing, extended for data/video
  DataDisc/                       ← NEW: data disc operations
    DataDiscSession.swift         ← model for data tracks/files
    ISOBuilder.swift              ← mkisofs wrapper
  VideoDVD/                       ← NEW: video DVD operations
    VideoDVDSession.swift         ← model for video sources
    DVDAuthorController.swift     ← ffmpeg + dvdauthor wrapper
  CopyDisc/                       ← NEW: disc copy/duplication
    DiscCopySession.swift         ← copy workflow model
    CloneEngine.swift             ← cdrdao read-cd + write coordinator
  Player/                         ← NEW: audio player
    AudioPlayerEngine.swift       ← AVAudioEngine wrapper
    AudioPlayerView.swift         ← playback UI
  Spalam Sie/
    Models/
      BurnSession.swift           ← existing
    Views/
      ContentView.swift           ← extended with mode picker
      DataDiscView.swift          ← NEW
      VideoDVDView.swift          ← NEW
      CopyDiscView.swift          ← NEW
      PlayerView.swift            ← NEW
    Config/
      ConfigManager.swift         ← extended
```

### 4.3 Tool Dependencies

| Tool | Purpose | brew install |
|---|---|---|
| `mkisofs` | ISO 9660 + Joliet + Rock Ridge creation | `brew install cdrtools` |
| `cdrecord` | Burn data/audio to CD/DVD/BD | `brew install cdrtools` |
| `growisofs` | Burn DVD+RW/-R, BD, multi-session | `brew install dvd+rw-tools` |
| `readcd` | Clone data CDs sector-by-sector | `brew install cdrtools` |
| `ffmpeg` | Video→MPEG-2 conversion, audio decode for player | `brew install ffmpeg` |
| `dvdauthor` | VIDEO_TS authoring | `brew install dvdauthor` |
| `dvd+rw-format` | Format DVD+RW before use | `brew install dvd+rw-tools` |

### 4.4 Thread Safety
- All tool invocations via `Process` (already implemented)
- Progress reported via async/await or callback closures
- `@MainActor` models for UI-bound state
- Player runs on separate audio thread via `AVAudioEngine`

## 5. Quality Attributes

| Attribute | Target | Method |
|---|---|---|
| Reliability | <1% burn failure rate | Simulation mode before real burns |
| Compatibility | Discs readable on Mac/PC/Linux | Hybrid ISO+Joliet+HFS |
| Performance | Burn at max rated drive speed | Configurable speed, large FIFO |
| Audio quality | Bit-perfect FLAC playback | PCM pipeline without resampling |
| Memory | <200MB idle, <500MB during burn | Lazy loading, temp file cleanup |

## 6. Constraints
- macOS 14+ (Sonoma) minimum
- Apple Silicon native (ARM64)
- All dependencies via Homebrew (no bundled binaries)
- Open Source MIT License

## 7. Success Criteria
1. Data disc burns readable on macOS, Windows 11, and Linux
2. DVD-Video plays on standalone DVD players and game consoles
3. Clone copies produce discs with identical TOC and data
4. Audio player delivers gapless FLAC playback at 44.1kHz/16-bit
5. All operations work via SCSI passthrough on Apple Silicon USB drives
6. Burn simulation succeeds without media (dry-run validation)

---

*End of PRD v1.0*
