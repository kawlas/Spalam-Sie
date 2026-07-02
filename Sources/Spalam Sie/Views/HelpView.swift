import SwiftUI

/// Help and documentation window for Spalam Sie.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        TabView {
            gettingStartedTab
            formatsTab
            troubleshootingTab
            aboutTab
        }
        .frame(width: 580, height: 480)
        .padding()
    }
    
    // MARK: - Getting Started
    
    private var gettingStartedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "opticaldiscdrive")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                
                Text("Getting Started")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                
                helpSection(
                    title: "1. Add Audio Files",
                    text: "Drag-and-drop audio files (WAV, FLAC, MP3, AIFF, M4A) onto the main window, or use File → Add Audio Files (⌘O). You can also add entire folders — they will be scanned recursively for supported audio files."
                )
                
                helpSection(
                    title: "2. CUE Sheets",
                    text: "Drop a .cue file to load all its tracks at once with metadata. If the CUE references a single large audio file, tracks are automatically split at the correct positions during burning."
                )
                
                helpSection(
                    title: "3. Review & Edit",
                    text: "Double-click a track title to edit it. Use the Album Details section on the right to set global album artist and title. Drag tracks to reorder them."
                )
                
                helpSection(
                    title: "4. Configure Burn Settings",
                    text: "Select burn speed (4x recommended for USB 2.0). Enable Simulation mode to test without writing. BurnProof prevents buffer underruns."
                )
                
                helpSection(
                    title: "5. Burn!",
                    text: "Click 'Burn CD' to write your audio CD. For simulation, click 'Simulate Burn' — the TOC is validated but the disc is NOT written."
                )
            }
            .padding()
        }
        .tabItem { Label("Getting Started", systemImage: "house") }
    }
    
    // MARK: - Supported Formats
    
    private var formatsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                
                Text("Supported Formats")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        formatRow(name: "WAV", ext: ".wav, .wave", detail: "Recommended. Copied directly with format validation (converted to 44.1kHz/16-bit if needed).")
                        formatRow(name: "FLAC", ext: ".flac", detail: "Lossless. Decoded to WAV at CD quality via flac + ffmpeg.")
                        formatRow(name: "MP3", ext: ".mp3", detail: "Lossy. Decoded to WAV via ffmpeg. Best results from high-bitrate sources (320 kbps).")
                        formatRow(name: "AIFF", ext: ".aiff, .aif", detail: "Apple format. Converted via ffmpeg.")
                        formatRow(name: "M4A/AAC", ext: ".m4a", detail: "Lossy. Converted via ffmpeg.")
                        formatRow(name: "CUE", ext: ".cue", detail: "CUE sheet parser. Loads track metadata and splits referenced audio files automatically.")
                    }
                    .padding(.vertical, 4)
                }
                
                Divider()
                
                Text("Output Format")
                    .font(.headline)
                
                Text("All audio is converted to CD-DA standard: 44.1 kHz sample rate, 16-bit signed integer, 2 channels (stereo), PCM WAV format. This is the only format supported by the Red Book audio CD standard.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .tabItem { Label("Formats", systemImage: "doc.text") }
    }
    
    // MARK: - Troubleshooting
    
    private var troubleshootingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "wrench.adjustable")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                
                Text("Troubleshooting")
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                
                helpSection(
                    title: "Drive not detected",
                    text: "Make sure your USB optical drive is connected. Try a different USB port or hub (USB 2.0 recommended). Click the refresh (↻) button next to the Device picker. Check Console.app for SCSI errors."
                )
                
                helpSection(
                    title: "Burn fails or buffer underrun",
                    text: "Reduce burn speed to 4x or 2x. This is especially important for USB 2.0 connections. Make sure BurnProof/JustLink is enabled. Try a different brand of CD-R discs."
                )
                
                helpSection(
                    title: "Disc ejected but not recognized",
                    text: "Some drives need the disc to be unmounted before the OS recognizes the newly written audio CD. Use Disk Utility to mount the disc, or re-insert it."
                )
                
                helpSection(
                    title: "Missing tools (cdrdao, ffmpeg)",
                    text: "Spalam Sie requires Homebrew-installed tools. Run: brew install cdrdao cdrtools ffmpeg flac lame. Check Config → Tools to verify all paths."
                )
                
                helpSection(
                    title: "Audio CD doesn't play in car stereo",
                    text: "Some car stereos require CD-TEXT or specific write modes. Try SAO (Session-At-Once) mode. Ensure audio is truly 44.1kHz/16-bit/stereo. Old car stereos may not read CD-R discs."
                )
            }
            .padding()
        }
        .tabItem { Label("Troubleshooting", systemImage: "wrench") }
    }
    
    // MARK: - About
    
    private var aboutTab: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            
            Text("Spalam Sie")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Version 1.0")
                .foregroundColor(.secondary)
            
            Text("Native CD burning application for macOS Apple Silicon.\nBurns audio CDs from FLAC, MP3, WAV, AIFF, M4A, and CUE sheets.\nUses cdrdao for SCSI passthrough on USB optical drives.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.callout)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Requires macOS 14+ (Sonoma)", systemImage: "macbook")
                Label("Apple Silicon native", systemImage: "cpu")
                Label("Open Source — MIT License", systemImage: "swift")
                Label("Built with SwiftUI + cdrdao", systemImage: "hammer")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            Spacer()
            
            Text("© 2026 Spalam Sie. All rights reserved.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .tabItem { Label("About", systemImage: "info.circle") }
    }
    
    // MARK: - Helpers
    
    private func helpSection(title: String, text: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func formatRow(name: String, ext: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(name)
                .fontWeight(.semibold)
                .frame(width: 50, alignment: .leading)
            Text(ext)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

#Preview {
    HelpView()
}
