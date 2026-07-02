import SwiftUI

/// View for disc copy/duplication (source→target).
struct CopyDiscView: View {
    @EnvironmentObject var configManager: ConfigManager
    @StateObject private var engine = CloneEngine()
    @State private var copyMode: CopyMode = .audioCD
    @State private var log: String = ""
    @State private var isBusy = false
    @State private var progress: Double = 0
    @State private var statusMessage = "Gotowy"
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Mode selector
                    Picker("Tryb kopiowania", selection: $copyMode) {
                        ForEach(CopyMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: copyMode) { newMode in
                        engine.copyMode = newMode
                    }
                    
                    // Device configuration
                    GroupBox("Napędy") {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Źródło:")
                                    .frame(width: 60, alignment: .trailing)
                                    .foregroundColor(.secondary)
                                TextField("IOService:/.../source", text: $engine.sourceDevice)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                Button(action: { engine.sourceDevice = configManager.lastDeviceAddress }) {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                                .help("Użyj ostatniego urządzenia")
                            }
                            
                            HStack {
                                Text("Cel:")
                                    .frame(width: 60, alignment: .trailing)
                                    .foregroundColor(.secondary)
                                TextField("IOService:/.../target", text: $engine.targetDevice)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                Button(action: { engine.targetDevice = configManager.lastDeviceAddress }) {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.borderless)
                                .help("Użyj ostatniego urządzenia")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Options
                    GroupBox("Opcje") {
                        VStack(spacing: 6) {
                            HStack {
                                Toggle("On-the-fly", isOn: $engine.onTheFly)
                                    .disabled(copyMode != .audioCD)
                                Spacer()
                                Toggle("CD-TEXT", isOn: $engine.preserveCDTEXT)
                                Spacer()
                                Toggle("Symuluj", isOn: $engine.simulate)
                            }
                            .font(.caption)
                            
                            if !engine.onTheFly {
                                HStack {
                                    Text("Bufor:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Slider(value: Binding(get: { Double(engine.bufferSize) }, set: { engine.bufferSize = Int($0) }), in: 4...256, step: 4)
                                    Text("\(engine.bufferSize)s")
                                        .font(.caption.monospacedDigit())
                                        .frame(width: 40)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: readDisc) {
                            Label("Odczytaj", systemImage: "opticaldiscdrive")
                        }
                        .disabled(isBusy || engine.sourceDevice.isEmpty)
                        
                        Button(action: writeDisc) {
                            Label("Nagraj", systemImage: "burn")
                        }
                        .disabled(isBusy || engine.targetDevice.isEmpty)
                        
                        Button(action: fullCopy) {
                            Label("Kopiuj", systemImage: "rectangle.on.rectangle")
                        }
                        .disabled(isBusy || engine.sourceDevice.isEmpty || engine.targetDevice.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.small)
                    
                    // Progress
                    if isBusy || progress > 0 {
                        ProgressView(statusMessage, value: progress, total: 1.0)
                            .padding(.horizontal)
                    }
                    
                    // Status
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            // Log
            Divider()
            ScrollView {
                Text(log.isEmpty ? "Gotowy" : log)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(height: 100)
            .background(Color(NSColor.textBackgroundColor))
        }
    }
    
    // MARK: - Actions
    
    private func readDisc() {
        isBusy = true
        statusMessage = "Odczytuję płytę źródłową..."
        progress = 0
        log += "\n▶ Odczyt..."
        
        let path = engine.temporaryImagePath()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let cmd = try engine.generateReadCommand(intermediateFile: path)
                let result = try shell(cmd)
                DispatchQueue.main.async {
                    log += "\n✅ Odczytano: \(path)"
                    statusMessage = "Odczyt zakończony"
                    isBusy = false
                    progress = 1.0
                }
            } catch {
                DispatchQueue.main.async {
                    log += "\n❌ Błąd: \(error.localizedDescription)"
                    statusMessage = "Błąd odczytu"
                    isBusy = false
                }
            }
        }
    }
    
    private func writeDisc() {
        isBusy = true
        statusMessage = "Nagrywam..."
        progress = 0
        log += "\n▶ Nagrywanie..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let path = engine.temporaryImagePath()
                let cmd = try engine.generateWriteCommand(tocFile: path)
                let result = try shell(cmd)
                DispatchQueue.main.async {
                    log += "\n✅ Nagrano"
                    statusMessage = "Nagrywanie zakończone"
                    isBusy = false
                    progress = 1.0
                }
            } catch {
                DispatchQueue.main.async {
                    log += "\n❌ Błąd: \(error.localizedDescription)"
                    statusMessage = "Błąd nagrywania"
                    isBusy = false
                }
            }
        }
    }
    
    private func fullCopy() {
        isBusy = true
        statusMessage = "Kopiowanie..."
        progress = 0
        log += "\n▶ Pełne kopiowanie..."
        
        let path = engine.temporaryImagePath()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let pipeline = try engine.generateFullCopyPipeline(intermediateFile: path)
                let result = try shell(pipeline)
                DispatchQueue.main.async {
                    log += "\n✅ Skopiowano"
                    statusMessage = "Kopiowanie zakończone"
                    isBusy = false
                    progress = 1.0
                }
            } catch {
                DispatchQueue.main.async {
                    log += "\n❌ Błąd: \(error.localizedDescription)"
                    statusMessage = "Błąd kopiowania"
                    isBusy = false
                }
            }
        }
    }
    
    @discardableResult
    private func shell(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
