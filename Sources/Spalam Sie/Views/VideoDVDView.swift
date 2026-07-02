import SwiftUI

/// View for video DVD authoring and burning.
struct VideoDVDView: View {
    @EnvironmentObject var configManager: ConfigManager
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "film")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Video DVD")
                .font(.title2)
            
            Text("Tworzenie płyt DVD-Video z plików wideo")
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                Label("ffmpeg → MPEG-2", systemImage: "1.circle")
                Label("dvdauthor → VIDEO_TS", systemImage: "2.circle")
                Label("growisofs → DVD", systemImage: "3.circle")
            }
            .foregroundColor(.secondary)
            
            Text("Wkrótce dostępne — implementacja w toku")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
    }
}
