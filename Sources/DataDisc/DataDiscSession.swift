import Foundation
import Combine

/// Disc type for data burning based on total file size.
public enum DataDiscType: String {
    case cdr = "CD-R"
    case dvdr = "DVD±R"
    case bdr = "BD-R"
    
    public var capacityBytes: Int64 {
        switch self {
        case .cdr:  return 737_000_000   // ~700 MB
        case .dvdr: return 4_700_000_000 // ~4.7 GB
        case .bdr:  return 25_000_000_000 // ~25 GB
        }
    }
}

// MARK: - Burn State

/// Current state of a data disc burn operation.
public enum DataBurnState: Equatable {
    case idle
    case buildingISO
    case burning(progress: Double)
    case completed(success: Bool, message: String)
    case error(String)
}

// MARK: - DataBurner Protocol

/// Abstraction over the burn engine for testability.
public protocol DataBurner: AnyObject, Sendable {
    func burnData(config: BurnConfiguration, sourcePath: String, progress: BurnProgressCallback?) throws -> Bool
    func cancel()
}

/// Model for a data disc burning session (files, folders, volume label).
@MainActor
public class DataDiscSession: ObservableObject {
    @Published public var files: [URL] = []
    @Published public var volumeLabel: String = "SPALAM_DATA" {
        didSet { if volumeLabel.count > 32 { volumeLabel = String(volumeLabel.prefix(32)) } }
    }
    @Published public var totalFileSize: Int64 = 0
    @Published public var burnState: DataBurnState = .idle
    @Published public var burnLog: String = ""
    
    private let burner: DataBurner
    private var isCancelledByUser = false
    
    public init(burner: DataBurner = BurnEngine()) {
        self.burner = burner
    }
    
    /// Add a file, updating total size.
    public func addFile(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        files.append(url)
        if let size = attrs[.size] as? Int64 {
            totalFileSize += size
        }
    }
    
    /// Remove file at index.
    public func removeFile(at index: Int) {
        guard index >= 0, index < files.count else { return }
        files.remove(at: index)
        recalculateSize()
    }
    
    /// Clear all files.
    public func clearAll() {
        files.removeAll()
        totalFileSize = 0
    }
    
    /// Recommended disc type based on total size.
    public var recommendedDiscType: DataDiscType {
        if totalFileSize <= DataDiscType.cdr.capacityBytes {
            return .cdr
        } else if totalFileSize <= DataDiscType.dvdr.capacityBytes {
            return .dvdr
        } else {
            return .bdr
        }
    }
    
    // MARK: - Burn orchestration
    
    /// Perform a data burn operation.
    /// - Parameters:
    ///   - sourcePath: Path to the staging directory containing files to burn.
    ///   - devicePath: Device path (IOKit) for the optical drive.
    ///   - simulate: If true, only simulate the burn.
    ///   - speed: Write speed.
    ///   - ejectAfterBurn: If true, eject disc after completion.
    public func performDataBurn(sourcePath: String, devicePath: String, simulate: Bool, speed: Int, ejectAfterBurn: Bool) {
        guard !files.isEmpty else {
            burnState = .error("No files")
            appendLog("❌ No files to burn")
            return
        }
        isCancelledByUser = false
        burnState = .buildingISO
        appendLog("Starting data burn...")
        
        let burner = self.burner
        var config = BurnConfiguration.safeUSB(devicePath: devicePath)
        config.simulate = simulate
        config.speed = speed
        config.ejectAfterBurn = ejectAfterBurn
        config.volumeLabel = self.volumeLabel
        
        Task {
            do {
                let result = try burner.burnData(config: config, sourcePath: sourcePath, progress: { p in
                    Task { @MainActor in
                        guard !self.isCancelledByUser else { return }
                        switch p {
                        case .writingTrack(_, _, let frac):
                            self.burnState = .burning(progress: frac)
                        case .completed:
                            break // handled after return
                        case .error(let e):
                            self.burnState = .error(e.localizedDescription)
                        default:
                            break
                        }
                    }
                })
                await MainActor.run {
                    guard !self.isCancelledByUser else { return }
                    self.burnState = .completed(success: result, message: result ? "Data disc burned" : "Burn returned false")
                    self.appendLog(result ? "✅ Done" : "⚠️ Burn returned false")
                }
            } catch {
                let desc = error.localizedDescription
                await MainActor.run {
                    guard !self.isCancelledByUser else { return }
                    self.burnState = .error(desc)
                    self.appendLog("❌ \(desc)")
                }
            }
        }
    }
    
    /// Cancel the current burn operation.
    public func cancelBurn() {
        isCancelledByUser = true
        burner.cancel()
        burnState = .error("Cancelled by user")
        appendLog("🛑 Cancelled")
    }
    
    // MARK: - Private
    
    /// Append a timestamped message to the burn log.
    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        burnLog += "[\(timestamp)] \(message)\n"
    }
    
    private func recalculateSize() {
        totalFileSize = 0
        for file in files {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? Int64 {
                totalFileSize += size
            }
        }
    }
}
