import AppKit
import SwiftUI

@main
struct FreeFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(appState: appDelegate.appState) {
                appDelegate.session.handleCancel()
            }
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
            hasError: appState.errorMessage != nil,
            modelLoadState: appState.modelLoadState
        ).systemImage)
    }
}

private struct MenuBarContent: View {
    let appState: AppState
    /// Discards the in-flight recording (planning 0017). The always-available,
    /// discoverable path to cancel — the mouse-free counterpart is the fn-key
    /// gesture in `HotkeyManager`. Both call the same `FreeFlowSession.handleCancel`.
    let cancel: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(MenuBarPresentation.visual(
            state: appState.state,
            hasError: appState.errorMessage != nil,
            modelLoadState: appState.modelLoadState
        ).statusLabel)
        if let errorMessage = appState.errorMessage {
            Text(errorMessage)
        }
        if let notice = appState.notice {
            Text(notice)
        }
        // Only actionable while recording (the session guards it anyway); shown
        // conditionally so it isn't dead UI the rest of the time.
        if appState.state == .recording {
            Divider()
            Button("Cancel Recording", role: .destructive, action: cancel)
                .keyboardShortcut(".")
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
