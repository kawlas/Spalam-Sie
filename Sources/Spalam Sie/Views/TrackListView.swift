import SwiftUI

struct TrackListView: View {
    @EnvironmentObject var session: BurnSession
    @State private var selectedTracks = Set<UUID>()
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Tracks")
                    .font(.headline)
                Spacer()
                Text("\(session.tracks.count) tracks")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(action: addFiles) {
                    Image(systemName: "plus")
                }
                .help("Add files")
                Button(action: {
                    session.removeTracks(at: selectedTrackIndices)
                }) {
                    Image(systemName: "minus")
                }
                .disabled(selectedTracks.isEmpty)
                .help("Remove selected")
                Button(action: { session.clearTracks() }) {
                    Image(systemName: "trash")
                }
                .disabled(session.tracks.isEmpty)
                .help("Clear all")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Track list
            List(selection: $selectedTracks) {
                TrackHeader()
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                
                ForEach(session.tracks) { track in
                    TrackRowView(track: track)
                        .tag(track.id)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
                .onMove { source, dest in
                    session.moveTracks(from: source, to: dest)
                }
                .onDelete { indexSet in
                    session.removeTracks(at: indexSet)
                }
            }
            .listStyle(.plain)
            .alternatingRowBackgrounds()
        }
    }
    
    private var selectedTrackIndices: IndexSet {
        var indices = IndexSet()
        for (index, track) in session.tracks.enumerated() {
            if selectedTracks.contains(track.id) {
                indices.insert(index)
            }
        }
        return indices
    }
    
    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [
            .wav,
            .init(filenameExtension: "flac") ?? .data,
            .init(filenameExtension: "mp3") ?? .data,
            .init(filenameExtension: "aiff") ?? .data,
            .init(filenameExtension: "m4a") ?? .data,
            .init(filenameExtension: "cue") ?? .data,
        ]
        
        guard panel.runModal() == .OK else { return }
        session.addFiles(panel.urls)
    }
}

// MARK: - Track Header

struct TrackHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("#")
                .frame(width: 28, alignment: .trailing)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Title")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Artist")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text("Format")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .center)
            Text("Size")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.separatorColor).opacity(0.1))
    }
}

// MARK: - Track Row

struct TrackRowView: View {
    @EnvironmentObject var session: BurnSession
    let track: BurnTrack
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    
    var body: some View {
        HStack(spacing: 8) {
            // Track number
            Text("\(track.trackNumber)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .trailing)
            
            // Title
            if isEditing {
                TextField("Track title", text: $editedTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onSubmit {
                        session.updateTrackTitle(id: track.id, newTitle: editedTitle)
                        isEditing = false
                    }
                    .onExitCommand {
                        isEditing = false
                    }
            } else {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) {
                        editedTitle = track.title
                        isEditing = true
                    }
            }
            
            // Artist
            Text(track.performer ?? "-")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
            
            // Format badge
            Text(track.format.rawValue)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(formatColor(track.format))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(formatColor(track.format).opacity(0.1))
                )
                .frame(width: 50, alignment: .center)
            
            // Size
            Text(formattedSize(track.fileSize))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private func formatColor(_ format: AudioFormat) -> Color {
        switch format {
        case .wav: return .blue
        case .flac: return .purple
        case .mp3: return .orange
        case .aiff: return .teal
        case .m4a: return .pink
        case .cue: return .gray
        case .unknown: return .secondary
        }
    }
    
    private func formattedSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}
