import SwiftUI

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
    
    @State private var selectedTab: AppTab = .player
    @State private var burnerSection: BurnerSection = .audio
    @State private var showHelp = false
    @State private var showFilePicker = false
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
    }
    
    // MARK: - Player Content
    
    private var playerContent: some View {
        VStack {
            if session.tracks.isEmpty {
                // Empty state — show album grid placeholder
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "music.note.house")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Twoja biblioteka muzyczna")
                        .font(.title2)
                    Text("Dodaj foldery z muzyką aby rozpocząć")
                        .foregroundColor(.secondary)
                    Button("Dodaj folder") {
                        showFilePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Tracks from burner session — quick preview
                TrackListView()
                    .environmentObject(session)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder, .audio, .wav,
                                 .init(filenameExtension: "flac") ?? .data,
                                 .init(filenameExtension: "mp3") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                session.addFiles(urls)
            }
        }
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
        VStack(spacing: 0) {
            // Now playing (placeholder)
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("Odtwarzacz")
                    .font(.headline)
                Text("Wybierz utwór z biblioteki")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Volume
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundColor(.secondary)
                Slider(value: .constant(0.7), in: 0...1)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Queue / playlist
            VStack(alignment: .leading) {
                Text("Kolejka")
                    .font(.headline)
                    .padding(.horizontal)
                if session.tracks.isEmpty {
                    Text("Brak utworów")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                } else {
                    List(Array(session.tracks.enumerated()), id: \.offset) { _, track in
                        Text(track.title)
                            .font(.caption)
                    }
                    .listStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            
            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
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
