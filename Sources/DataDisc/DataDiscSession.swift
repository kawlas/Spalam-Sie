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

/// Model for a data disc burning session (files, folders, volume label).
public class DataDiscSession: ObservableObject {
    @Published public var files: [URL] = []
    @Published public var volumeLabel: String = "SPALAM_DATA" {
        didSet { if volumeLabel.count > 32 { volumeLabel = String(volumeLabel.prefix(32)) } }
    }
    @Published public var totalFileSize: Int64 = 0
    
    public init() {}
    
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
