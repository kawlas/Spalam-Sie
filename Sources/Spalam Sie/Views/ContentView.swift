import SwiftUI

/// Target for the ⌘O open-files command, decided by the active tab.
enum OpenTarget: Equatable {
    case playerFiles
    case burnerTracks
}

/// Pure dispatch logic for ⌘O — testable without SwiftUI.
func openTarget(for tab: AppTab) -> OpenTarget {
    switch tab {
    case .player: return .playerFiles
    case .burner: return .burnerTracks
    }
}

enum AppTab: String, CaseIterable {
    case player = "Player"
    case burner = "Burner"
}

enum BurnerSection: String, CaseIterable, Identifiable {
    case audio  = "Audio CD"
    case data   = "Data Disc"
    case copy   = "Copy Disc"
    case video  = "Video DVD"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .audio: return "music.note.list"
        case .data:  return "externaldrive"
        case .copy:  return "rectangle.on.rectangle"
        case .video: return "film"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var session: BurnSession
    @EnvironmentObject var configManager: ConfigManager
    @StateObject private var playerEngine = AudioPlayerEngine()
    
    @State private var selectedTab: AppTab = .player
    @State private var burnerSection: BurnerSection = .audio
    @State private var showHelp = false
    @State private var showFilePicker = false
    @State private var showPlayerFilePicker = false
    @State private var isDropTargeted = false
    
    var body: some View {
        HSplitView {
            // === LEFT PANEL ===
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text("Spalam Sie")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Button("Open") { handleOpenCommand() }
                        .keyboardShortcut("o", modifiers: .command)
                        .opacity(0)
                    Spacer()
                    deviceStatusBadge
                    ejectButton
                    helpButton
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor))
                
                // Tab selector
                Picker("", selection: $selectedTab) {
                    Text("🎵  Player").tag(AppTab.player)
                    Text("🔥  Burner").tag(AppTab.burner)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                
                // Content
                switch selectedTab {
                case .player:
                    playerContent
                case .burner:
                    burnerContent
                }
            }
            .frame(minWidth: 400)
            
