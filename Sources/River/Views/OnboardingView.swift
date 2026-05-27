import SwiftUI

struct OnboardingView: View {
    let capabilities: [any Capability]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to River")
                .font(.title)
            Text("Permissions setup will live here.")
                .foregroundStyle(.secondary)

            Divider()

            ForEach(Array(capabilities.enumerated()), id: \.offset) { _, capability in
                HStack {
                    Text(capability.displayName)
                    Spacer()
                    Text(statusLabel(for: capability.currentStatus))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func statusLabel(for status: CapabilityStatus) -> String {
        switch status {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .unknown: return "Unknown"
        }
    }
}
