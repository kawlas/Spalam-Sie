import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// macOS-native audio player view powered by SFBAudioEngine.
struct PlayerView: View {
    @ObservedObject var player: AudioPlayerEngine
    @State private var showFilePicker = false
    
    init(player: AudioPlayerEngine = AudioPlayerEngine()) {
        self.player = player
    }
    
    // Time tracking
    @State private var seekPosition: Double = 0
    @State private var isSeeking = false
    @State private var timerHandle: Timer?
    
    // Queue display
    @State private var draggedIndex: Int?
    @State private var isDropTargeted = false
    
    private let timeFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.zeroFormattingBehavior = .pad
        return f
    }()
    
    var body: some View {
        HSplitView {
            // === LEFT: Track List / Queue ===
            queueSidebar
                .frame(minWidth: 200, idealWidth: 280)
            
            // === RIGHT: Now Playing + Controls ===
            nowPlayingPanel
                .frame(minWidth: 400, idealWidth: 500)
        }
        .frame(minHeight: 400)
        .toolbar { toolbarContent }
        .background(isDropTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: Self.supportedAudioTypes,
            allowsMultipleSelection: true,
            onCompletion: handleFileImport
        )
        .onReceive(player.$state) { state in
            if state == .playing || state == .paused {
                startTimeUpdates()
            } else {
                stopTimeUpdates()
            }
        }
        .onReceive(player.$currentTime) { time in
            if !isSeeking {
                seekPosition = player.totalTime > 0 ? time / player.totalTime : 0
            }
        }
    }
    
    // MARK: - Queue Sidebar
    
    private var queueSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Kolejka")
                    .font(.headline)
                Spacer()
                if player.queueCount > 0 {
                    Text("\(player.queueCount) utworów")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
            
            if player.queueCount == 0 {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Kolejka pusta")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Otwórz pliki audio przez ⌘O\nalbo przeciągnij na okno")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Wybierz pliki audio…") {
                        showFilePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(Array(player.queueURLs.enumerated()), id: \.offset) { index, url in
                        QueueRow(
                            index: index,
                            url: url,
                            isCurrent: index == player.currentIndex
                        )
                        .onTapGesture(count: 2) {
                            try? player.playAt(index: index)
                        }
                    }
                    .onMove { from, to in
                        player.moveQueue(from: from, to: to)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - Now Playing Panel
    
    private var nowPlayingPanel: some View {
        VStack(spacing: 0) {
            // Album art / placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(artworkGradient)
                    .frame(width: 240, height: 240)
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                
                if let artworkData = player.currentArtworkData, let artwork = NSImage(data: artworkData) {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 240, height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: player.state == .playing ? "waveform" : "music.note")
                        .font(.system(size: 72))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.top, 32)
            
            // Track info
            VStack(spacing: 4) {
                Text(player.nowPlayingTitle.isEmpty ? "Brak utworu" : player.nowPlayingTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Text(player.nowPlayingArtist.isEmpty ? "Nieznany artysta" : player.nowPlayingArtist)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.top, 20)
            
            // Seek bar
            VStack(spacing: 6) {
                Slider(
                    value: $seekPosition,
                    in: 0...1,
                    onEditingChanged: { editing in
                        isSeeking = editing
                        if !editing {
                            player.seek(position: seekPosition)
                        }
                    }
                )
                .disabled(player.state == .stopped)
                
                HStack {
                    Text(formatTime(player.currentTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text(formatTime(player.totalTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 12)
            
            // Transport controls
            HStack(spacing: 28) {
                Button(action: { try? player.previous() }) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(player.state == .stopped)
                
                Button(action: { togglePlayPause() }) {
                    Image(systemName: player.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .disabled(player.state == .stopped && player.queueCount == 0)
                
                Button(action: { try? player.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(player.state == .stopped)
            }
            .padding(.top, 16)
            
            // Volume
            HStack(spacing: 10) {
                Image(systemName: volumeIconName)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                Slider(value: $player.volume, in: 0...1)
                    .frame(width: 180)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            }
            .padding(.top, 16)
            
            // Status
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 12)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showFilePicker = true }) {
                Label("Otwórz pliki", systemImage: "folder")
            }
        }
        
        ToolbarItem(placement: .primaryAction) {
            Button(action: { player.stop() }) {
                Label("Zatrzymaj", systemImage: "stop.fill")
            }
            .keyboardShortcut(".")
            .disabled(player.state == .stopped)
        }
    }
    
    // MARK: - Actions
    
    private func togglePlayPause() {
        switch player.state {
        case .playing:
            player.pause()
        case .paused:
            player.resume()
        case .stopped, .loading:
            if player.queueCount > 0 {
                try? player.playAt(index: 0)
            }
        case .error:
            player.stop()
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            if case .failure(let error) = result {
                print("❌ File import failed: \(error.localizedDescription)")
            }
            return
        }
        let audioURLs = urls.filter { isAudioFile($0) }
        guard !audioURLs.isEmpty else {
            print("⚠️ No supported audio files selected")
            return
        }
        
        do {
            if player.queueCount == 0 {
                try player.playQueue(urls: audioURLs)
                print("▶️ Playing \(audioURLs.count) file(s)")
            } else {
                for url in audioURLs {
                    try player.queue(url: url)
                }
                print("➕ Queued \(audioURLs.count) file(s)")
            }
        } catch {
            print("❌ Playback error: \(error.localizedDescription)")
            player.reportError(error.localizedDescription)
        }
    }
    
    private func isAudioFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["flac", "wav", "mp3", "aiff", "aif", "m4a", "aac", "ogg", "opus",
                "wv", "wavpack", "dsf", "dff", "ape", "alac"].contains(ext)
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        let urls = FileDropExtractor.extractURLs(from: providers)
        let audioURLs = urls.filter { isAudioFile($0) }
        guard !audioURLs.isEmpty else { return }
        DispatchQueue.main.async { [self] in
            if player.queueCount == 0 {
                try? player.playQueue(urls: audioURLs)
            } else {
                for url in audioURLs {
                    try? player.queue(url: url)
                }
            }
        }
    }
    
    // MARK: - Time updates
    
    private func startTimeUpdates() {
        stopTimeUpdates()
        timerHandle = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [self] _ in
            Task { @MainActor in
                self.player.refreshTime()
            }
        }
    }
    
    private func stopTimeUpdates() {
        timerHandle?.invalidate()
        timerHandle = nil
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0:00" }
        return timeFormatter.string(from: interval) ?? "0:00"
    }
    
    private var volumeIconName: String {
        switch player.volume {
        case ..<0.01: return "speaker.slash.fill"
        case ..<0.33: return "speaker.fill"
        case ..<0.66: return "speaker.wave.2.fill"
        default:       return "speaker.wave.3.fill"
        }
    }
    
    private var statusColor: Color {
        switch player.state {
        case .playing:  return .green
        case .paused:   return .orange
        case .stopped:  return .secondary
        case .loading:  return .yellow
        case .error:    return .red
        }
    }
    
    private var statusText: String {
        switch player.state {
        case .playing:  return "Odtwarzanie"
        case .paused:   return "Wstrzymane"
        case .stopped:  return "Zatrzymany"
        case .loading:  return "Wczytywanie..."
        case .error(let e): return "Błąd: \(e)"
        }
    }
    
    private var artworkGradient: LinearGradient {
        LinearGradient(
            colors: [.accentColor.opacity(0.6), .accentColor.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// All supported audio file UTTypes for the file importer.
    static let supportedAudioTypes: [UTType] = {
        var types: [UTType] = [
            .wav, .mp3, .mpeg4Audio, .aiff,
            .audio
        ]
        // FLAC – create from extension since it may not be in the system database
        if let flac = UTType(tag: "flac", tagClass: .filenameExtension, conformingTo: .audio) {
            types.append(flac)
        }
        // OGG / Opus
        if let ogg = UTType(tag: "ogg", tagClass: .filenameExtension, conformingTo: .audio) {
            types.append(ogg)
        }
        if let opus = UTType(tag: "opus", tagClass: .filenameExtension, conformingTo: .audio) {
            types.append(opus)
        }
        // APE
        if let ape = UTType(tag: "ape", tagClass: .filenameExtension, conformingTo: .audio) {
            types.append(ape)
        }
        // WavPack
        if let wv = UTType(tag: "wv", tagClass: .filenameExtension, conformingTo: .audio) {
            types.append(wv)
        }
        // DSD
        if let dsf = UTType(tag: "dsf", tagClass: .filenameExtension, conformingTo: .audio) {
            types.append(dsf)
        }
        if let dff = UTType(tag: "dff", tagClass: .filenameExtension, conformingTo: .audio) {
            types.append(dff)
        }
        return types
    }()
    
    /// Public entry point for ContentView to forward picked files to the player.
    func importFiles(_ urls: [URL]) {
        let audioURLs = urls.filter { isAudioFile($0) }
        guard !audioURLs.isEmpty else {
            print("⚠️ No supported audio files selected")
            return
        }
        do {
            if player.queueCount == 0 {
                try player.playQueue(urls: audioURLs)
                print("▶️ Playing \(audioURLs.count) file(s)")
            } else {
                for url in audioURLs {
                    try player.queue(url: url)
                }
                print("➕ Queued \(audioURLs.count) file(s)")
            }
        } catch {
            print("❌ Playback error: \(error.localizedDescription)")
            player.reportError(error.localizedDescription)
        }
    }
}

// MARK: - Queue Row

struct QueueRow: View {
    let index: Int
    let url: URL
    let isCurrent: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.body)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                Text(url.pathExtension.uppercased())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isCurrent {
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .background(isCurrent ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(4)
    }
}

// MARK: - Preview

#Preview {
    PlayerView()
        .frame(width: 800, height: 500)
}
