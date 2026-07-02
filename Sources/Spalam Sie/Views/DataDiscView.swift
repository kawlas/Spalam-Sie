import SwiftUI
import UniformTypeIdentifiers

/// View for data disc burning (files, folders, ISO options).
struct DataDiscView: View {
    @StateObject private var session = DataDiscSession()
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var burnSession: BurnSession
    
    @State private var isTargeted = false
    @State private var devicePath: String = ""
    @State private var speed: Int = 4
    @State private var simulate: Bool = false
    @State private var ejectAfterBurn: Bool = true
    @State private var stagingDir: URL?
    
    private var isBusy: Bool {
        if case .buildingISO = session.burnState { return true }
        if case .burning = session.burnState { return true }
        return false
    }
    
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
            
            // MARK: - Burn Controls
            
            VStack(spacing: 12) {
                // Device path
                HStack {
                    Text("Urządzenie:")
                        .foregroundColor(.secondary)
                    TextField("Device IOKit path", text: $devicePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                }
                
                // Burn settings row
                HStack(spacing: 16) {
                    HStack {
                        Text("Prędkość:")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Picker("", selection: $speed) {
                            Text("1×").tag(1)
                            Text("2×").tag(2)
                            Text("4×").tag(4)
                            Text("8×").tag(8)
                            Text("16×").tag(16)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                    
                    Toggle("Symulacja", isOn: $simulate)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    
                    Toggle("Eject", isOn: $ejectAfterBurn)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button("Wypal płytę danych") {
                        performBurn(simulate: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(session.files.isEmpty || isBusy)
                    
                    Button("Symuluj") {
                        performBurn(simulate: true)
                    }
                    .buttonStyle(.bordered)
                    .disabled(session.files.isEmpty || isBusy)
                    
                    Button("Anuluj") {
                        session.cancelBurn()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isBusy)
                }
                
                // Progress
                Group {
                    switch session.burnState {
                    case .idle:
                        EmptyView()
                    case .buildingISO:
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Budowanie ISO…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    case .burning(let progress):
                        VStack(spacing: 4) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(.red)
                            Text("Wypalanie: \(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    case .completed(let success, let message):
                        HStack(spacing: 6) {
                            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(success ? .green : .orange)
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    case .error(let message):
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                // Log
                if !session.burnLog.isEmpty {
                    ScrollView {
                        Text(session.burnLog)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 80)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .onAppear {
            devicePath = burnSession.deviceAddress
        }
        .onChange(of: session.burnState) { newState in
            // Clean up staging directory on completion or error
            if let dir = stagingDir {
                switch newState {
                case .completed, .error:
                    try? FileManager.default.removeItem(at: dir)
                    stagingDir = nil
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func buildStagingDir() throws -> URL {
        try session.buildStagingDirectory()
    }
    
    private func performBurn(simulate: Bool) {
        guard !session.files.isEmpty else { return }
        do {
            let staging = try buildStagingDir()
            stagingDir = staging
            session.performDataBurn(sourcePath: staging.path,
                                    devicePath: devicePath,
                                    simulate: simulate,
                                    speed: speed,
                                    ejectAfterBurn: ejectAfterBurn)
        } catch {
            print("Staging error: \(error)")
        }
    }
    
    // MARK: - Drop Handling
    
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
