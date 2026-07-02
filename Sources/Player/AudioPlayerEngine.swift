import Foundation
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
/// Supports gapless playback, all formats (FLAC, ALAC, WAV, AIFF, MP3, AAC, OGG, Opus, APE, DSD),
/// and bit-perfect output via CoreAudio HAL exclusive mode.
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
    
    /// Auto-advance to next track when current finishes.
    public var autoAdvance: Bool = true
    
    private var queue: [URL] = []
    private var currentIndex: Int = -1
    
    override public init() {
        self.player = AudioPlayer()
        super.init()
        self.player.delegate = self
    }
    
    // MARK: - Playback Control
    
    /// Play a single audio file immediately.
    public func play(url: URL) throws {
        state = .loading
        queue = [url]
        currentIndex = 0
        currentURL = url
        loadMetadata(for: url)
        
        try player.play(url)
        state = .playing
    }
    
    /// Start or resume the engine (AudioPlayer manages it internally, but this is needed for API compat).
    public func start() throws {
        // AudioPlayer manages engine lifecycle internally
    }
    
    /// Stop playback and clear queue.
    public func stop() {
        player.stop()
        queue.removeAll()
        currentIndex = -1
        currentTime = 0
        totalTime = 0
        nowPlayingTitle = ""
        nowPlayingArtist = ""
        currentURL = nil
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
    
    /// Seek to a specific time position.
    public func seek(to time: TimeInterval) {
        player.seek(time: time)
    }
    
    /// Seek to a fractional position (0.0 - 1.0).
    public func seek(position: Double) {
        player.seek(position: position)
    }
    
    // MARK: - Queue Management
    
    /// Queue a track for gapless playback.
    public func queue(url: URL) throws {
        queue.append(url)
        queueCount = queue.count
        try player.enqueue(url)
    }
    
    /// Queue multiple URLs.
    public func queue(urls: [URL]) throws {
        for url in urls {
            try queue(url: url)
        }
    }
    
    /// Play a specific index from the queue.
    public func playAt(index: Int) throws {
        guard index >= 0, index < queue.count else { return }
        let url = queue[index]
        currentIndex = index
        try play(url: url)
    }
    
    /// Skip to next track.
    public func next() throws {
        let nextIndex = currentIndex + 1
        guard nextIndex < queue.count else {
            stop()
            return
        }
        try playAt(index: nextIndex)
    }
    
    /// Go to previous track.
    public func previous() throws {
        let prevIndex = max(currentIndex - 1, 0)
        try playAt(index: prevIndex)
    }
    
    /// Clear the queue.
    public func clearQueue() {
        player.clearQueue()
        queue.removeAll()
        queueCount = 0
        currentIndex = -1
    }
    
    /// Replace queue with new URLs and start playing.
    public func playQueue(urls: [URL]) throws {
        clearQueue()
        for url in urls {
            queue.append(url)
        }
        queueCount = queue.count
        try playAt(index: 0)
    }
    
    /// Whether the engine is running.
    public var isRunning: Bool {
        player.engineIsRunning
    }
    
    // MARK: - Private
    
    private func loadMetadata(for url: URL) {
        guard let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url) else {
            nowPlayingTitle = url.lastPathComponent
            nowPlayingArtist = ""
            totalTime = 0
            return
        }
        nowPlayingTitle = audioFile.metadata.title ?? url.lastPathComponent
        nowPlayingArtist = audioFile.metadata.artist ?? ""
        if let duration = audioFile.properties.duration {
            totalTime = duration
        }
    }
    
    private func syncPlaybackState() {
        switch player.playbackState {
        case .playing: state = .playing
        case .paused:  state = .paused
        case .stopped: state = .stopped
        @unknown default: break
        }
    }
    
    /// Update current time from player, called periodically.
    public func refreshTime() {
        if let ct = player.currentTime {
            currentTime = ct
        }
        if player.isPlaying {
            // Schedule next refresh
        }
    }
}

/// Player-specific errors.
public enum PlayerError: LocalizedError {
    case enqueueFailed
    case playbackFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .enqueueFailed: return "Could not enqueue track"
        case .playbackFailed(let details): return "Playback failed: \(details)"
        }
    }
}

// MARK: - AudioPlayer.Delegate

extension AudioPlayerEngine: AudioPlayer.Delegate {
    
    nonisolated public func audioPlayer(_ audioPlayer: AudioPlayer, playbackStateChanged newState: AudioPlayer.PlaybackState) {
        Task { @MainActor in
            switch newState {
            case .playing:
                self.state = .playing
            case .paused:
                self.state = .paused
            case .stopped:
                self.state = .stopped
            @unknown default:
                break
            }
        }
    }
    
    nonisolated public func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        Task { @MainActor in
            if self.autoAdvance {
                try? self.next()
            }
        }
    }
    
    nonisolated public func audioPlayer(_ audioPlayer: AudioPlayer, nowPlayingChanged nowPlaying: (any PCMDecoding)?) {
        // A new track started playing — metadata was already loaded by play(url:)
    }
    
    nonisolated public func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        Task { @MainActor in
            self.state = .error(error.localizedDescription)
        }
    }
}
