import AppKit
import SwiftUI

@main
struct FreeFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(appState: appDelegate.appState)
        } label: {
            MenuBarLabel(appState: appDelegate.appState)
        }

        SwiftUI.Settings {
            SettingsView()
        }
    }
}

private struct MenuBarLabel: View {
    let appState: AppState

    var body: some View {
        Image(systemName: MenuBarPresentation.visual(
            state: appState.state,
            hasError: appState.errorMessage != nil
        ).systemImage)
    }
}

private struct MenuBarContent: View {
    let appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(MenuBarPresentation.visual(
            state: appState.state, hasError: appState.errorMessage != nil
        ).statusLabel)
        if let errorMessage = appState.errorMessage {
            Text(errorMessage)
        }
        Divider()
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Free Flow") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
