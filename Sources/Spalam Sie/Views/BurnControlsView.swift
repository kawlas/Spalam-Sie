import SwiftUI

struct BurnControlsView: View {
    @EnvironmentObject var session: BurnSession
    @State private var showBurnConfirmation = false
    
    private let speeds = [1, 2, 4, 8, 10, 16, 24]
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Burn Settings")
                .font(.headline)
            
            // Speed selector
            HStack {
                Text("Speed:")
                    .frame(width: 80, alignment: .trailing)
                    .foregroundColor(.secondary)
                Picker("", selection: $session.burnSpeed) {
                    ForEach(speeds, id: \.self) { speed in
                        Text("\(speed)x (\(speed * 176) kB/s)")
                            .tag(speed)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            
            // Options
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $session.burnProof) {
                    Label("BurnProof / JustLink", systemImage: "shield")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                
                Toggle(isOn: $session.simulate) {
                    Label("Simulation mode (no burn)", systemImage: "play.slash")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                
                Toggle(isOn: $session.ejectAfterBurn) {
                    Label("Eject after burn", systemImage: "eject")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            .padding(.leading, 8)
            
            Divider()
            
            // Status / Progress
            statusSection
            
            // Copyable error detail area (appears when there's an error)
            if case .error(let message) = session.state, !message.isEmpty {
                errorDetailView(message: message)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    if session.simulate {
                        session.startBurn()
                    } else {
                        showBurnConfirmation = true
                    }
                }) {
                    Label(session.simulate ? "Simulate Burn" : "Burn CD",
                          systemImage: session.simulate ? "play.slash" : "opticaldiscdrive")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(session.simulate ? .orange : .red)
                .disabled(session.tracks.isEmpty || {
                    if case .burning = session.state { return true }
                    return false
                }())
                
                Button(action: { session.cancelBurn() }) {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!isBurning)
            }
        }
        .padding()
        .alert("Confirm Real Burn", isPresented: $showBurnConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Burn Now", role: .destructive) {
                session.startBurn()
            }
        } message: {
            let count = String(session.tracks.count)
            let time = formatTime(session.totalDuration)
            Text("This will actually write to the disc.\n\(count) tracks, \(time) total.")
        }
    }
    
    // MARK: - Copyable Error Detail
    
    @ViewBuilder
    private func errorDetailView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundColor(.red)
                    .imageScale(.small)
                Text("Error Details — select and copy below")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            TextEditor(text: .constant(message))
                .font(.caption.monospaced())
                .foregroundColor(.red)
                .frame(height: 80)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
                .padding(.top, 2)
        }
    }
    private var isBurning: Bool {
        if case .burning = session.state { return true }
        return false
    }
    
    // MARK: - Status Section
    
    @ViewBuilder
    private var statusSection: some View {
        VStack(spacing: 8) {
            switch session.state {
            case .idle:
                idleStatus
            case .loadingTracks:
                loadingStatus
            case .ready:
                readyStatus
            case .burning(let progress, let current, let total):
                burningStatus(progress: progress, current: current, total: total)
            case .verifying(let progress):
                verifyingStatus(progress: progress)
            case .completed(let success, let message):
                completedStatus(success: success, message: message)
            case .error(let error):
                errorStatus(message: error)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var idleStatus: some View {
        HStack {
            Image(systemName: "tray")
                .foregroundColor(.secondary)
            Text("Drop audio files to begin")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var loadingStatus: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.7)
            Text("Loading tracks...")
                .font(.caption)
        }
    }
    
    private var readyStatus: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("\(session.tracks.count) tracks ready")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Total time estimate
            let totalSize = session.tracks.reduce(0) { $0 + $1.fileSize }
            let estMinutes = Int(totalSize / 1024 / 1024 / 10) // Rough: ~10 MB/min at 4x
            if estMinutes > 0 {
                Text("~\(estMinutes) min")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func burningStatus(progress: Double, current: Int, total: Int) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "opticaldiscdrive")
                    .symbolEffect(.variableColor.iterative)
                Text("Burning... Track \(current) of \(total)")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            ProgressView(value: max(0.01, progress)) {
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func verifyingStatus(progress: Double) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Verifying...")
                    .font(.caption)
            }
            
            ProgressView(value: progress)
        }
    }
    
    private func completedStatus(success: Bool, message: String) -> some View {
        HStack {
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(success ? .green : .yellow)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Clear") {
                session.clearTracks()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.accentColor)
        }
    }
    
    private func errorStatus(message: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundColor(.red)
                Text("Error")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
            }
            
            Text(message)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            
            Button("Try Again") {
                session.startBurn()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
