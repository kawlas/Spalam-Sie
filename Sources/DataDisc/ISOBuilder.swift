import Foundation

/// Builds ISO 9660 filesystem images using mkisofs.
/// Default configuration: Joliet + Rock Ridge enabled for cross-platform compatibility.
public class ISOBuilder {
    /// Default binary path for mkisofs.
    public static let mkisofsBinaryPath = "/opt/homebrew/bin/mkisofs"
    
    public var volumeLabel: String = "SPALAM_DATA" {
        didSet { if volumeLabel.count > 32 { volumeLabel = String(volumeLabel.prefix(32)) } }
    }
    public var joliet: Bool = true
    public var rockRidge: Bool = true
    public var hybridHFS: Bool = false
    public var outputURL: URL?
    public private(set) var files: [URL] = []
    private let mkisofsPath: String
    
    public init(mkisofsPath: String = "/opt/homebrew/bin/mkisofs") {
        self.mkisofsPath = mkisofsPath
    }
    
    /// Add a single file to the ISO session.
    public func addFile(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        files.append(url)
    }
    
    /// Recursively add all files in a directory.
    public func addDirectory(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return }
        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                files.append(fileURL)
            }
        }
    }
    
    /// Remove file at index.
    public func removeFile(at index: Int) {
        guard index >= 0, index < files.count else { return }
        files.remove(at: index)
    }
    
    /// Clear all files.
    public func clearAll() {
        files.removeAll()
    }
    
    /// Dry run: calculate ISO size without writing.
    /// - Returns: Size in 2048-byte sectors.
    public func dryRun() throws -> Int {
        let cmd = try generateCommand(dryRun: true)
        let output = try shell(cmd)
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
    
    /// Generate the ISO image file.
    public func generateISO() throws {
        guard outputURL != nil else { return }
        let cmd = try generateCommand(dryRun: false)
        try shell(cmd)
    }
    
    /// Generate the mkisofs command string.
    public func generateCommand(dryRun: Bool) throws -> String {
        var args: [String] = []
        if dryRun {
            args.append("-print-size")
        } else {
            args += ["-o", outputURL?.path ?? "/tmp/output.iso"]
        }
        args += ["-V", volumeLabel]
        if joliet { args.append("-J") }
        if rockRidge { args.append("-R") }
        if hybridHFS { args.append("-hfs") }
        for file in files {
            args.append(file.path)
        }
        return "\(mkisofsPath) " + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
    }
    
    @discardableResult
    private func shell(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
