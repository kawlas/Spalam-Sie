import SwiftUI

struct ContentView: View {
    @EnvironmentObject var session: BurnSession
    @State private var isDropTargeted = false
    @State private var showFilePicker = false
    @State private var showHelp = false
    @State private var selectedMode: DiscMode = .audio
    
    var body: some View {
        HSplitView {
            // Left panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 28, height: 28)
                    Text("Spalam Sie")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    deviceStatusBadge
                    ejectButton
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                
                // Mode picker
                Picker("Mode", selection: $selectedMode) {
                    ForEach(DiscMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.iconName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // Mode content
                switch selectedMode {
                case .audio:
                    if session.tracks.isEmpty {
                        dropZone
                    } else {
                        TrackListView()
                            .environmentObject(session)
                    }
                case .data:
                    DataDiscView()
                case .copy:
                    CopyDiscView()
                case .video:
                    VideoDVDView()
                case .player:
                    PlayerView()
                }
            }
            .frame(minWidth: 350)
            
            // Right panel: Controls (varies by mode)
            rightPanel
                .frame(minWidth: 300, idealWidth: 350)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
            showHelp = true
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
    }
    
    // MARK: - Right Panel
    
    @ViewBuilder
    private var rightPanel: some View {
        switch selectedMode {
        case .audio:
            audioRightPanel
        case .data:
            dataRightPanel
        case .copy:
            copyRightPanel
        case .video:
            videoRightPanel
        case .player:
            playerRightPanel
        }
    }
    
    private var audioRightPanel: some View {
        VStack(spacing: 0) {
            albumInfoSection
                .padding()
            
            if !session.tracks.isEmpty {
                durationSummaryView
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
            
            Divider()
            
            BurnControlsView()
                .environmentObject(session)
            
            Divider()
            
            logSection
        }
    }
    
    private var dataRightPanel: some View {
        VStack(spacing: 0) {
            albumInfoSection
                .padding()
            
            Divider()
            
            BurnControlsView()
                .environmentObject(session)
            
            Divider()
            
            logSection
        }
    }
    
    private var copyRightPanel: some View {
        VStack(spacing: 0) {
            albumInfoSection
                .padding()
            
            Divider()
            
            // Copy-specific controls
            VStack {
                Text("Copy mode")
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            logSection
        }
    }
    
    private var videoRightPanel: some View {
        VStack(spacing: 0) {
            albumInfoSection
                .padding()
            
            Divider()
            
            VStack {
                Text("Video DVD mode")
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            logSection
        }
    }
    
    private var playerRightPanel: some View {
        VStack(spacing: 0) {
            albumInfoSection
                .padding()
            
            Divider()
            
            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("Playlista")
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            logSection
        }
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Album Details")
                .font(.headline)
            
            HStack {
                Text("Artist:")
                    .frame(width: 60, alignment: .trailing)
                    .foregroundColor(.secondary)
                TextField("Artist name", text: $session.albumArtist)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Text("Album:")
                    .frame(width: 60, alignment: .trailing)
                    .foregroundColor(.secondary)
                TextField("Album title", text: $session.albumTitle)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Text("Device:")
                    .frame(width: 60, alignment: .trailing)
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
        }
    }
    
    // MARK: - Duration Summary
    
    private var durationSummaryView: some View {
        VStack(spacing: 2) {
            let total = session.totalDuration
            let cdCapacity: TimeInterval = 80 * 60 // 80 minutes max
            let usedPct = total > 0 ? min(total / cdCapacity, 1.0) : 0
            let remaining = max(cdCapacity - total, 0)
            
            HStack {
                Label("\(session.tracks.count) tracks", systemImage: "music.note.list")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTime(total))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(usedPct > 0.95 ? .red : .secondary)
            }
            
            HStack {
                Text("CD: 80:00 max")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if total > 0 {
                    Text("Remaining: \(formatTime(remaining))")
                        .font(.caption2)
                        .foregroundColor(usedPct > 0.95 ? .red : .green)
                }
            }
            
            // Progress bar
            if total > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 6)
                        Capsule()
                            .fill(usedPct > 0.95 ? Color.red : usedPct > 0.85 ? Color.orange : Color.green)
                            .frame(width: geo.size.width * usedPct, height: 6)
                    }
                }
                .frame(height: 6)
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
            
            ScrollViewReader { _ in
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
            }
        }
        .padding()
    }
    
    // MARK: - Drop Handling
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        
        for provider in providers {
            // Handle both files and folders
            let typeIdentifiers = provider.registeredTypeIdentifiers
            if typeIdentifiers.contains("public.file-url") ||
               typeIdentifiers.contains("public.directory") ||
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
