import AppKit
import SwiftUI

@main
struct FreeFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                appState: appDelegate.appState,
                cancel: { appDelegate.session.handleCancel() },
                copyLastTranscript: { appDelegate.session.copyLastTranscript() },
                openPermissions: { appDelegate.onboarding.forcePresent() },
                checkForUpdates: { appDelegate.updater.checkForUpdates() }
            )
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
    /// Writes the last retained transcript to the clipboard (planning 0019).
    /// User-initiated write — the automated cycle never touches the clipboard.
    let copyLastTranscript: () -> Void
    /// Re-opens the permissions window on demand (planning 0012). Wired to
    /// `OnboardingCoordinator.forcePresent()` so users can inspect or refresh
    /// their grants at any time without relaunching.
    let openPermissions: () -> Void
    /// Triggers a user-initiated Sparkle update check (planning 0009). Wired to
    /// `UpdaterManager.checkForUpdates()`; automatic background checks run on
    /// Sparkle's own schedule after the first-launch consent prompt.
    let checkForUpdates: () -> Void
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
        // Disabled before the first cycle; enabled after any successful transcription
        // (including when paste fails, which is exactly the recovery case).
        Button("Copy Last Transcription", action: copyLastTranscript)
            .disabled(!appState.hasLastTranscript)
        Divider()
        Button("Check for Updates…", action: checkForUpdates)
        Button("Permissions…", action: openPermissions)
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