            // === RIGHT PANEL ===
            rightPanel
                .frame(minWidth: 280, idealWidth: 320)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
            showHelp = true
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .fileImporter(
            isPresented: $showPlayerFilePicker,
            allowedContentTypes: PlayerView.supportedAudioTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                playerContentImporter(urls)
            }
        }
    }
    
    // MARK: - Player Content
    
    private var playerContent: some View {
        PlayerView(player: playerEngine)
    }
    
    // MARK: - Burner Content
    
    private var burnerContent: some View {
        NavigationSplitView {
            // Sidebar
            List(BurnerSection.allCases, selection: $burnerSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 140, idealWidth: 160)
        } detail: {
            // Content
            switch burnerSection {
            case .audio:
                audioBurnerView
            case .data:
                DataDiscView()
            case .copy:
                CopyDiscView()
            case .video:
                VideoDVDView()
            }
        }
        .navigationSplitViewStyle(.automatic)
    }
    
    private var audioBurnerView: some View {
        Group {
            if session.tracks.isEmpty {
                dropZone
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackListView()
                    .environmentObject(session)
            }
        }
    }
    
    // MARK: - Right Panel
    
    @ViewBuilder
    private var rightPanel: some View {
        switch selectedTab {
        case .player:
            playerRightPanel
        case .burner:
            burnerRightPanel
        }
    }
    
    private var playerRightPanel: some View {
        EmptyView()
    }
    
    private var burnerRightPanel: some View {
        VStack(spacing: 0) {
            // Info section
            albumInfoSection
                .padding()
            
            Divider()
            
            // Burn controls
            BurnControlsView()
                .environmentObject(session)
            
            Divider()
            
            // Log
            logSection
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Device Status
    
    private var deviceStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(session.detectedDevice != nil ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(session.detectedDevice != nil ? "Online" : "No Drive")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var ejectButton: some View {
        Button(action: ejectDisc) {
            Image(systemName: "eject")
                .foregroundColor(.secondary)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Eject disc")
    }
    
    private var helpButton: some View {
        Button(action: { showHelp = true }) {
            Image(systemName: "questionmark.circle")
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Help (⌘?)")
    }
    
    private func ejectDisc() {
        let engine = BurnEngine()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try engine.eject(iokitPath: self.session.deviceAddress)
                DispatchQueue.main.async {
                    self.session.appendLog("Disc ejected")
                }
            } catch {
                DispatchQueue.main.async {
                    self.session.appendLog("Eject failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Open Command
    
    private func handleOpenCommand() {
        switch openTarget(for: selectedTab) {
        case .playerFiles:
            showPlayerFilePicker = true
        case .burnerTracks:
            showFilePicker = true
        }
    }
    
    private func playerContentImporter(_ urls: [URL]) {
        let audioURLs = urls.filter { isAudioFile($0) }
        guard !audioURLs.isEmpty else { return }
        do {
            if playerEngine.queueCount == 0 {
                try playerEngine.playQueue(urls: audioURLs)
            } else {
                for url in audioURLs {
                    try playerEngine.queue(url: url)
                }
            }
        } catch {
            print("❌ Playback error: \(error.localizedDescription)")
            playerEngine.reportError(error.localizedDescription)
        }
    }
    
    private func isAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["flac", "wav", "mp3", "aiff", "aif", "m4a", "aac", "ogg", "opus",
                "wv", "wavpack", "dsf", "dff", "ape", "alac"].contains(ext)
    }
    
    // MARK: - Drop Zone
    
    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .foregroundColor(isDropTargeted ? .accentColor : .secondary.opacity(0.4))
                .padding(20)
            
            VStack(spacing: 16) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                
                Text("Drop audio files here")
                    .font(.title3)
                    .foregroundColor(.secondary)
                
                Text("or")
                    .foregroundColor(.secondary)
                
                Button("Select Files...") {
                    showFilePicker = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder, .wav, .audio,
                                 .init(filenameExtension: "flac") ?? .data,
                                 .init(filenameExtension: "mp3") ?? .data,
                                 .init(filenameExtension: "aiff") ?? .data,
                                 .init(filenameExtension: "m4a") ?? .data,
                                 .init(filenameExtension: "cue") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                session.addFiles(urls)
            }
        }
    }
    
    // MARK: - Album Info
    
    private var albumInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Album Details")
                .font(.headline)
            
            HStack {
                Text("Artist:")
                    .frame(width: 56, alignment: .trailing)
                    .foregroundColor(.secondary)
                TextField("Artist name", text: $session.albumArtist)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Text("Album:")
                    .frame(width: 56, alignment: .trailing)
                    .foregroundColor(.secondary)
                TextField("Album title", text: $session.albumTitle)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Text("Device:")
                    .frame(width: 56, alignment: .trailing)
                    .foregroundColor(.secondary)
                Picker("", selection: $session.deviceAddress) {
                    Text(session.detectedDevice?.name ?? "Unknown")
                        .tag(session.deviceAddress)
                }
                .labelsHidden()
                
                Button(action: { session.refreshDevice() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Rescan devices")
            }
            
            if !session.tracks.isEmpty && selectedTab == .burner && burnerSection == .audio {
                durationSummaryView
            }
        }
    }
    
    // MARK: - Duration Summary
    
    private var durationSummaryView: some View {
        VStack(spacing: 2) {
            let total = session.totalDuration
            let cdCapacity: TimeInterval = 80 * 60
            let usedPct = total > 0 ? min(total / cdCapacity, 1.0) : 0
            
            HStack {
                Label("\(session.tracks.count) tracks", systemImage: "music.note.list")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTime(total))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(usedPct > 0.95 ? .red : .secondary)
            }
            
            if total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 5)
                        Capsule()
                            .fill(usedPct > 0.95 ? Color.red : usedPct > 0.85 ? Color.orange : Color.green)
                            .frame(width: geo.size.width * usedPct, height: 5)
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Log
    
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Log")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView {
                Text(session.log.isEmpty ? "Ready" : session.log)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .textSelection(.enabled)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Drop Handling via NSViewRepresentable (moved outside)
extension ContentView {
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            let typeIdentifiers = provider.registeredTypeIdentifiers
            if typeIdentifiers.contains("public.file-url") ||
               provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    var urlsToLoad: [URL] = []
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urlsToLoad.append(url)
                    } else if let url = item as? URL {
                        urlsToLoad.append(url)
                    }
                    if !urlsToLoad.isEmpty {
                        DispatchQueue.main.async {
                            self.session.addFiles(urlsToLoad)
                        }
                    }
                }
                handled = true
            }
        }
        return handled
    }
}
