# Spalam Sie

A reliable CD burning application for macOS Apple Silicon that bypasses the problematic DiscRecording framework and uses cdrdao for direct SCSI passthrough.

## 📊 Current Status (2026-07-02)

**Two-mode app:** Player (SFBAudioEngine, gapless, FLAC/ALAC/WAV/MP3/OGG/Opus/APE/DSD) + Burner (Audio CD / Data Disc / Copy Disc / Video DVD).

**Build:** `bash build-app.sh` → `Spalam Sie.app` (codesign ad-hoc, 10 SFBAudioEngine frameworks bundled). **Tests:** 147 / 0 failures / 2 skipped.

**Known open issues (see [docs/STATUS_2026-07-02.md](docs/STATUS_2026-07-02.md) for full report):**
- 🔴 **Drag&drop from Finder still broken** — drop highlight shows but file vanishes, never reaches list. Unit-tested extractor works but `.onDrop` in view hierarchy doesn't deliver. Priority 1 next session.
- 🟠 **Player + Burner concurrency UX missing** — no menu/popup info when player plays during burn; can't add more files to player once a track is playing.
- 🟡 Manual E2E with real CD hardware pending for: cancelBurn, CD-TEXT null fix, Data Disc burn.

**Stabilization done this session:** B1 security-scope leak, B7 ⌘O contextual, B-help sheet trap, B2 runWithTimeout real, B5 cancelBurn real, B-cdtext-null sanitization, B3 volume label, I2 Data Disc burn (a+b+c), FileDropExtractor + tests.

## 🔥 Overview

Spalam Sie (Polish for "I'm Burning") is a native macOS application designed to reliably burn audio CDs on Apple Silicon Macs, particularly addressing the challenges posed by USB optical drives connected through hubs (like the XD013 multi-function device).

## ⚠️ Problem Solved

Many users experience issues with CD burning on Apple Silicon Macs:
- USB pipe stall errors (`0xe0005000`)
- "SupportLevel: Unsupported" errors from Apple's DiscRecording framework
- Drive detection issues when connected through USB hubs
- Unreliable burning leading to coasters

Spalam Sie solves these by:
- Using **cdrdao** with direct **SCSI passthrough** via IOKit (bypassing DiscRecording entirely)
- Implementing proper **thread-safe** communication with background burning processes
- Providing **native SwiftUI** interface with full macOS integration
- Including **comprehensive error handling** and logging
- Supporting **drag-and-drop**, **file type associations**, and **native macOS behaviors**

## 🏗️ Architecture

```
Spalam Sie/
├── Spalam Sie.app/           # Application bundle
├── Sources/
│   ├── App/                  # SwiftUI interface
│   ├── Audio/                # Format conversion and validation
│   ├── Metadata/             # Tag reading and CD-TEXT generation
│   ├── Burning/              # cdrdao integration and device management
│   ├── Utilities/            # Logging, configuration, helpers
│   └── Shared/               # Common models and protocols
├── Tests/                    # Unit and UI tests
├── Resources/                # Assets, icons, etc.
└── PLAN.md                   # Detailed development roadmap
```

## 🛠️ Technologies

- **Language**: Swift 6
- **Framework**: SwiftUI (for native macOS experience)
- **Build System**: Swift Package Manager
- **Audio Processing**: ffmpeg, flac, lame (via Homebrew)
- **Burning Engine**: cdrdao (via Swift Process)
- **Dependencies**: None (uses system-provided tools via Homebrew)

## 📋 Features

### Audio Support
- **Input Formats**: FLAC, MP3, WAV, AIFF, M4A, AAC
- **Automatic Conversion**: Lossless and lossy to WAV 44.1kHz/16-bit stereo
- **Validation**: Ensures audio meets Red Book CD-DA standards

### Metadata & CD-TEXT
- **Tag Reading**: Extracts artist, title, album from audio files
- **CUE Sheet Support**: Parses and burns CUE/BIN combinations
- **CD-TEXT Generation**: Creates proper TEXT blocks in TOC files
- **Unicode Support**: Handles international characters correctly

### Burning Features
- **Device Auto-Detection**: Finds optical drives via IOKit
- **Burn Speed Selection**: Safe defaults for USB 2.0 (4x recommended)
- **Buffer Underrun Protection**: Uses drive's built-in BurnProof/JustLink
- **Simulation Mode**: Test burns without writing to disc
- **Progress Reporting**: Real-time burn progress feedback
- **Post-Burn Verification**: Optional read-back and compare

### User Experience
- **Drag-and-Drop**: From Finder to app window or Dock icon
- **Native File Associations**: Opens .cue, .toc, .flac, .mp3 files
- **Menu Bar Integration**: Standard macOS application menus
- **Accessibility**: Full VoiceOver support
- **Dark Mode**: Native dark/light mode support
- **Retina Display**: Optimized for high-resolution screens

## 📦 Installation

### Prerequisites
Install required command-line tools via Homebrew:
```bash
brew install cdrdao ffmpeg flac lame
```

### From Source
1. Clone this repository
2. Open `Spalam Sie.xcodeproj` in Xcode
3. Build and run (⌘R)

### Application Bundle
1. Download the latest release `.dmg`
2. Drag `Spalam Sie.app` to `/Applications`
3. First launch may require right-click → "Open" to bypass Gatekeeper

## 🧪 Development

### Running Tests
```bash
swift test
```

### Building for Release
```bash
swift build -c release --product SpalamSie
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [cdrdao](https://sourceforge.net/projects/cdrdao/) - The excellent CD recording software
- [OpenBurningSuite](https://github.com/SvenGDK/OpenBurningSuite) - Reference for SCSI implementation
- [BurnMan](https://github.com/blakyris/BurnMan) - SwiftUI + cdrdao inspiration
- Apple's SwiftUI and Combine frameworks

## 📞 Support

For issues, please check the [issue tracker](https://github.com/yourusername/spalam-sie/issues) or contact the maintainer.

*Created with ❤️ for everyone struggling with CD burning on Apple Silicon Macs.*