import AppKit
import SwiftUI

@main
struct RiverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("River", systemImage: "mic") {
            MenuBarContent()
        }

        SwiftUI.Settings {
            SettingsView()
        }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit River") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
