import SwiftUI
import AppKit

// MARK: - Notifications

extension Notification.Name {
    static let showHelp = Notification.Name("com.spalamsie.showHelp")
}

// MARK: - Single-instance enforcement

private let spalamBundleID = "com.spalamsie.burner"

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppDelegate.ensureSingleInstance()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @MainActor static func ensureSingleInstance() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleId = Bundle.main.bundleIdentifier ?? spalamBundleID

        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        let others = running.filter { $0.processIdentifier != currentPID }

        if !others.isEmpty {
            if let existing = others.first {
                if #available(macOS 14, *) {
                    existing.activate()
                } else {
                    existing.activate(options: [.activateIgnoringOtherApps])
                }
            }
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - App entry point

@main
struct Spalam_SieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var session = BurnSession()
    @StateObject private var config = ConfigManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(config)
                .frame(minWidth: 700, minHeight: 500)
                .onAppear {
                    config.apply(to: session)
                    session.refreshDevice()
                    session.appendLog("Spalam Sie started")
                    
                    let tools = config.detectTools()
                    session.appendLog("Tools: cdrdao=\(tools.cdrdao ? "✓" : "✗") cdrecord=\(tools.cdrecord ? "✓" : "✗") ffmpeg=\(tools.ffmpeg ? "✓" : "✗")")
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .importExport) {
                Button("Add Audio Files...") {
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
                    
                    if panel.runModal() == .OK {
                        session.addFiles(panel.urls)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("Clear All Tracks") {
                    session.clearTracks()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                
                Button("Eject Disc") {
                    Task { @MainActor in
                        session.appendLog("Ejecting disc...")
                        let engine = BurnEngine()
                        do {
                            try engine.eject(iokitPath: session.deviceAddress)
                            session.appendLog("Disc ejected")
                        } catch {
                            session.appendLog("Eject failed: \(error.localizedDescription)")
                        }
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            
            CommandGroup(after: .help) {
                Button("Spalam Sie Help") {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}
