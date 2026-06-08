import os
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.activationKeyCode.name)
    private var activationKeyCode: Int = Settings.activationKeyCode.defaultValue
    @AppStorage(Settings.launchAtLogin.name)
    private var launchAtLogin: Bool = Settings.launchAtLogin.defaultValue

    @State private var dictionary: DictionaryModel
    @State private var newTerm: String = ""

    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "app")

    init(settings: SettingsStore) {
        _dictionary = State(initialValue: DictionaryModel(store: settings))
    }

    var body: some View {
        Form {
            activationSection
            dictionarySection
            generalSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
    }

    private var activationSection: some View {
        Section("Activation") {
            Picker("Activation Key", selection: $activationKeyCode) {
                ForEach(ActivationKeyOption.all) { option in
                    Text(option.label).tag(option.keyCode)
                }
            }
            if let warning = ActivationKeyOption.capsLockHoldWarning(keyCode: activationKeyCode) {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dictionarySection: some View {
        Section("Custom Dictionary") {
            if dictionary.terms.isEmpty {
                Text("No terms yet. Add proper nouns or jargon Whisper tends to mishear.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(dictionary.terms, id: \.self) { term in
                Text(term)
            }
            .onDelete { dictionary.delete(at: $0) }
            HStack {
                TextField("Add a term", text: $newTerm)
                    .onSubmit(addTerm)
                Button("Add", action: addTerm)
                    .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    updateLaunchAtLogin(enabled)
                }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
        }
    }

    private func addTerm() {
        dictionary.add(newTerm)
        newTerm = ""
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
