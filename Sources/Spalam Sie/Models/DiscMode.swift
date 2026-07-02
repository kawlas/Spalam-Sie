import Foundation

/// Application modes for the main window segmented control.
public enum DiscMode: String, CaseIterable, Identifiable {
    case audio = "Audio CD"
    case data = "Data Disc"
    case copy = "Copy Disc"
    case video = "Video DVD"
    case player = "Player"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .audio: return "music.note.list"
        case .data:  return "externaldrive"
        case .copy:  return "rectangle.on.rectangle"
        case .video: return "film"
        case .player: return "play.circle"
        }
    }
}
