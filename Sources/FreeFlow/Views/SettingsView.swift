import os
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.activationKeyCode.name)
    private var activationKeyCode: Int = Settings.activationKeyCode.defaultValue
    @AppStorage(Settings.activationMode.name)
    private var activationMode: ActivationMode = Settings.activationMode.defaultValue
    @AppStorage(Settings.launchAtLogin.name)
    private var launchAtLogin: Bool = Settings.launchAtLogin.defaultValue
    @AppStorage(Settings.playFeedbackSounds.name)
    private var playFeedbackSounds: Bool = Settings.playFeedbackSounds.defaultValue
    @AppStorage(Settings.pauseMediaWhileDictating.name)
    private var pauseMediaWhileDictating: Bool = Settings.pauseMediaWhileDictating.defaultValue
    @AppStorage(Settings.selectedModel.name)
    private var selectedModel: String = Settings.selectedModel.defaultValue

    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "app")

    var body: some View {
        Form {
            activationSection
            transcriptionSection
            generalSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 556)
    }

    private var activationSection: some View {
        Section("Activation") {
            Picker("Activation Key", selection: $activationKeyCode) {
                ForEach(ActivationKeyOption.all) { option in
                    Text(option.label).tag(option.keyCode)
                }
            }
            Picker("Activation Mode", selection: $activationMode) {
                ForEach(ActivationMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Text(activationMode.description)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let warning = ActivationKeyOption.capsLockHoldWarning(keyCode: activationKeyCode, mode: activationMode) {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var transcriptionSection: some View {
        Section("Transcription") {
            Picker("Model", selection: $selectedModel) {
                ForEach(Constants.curatedModels) { model in
                    Text(model.label).tag(model.name)
                }
            }
            if let hint = Constants.curatedModels.first(where: { $0.name == selectedModel })?.hint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            // Switching keeps the previous model cached (planning 0021 disk-footprint
            // decision: fast switch-back over reclaiming ~240–630 MB; the Homebrew cask
            // `zap` clears the whole cache dir, so there's no in-app cleanup UI).
            Text("Changing the model downloads it the first time and briefly shows a loading status in the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    updateLaunchAtLogin(enabled)
                }
            Toggle("Sound effects", isOn: $playFeedbackSounds)
            Toggle("Pause media while dictating", isOn: $pauseMediaWhileDictating)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            logger.info("Launch at login \(enabled ? "registered" : "unregistered", privacy: .public)")
        } catch {
            logger.error("Launch at login update failed: \(LogRedaction.redactUserPaths(error.localizedDescription), privacy: .public)")
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
