import Foundation
import AppKit
import Combine
import SFBAudioEngine

/// Player state exposed to UI.
public enum PlayerState: Equatable {
    case stopped
    case playing
    case paused
    case loading
    case error(String)
}

/// High-quality audio player powered by SFBAudioEngine.
///
/// Queue management is ENTIRELY manual:
/// - `queue` is the source of truth — never use `player.enqueue()`
/// - Tracks advance via delegate `audioPlayerEndOfAudio` → `next()` → `playAt()` → `playURL()` → `player.play(url)`
/// - This avoids double-playback from mixing two queue systems
@MainActor public class AudioPlayerEngine: NSObject, ObservableObject {
    
    private let player: AudioPlayer
    
    @Published public private(set) var state: PlayerState = .stopped
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var totalTime: TimeInterval = 0
    @Published public var volume: Float = 1.0 {
        didSet { try? player.setVolume(volume) }
    }
    @Published public private(set) var queueCount: Int = 0
    @Published public var playlistName: String = "Playlista"
    @Published public private(set) var nowPlayingTitle: String = ""
    @Published public private(set) var nowPlayingArtist: String = ""
    @Published public private(set) var currentURL: URL?
    @Published public private(set) var currentArtworkData: Data?
    
    /// All URLs currently in the queue (exposed for UI display).
    public var queueURLs: [URL] { queue }
    
    /// Index of the currently playing track, or -1 if none.
    public private(set) var currentIndex: Int = -1
    
    /// URLs for which security-scoped access has been started.
    public var securityScopedURLs: [URL] { Array(scopedURLs) }
    
    /// Auto-advance to next track when current finishes.
    public var autoAdvance: Bool = true
    
    /// Private backing array — source of truth for the queue.
    private var queue: [URL] = []
    
    /// Security-scoped URLs that are currently being accessed.
    private var scopedURLs: Set<URL> = []
    
    override public init() {
        self.player = AudioPlayer()
        super.init()
        self.player.delegate = self
    }
    
    // MARK: - Playback Control
    
    /// Play a single file immediately, replacing the queue.
    public func play(url: URL) throws {
        state = .loading
        queue = [url]
        currentIndex = 0
        syncQueueCount()
        try playCurrent()
    }
    
    /// Start the engine (no-op — AudioPlayer manages its own engine).
    public func start() throws {}
    
    /// Stop playback and purge the queue.
    public func stop() {
        player.stop()
        stopAllScopes()
        queue.removeAll()
        currentIndex = -1
        queueCount = 0
        clearNowPlaying()
        state = .stopped
    }
    
    /// Pause playback.
    public func pause() {
        player.pause()
        state = .paused
    }
    
    /// Resume playback.
    public func resume() {
        player.resume()
        state = .playing
    }
    
    /// Toggle play/pause.
    public func togglePlayPause() {
        try? player.togglePlayPause()
        syncPlaybackState()
    }
    
    /// Seek to a precise time position.
    public func seek(to time: TimeInterval) {
        player.seek(time: time)
    }
    
    /// Seek to a fractional position (0.0 – 1.0).
    public func seek(position: Double) {
        player.seek(position: position)
    }
    
    // MARK: - Queue Management
    
    /// Append one URL to the tail of the queue.
    /// Does NOT call `player.enqueue()` — manual queue only.
    public func queue(url: URL) throws {
        startScope(for: url)
        queue.append(url)
        syncQueueCount()
    }
    
    /// Append multiple URLs to the tail.
    public func queue(urls: [URL]) throws {
        queue.append(contentsOf: urls)
        syncQueueCount()
    }
    
    /// Play the track at `index` without clearing other queued items.
    public func playAt(index: Int) throws {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        try playCurrent()
    }
    
    /// Advance to the next track.
    /// Called by the delegate and UI.
    public func next() throws {
        let nextIndex = currentIndex + 1
        guard queue.indices.contains(nextIndex) else {
            stop()
            return
        }
        currentIndex = nextIndex
        try playCurrent()
    }
    
    /// Go to the previous track.
    public func previous() throws {
        let prevIndex = max(currentIndex - 1, 0)
        guard queue.indices.contains(prevIndex) else { return }
        currentIndex = prevIndex
        try playCurrent()
    }
    
    /// Empty the queue.  Does NOT stop currently playing audio.
    public func clearQueue() {
        stopAllScopes()
        queue.removeAll()
        currentIndex = -1
        syncQueueCount()
        currentArtworkData = nil
    }
    
