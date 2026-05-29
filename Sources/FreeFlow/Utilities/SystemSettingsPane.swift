import AppKit
import Foundation

/// Single source of truth for the privacy-pane deep links. Each capability that
/// can't auto-prompt routes through here so the URL strings live in one place.
enum SystemSettingsPane: String {
    case accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    case inputMonitoring = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    case microphone = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"

    @MainActor
    func open() {
        guard let url = URL(string: rawValue) else { return }
        NSWorkspace.shared.open(url)
    }
}
