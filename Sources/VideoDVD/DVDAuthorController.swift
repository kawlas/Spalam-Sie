import Foundation

/// Video system detection (NTSC vs PAL).
public enum VideoSystem: String {
    case ntsc = "NTSC"
    case pal = "PAL"
}

/// Controls video DVD authoring: ffmpeg conversion → dvdauthor → growisofs burn.
public class DVDAuthorController {
    public var videoFiles: [(url: URL, duration: TimeInterval)] = []
    public var totalDuration: TimeInterval {
        videoFiles.reduce(0) { $0 + $1.duration }
    }
    
    public init() {}
    
    /// Add a video file to the DVD session.
    public func addVideo(_ url: URL) throws {
        videoFiles.append((url: url, duration: 0))
    }
    
    /// Detect video system (NTSC vs PAL) from file properties.
    /// Uses ffprobe to read the frame rate.
    public func detectVideoSystem(_ url: URL) throws -> VideoSystem {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        process.arguments = [
            "-v", "quiet",
            "-select_streams", "v:0",
            "-show_entries", "stream=r_frame_rate",
            "-of", "csv=p=0",
            url.path
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return .pal // safe default
        }
        
        // ffprobe returns frame rate as fraction like "30000/1001" or "25/1"
        let components = output.split(separator: "/")
        if components.count == 2,
           let num = Double(components[0]),
           let den = Double(components[1]),
           den > 0 {
            let fps = num / den
            // NTSC is ~29.97 fps (30000/1001), PAL is 25 fps
            if abs(fps - 29.97) < 1.0 || abs(fps - 23.976) < 1.0 || abs(fps - 30.0) < 1.0 {
                return .ntsc
            }
        }
        return .pal
    }
    
    /// Generate ffmpeg conversion command.
    public func generateConvertCommand(input: URL, output: URL, system: VideoSystem) throws -> String {
        return "ffmpeg -i \"\(input.path)\" -target \(system == .pal ? "pal-dvd" : "ntsc-dvd") -y \"\(output.path)\""
    }
    
    /// Generate dvdauthor XML configuration.
    public func generateAuthorXML(outputDir: String) throws -> String {
        return """
        <dvdauthor>
          <vmgm />
          <titleset>
            <titles>
              <video format="pal" />
              <pgc>
                <vob file="title.mpg" />
              </pgc>
            </titles>
          </titleset>
        </dvdauthor>
        """
    }
    
    /// Generate growisofs burn command.
    public func generateBurnCommand(dvdDir: URL, devicePath: String, speed: Int) throws -> String {
        return "growisofs -Z \(devicePath) -dvd-video -speed=\(speed) \"\(dvdDir.path)\""
    }
}