    /// Reorder the queue by moving items.
    public func moveQueue(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        // Adjust currentIndex if needed (track moved)
        if queue.indices.contains(currentIndex) == false {
            currentIndex = currentIndex >= queue.count ? queue.count - 1 : currentIndex
        }
    }
    
    /// Replace the queue with new URLs and start playing the first one.
    public func playQueue(urls: [URL]) throws {
        clearQueue()
        queue.append(contentsOf: urls)
        syncQueueCount()
        guard !queue.isEmpty else { return }
        currentIndex = 0
        try playCurrent()
    }
    
    /// Report an error from the UI layer (e.g. file access failure).
    public func reportError(_ message: String) {
        state = .error(message)
    }
    
    /// Whether the engine is running.
    public var isRunning: Bool {
        player.engineIsRunning
    }
    
    /// Refresh currentTime from the player (called by timer).
    public func refreshTime() {
        if let ct = player.currentTime {
            currentTime = ct
        }
    }
    
    // MARK: - Private
    
    /// Play the track at `queue[currentIndex]` by calling `player.play(_:)`.
    /// This is the ONLY place where `player.play(_:)` is called for queue advancement.
    private func playCurrent() throws {
        guard queue.indices.contains(currentIndex) else {
            stop()
            return
        }
        let url = queue[currentIndex]
        startScope(for: url)
        state = .loading
        currentURL = url
        loadMetadata(for: url)
        try player.play(url)
        state = .playing
    }
    
    private func loadMetadata(for url: URL) {
        guard let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url) else {
            nowPlayingTitle = url.lastPathComponent
            nowPlayingArtist = ""
            totalTime = 0
            currentArtworkData = nil
            return
        }
        nowPlayingTitle = audioFile.metadata.title ?? url.lastPathComponent
        nowPlayingArtist = audioFile.metadata.artist ?? ""
        if let duration = audioFile.properties.duration {
            totalTime = duration
        }
        currentArtworkData = audioFile.metadata.attachedPictures.first?.imageData
    }
    
    private func syncPlaybackState() {
        switch player.playbackState {
        case .playing: state = .playing
        case .paused:  state = .paused
        case .stopped: state = .stopped
        @unknown default: break
        }
    }
    
    private func syncQueueCount() {
        queueCount = queue.count
    }
    
    private func clearNowPlaying() {
        currentTime = 0
        totalTime = 0
        nowPlayingTitle = ""
        nowPlayingArtist = ""
        currentURL = nil
        currentArtworkData = nil
    }
    
    /// Start security-scoped access for the given URL.
    /// Does nothing if the URL is already being accessed.
    private func startScope(for url: URL) {
        guard !scopedURLs.contains(url) else { return }
        _ = url.startAccessingSecurityScopedResource()
        scopedURLs.insert(url)
    }
    
    /// Stop security-scoped access for all tracked URLs.
    private func stopAllScopes() {
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        scopedURLs.removeAll()
    }
}

/// Player-specific errors.
public enum PlayerError: LocalizedError {
    case playbackFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .playbackFailed(let details): return "Playback failed: \(details)"
        }
    }
}

// MARK: - AudioPlayer.Delegate

extension AudioPlayerEngine: AudioPlayer.Delegate {
    
    nonisolated public func audioPlayer(_ audioPlayer: AudioPlayer,
                                         playbackStateChanged newState: AudioPlayer.PlaybackState) {
        Task { @MainActor in
            switch newState {
            case .playing: self.state = .playing
            case .paused:  self.state = .paused
            case .stopped: self.state = .stopped
            @unknown default: break
            }
        }
    }
    
    /// Called when the player has no more audio to play.
    /// We advance to the next manually-managed queue item.
    nonisolated public func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        Task { @MainActor in
            guard self.autoAdvance else { return }
            try? self.next()
        }
    }
    
    nonisolated public func audioPlayer(_ audioPlayer: AudioPlayer,
                                         nowPlayingChanged nowPlaying: (any PCMDecoding)?) {
        // Metadata was already loaded in playCurrent() / loadMetadata(for:)
    }
    
    nonisolated public func audioPlayer(_ audioPlayer: AudioPlayer,
                                         encounteredError error: Error) {
        Task { @MainActor in
            self.state = .error(error.localizedDescription)
        }
    }
}
