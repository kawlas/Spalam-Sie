import SwiftUI

/// View for audio playback.
struct PlayerView: View {
    @StateObject private var player = AudioPlayerEngine()
    @State private var isPlaying = false
    @State private var volume: Float = 1.0
    @State private var currentTrack: String = ""
    
    var body: some View {
        VStack(spacing: 24) {
            // Artwork / icon
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 200, height: 200)
                Image(systemName: isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)
            }
            
            // Track info
            VStack(spacing: 4) {
                Text(currentTrack.isEmpty ? "Brak utworu" : currentTrack)
                    .font(.headline)
                    .lineLimit(1)
                Text(player.playlistName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Controls
            HStack(spacing: 32) {
                Button(action: previousTrack) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(!isPlaying)
                
                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                }
                .buttonStyle(.plain)
                
                Button(action: nextTrack) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(!isPlaying)
            }
            
            // Volume
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundColor(.secondary)
                Slider(value: $volume, in: 0...1) { _ in
                    player.volume = volume
                }
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.secondary)
            }
            .frame(width: 250)
        }
        .padding()
        .onAppear {
            try? player.start()
        }
        .onDisappear {
            player.stop()
        }
    }
    
    private func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.resume()
            isPlaying = true
        }
    }
    
    private func nextTrack() {
        // TODO: implement
    }
    
    private func previousTrack() {
        // TODO: implement
    }
}
