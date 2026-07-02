import Foundation
import SwiftUI

/// Persistent configuration manager for Spalam Sie.
/// Uses @AppStorage for automatic UserDefaults persistence + SwiftUI reactivity.
@MainActor
public class ConfigManager: ObservableObject {
    public static let shared = ConfigManager()
    
    // MARK: - Published Settings
    
    /// Default burn speed (1x-24x, default: 4x for USB safety)
    @Published public var defaultBurnSpeed: Int {
        didSet { UserDefaults.standard.set(defaultBurnSpeed, forKey: "defaultBurnSpeed") }
    }
    
    /// BurnProof/JustLink enabled by default
    @Published public var burnProofEnabled: Bool {
        didSet { UserDefaults.standard.set(burnProofEnabled, forKey: "burnProofEnabled") }
    }
    
    /// Eject disc automatically after successful burn
    @Published public var ejectAfterBurn: Bool {
        didSet { UserDefaults.standard.set(ejectAfterBurn, forKey: "ejectAfterBurn") }
    }
    
    /// Show simulation mode by default
    @Published public var defaultSimulate: Bool {
        didSet { UserDefaults.standard.set(defaultSimulate, forKey: "defaultSimulate") }
    }
    
    /// Preferred audio format for source files
    @Published public var preferredAudioFormat: String {
        didSet { UserDefaults.standard.set(preferredAudioFormat, forKey: "preferredAudioFormat") }
    }
    
    /// Path to cdrdao executable (auto-detected)
    @Published public var cdrdaoPath: String {
        didSet { UserDefaults.standard.set(cdrdaoPath, forKey: "cdrdaoPath") }
    }
    
    /// Path to cdrecord executable (auto-detected)
    @Published public var cdrecordPath: String {
        didSet { UserDefaults.standard.set(cdrecordPath, forKey: "cdrecordPath") }
    }
    
    /// Path to ffmpeg executable (auto-detected)
    @Published public var ffmpegPath: String {
        didSet { UserDefaults.standard.set(ffmpegPath, forKey: "ffmpegPath") }
    }
    
    /// Last used device address (for quick reconnection)
    @Published public var lastDeviceAddress: String {
        didSet { UserDefaults.standard.set(lastDeviceAddress, forKey: "lastDeviceAddress") }
    }
    
    /// Whether to show track number in title
    @Published public var showTrackNumbers: Bool {
        didSet { UserDefaults.standard.set(showTrackNumbers, forKey: "showTrackNumbers") }
    }
    
    // MARK: - Initialization
    
    private init() {
        let defaults = UserDefaults.standard
        
        self.defaultBurnSpeed = defaults.object(forKey: "defaultBurnSpeed") as? Int ?? 4
        self.burnProofEnabled = defaults.object(forKey: "burnProofEnabled") as? Bool ?? true
        self.ejectAfterBurn = defaults.object(forKey: "ejectAfterBurn") as? Bool ?? false
        self.defaultSimulate = defaults.object(forKey: "defaultSimulate") as? Bool ?? false
        self.preferredAudioFormat = defaults.string(forKey: "preferredAudioFormat") ?? "auto"
        self.cdrdaoPath = defaults.string(forKey: "cdrdaoPath") ?? "/opt/homebrew/bin/cdrdao"
        self.cdrecordPath = defaults.string(forKey: "cdrecordPath") ?? "/opt/homebrew/bin/cdrecord"
        self.ffmpegPath = defaults.string(forKey: "ffmpegPath") ?? "/opt/homebrew/bin/ffmpeg"
        self.lastDeviceAddress = defaults.string(forKey: "lastDeviceAddress") ?? ""
        self.showTrackNumbers = defaults.object(forKey: "showTrackNumbers") as? Bool ?? true
    }
    
    // MARK: - Convenience
    
    /// Apply config values to a BurnSession
    public func apply(to session: BurnSession) {
        session.burnSpeed = defaultBurnSpeed
        session.burnProof = burnProofEnabled
        session.ejectAfterBurn = ejectAfterBurn
        session.simulate = defaultSimulate
    }
    
    /// Save current session values to config
    public func save(from session: BurnSession) {
        defaultBurnSpeed = session.burnSpeed
        burnProofEnabled = session.burnProof
        ejectAfterBurn = session.ejectAfterBurn
        defaultSimulate = session.simulate
        lastDeviceAddress = session.deviceAddress
    }
    
    /// Reset all settings to defaults
    public func resetToDefaults() {
        defaultBurnSpeed = 4
        burnProofEnabled = true
        ejectAfterBurn = false
        defaultSimulate = false
        preferredAudioFormat = "auto"
        showTrackNumbers = true
        // Keep tool paths as they are (auto-detected)
    }
    
    /// Detect tool paths on the system
    public func detectTools() -> (cdrdao: Bool, cdrecord: Bool, ffmpeg: Bool, flac: Bool, lame: Bool) {
        let fm = FileManager.default
        return (
            cdrdao: fm.isExecutableFile(atPath: cdrdaoPath),
            cdrecord: fm.isExecutableFile(atPath: cdrecordPath),
            ffmpeg: fm.isExecutableFile(atPath: ffmpegPath),
            flac: fm.isExecutableFile(atPath: "/opt/homebrew/bin/flac"),
            lame: fm.isExecutableFile(atPath: "/opt/homebrew/bin/lame")
        )
    }
}
