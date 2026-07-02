import SwiftUI
import UniformTypeIdentifiers

/// View for data disc burning (files, folders, ISO options).
struct DataDiscView: View {
    @StateObject private var session = DataDiscSession()
    @EnvironmentObject var configManager: ConfigManager
    
    @State private var isTargeted = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Drop zone
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargeted ? Color.blue : Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                .frame(height: 120)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive.badge.plus")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Przeciągnij pliki i foldery tutaj")
                            .foregroundColor(.secondary)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                    handleDrop(providers: providers)
                    return true
                }
            
            // Volume label
            HStack {
                Text("Volume:")
                    .foregroundColor(.secondary)
                TextField("Nazwa płyty", text: $session.volumeLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            
            // File list
            if session.files.isEmpty {
                Spacer()
                Text("Brak plików — przeciągnij pliki powyżej")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(Array(session.files.enumerated()), id: \.offset) { index, url in
                        HStack {
                            Image(systemName: url.hasDirectoryPath ? "folder" : "doc")
                            Text(url.lastPathComponent)
                            Spacer()
                            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                               let size = attrs[.size] as? Int64 {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet.sorted(by: >) {
                            session.removeFile(at: index)
                        }
                    }
                }
                .listStyle(.plain)
            }
            
            // Info bar
            HStack {
                Label("\(session.files.count) plików", systemImage: "doc")
                Spacer()
                Label("\(ByteCountFormatter.string(fromByteCount: session.totalFileSize, countStyle: .file))", systemImage: "arrow.up.doc")
                Spacer()
                Label(session.recommendedDiscType.rawValue, systemImage: "opticaldisc")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
        }
        .padding()
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    do {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                            if isDir.boolValue {
                                try session.addFile(url)
                            } else {
                                try session.addFile(url)
                            }
                        }
                    } catch {
                        print("Error adding file: \(error)")
                    }
                }
            }
        }
    }
}
