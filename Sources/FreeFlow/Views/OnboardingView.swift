import SwiftUI

struct OnboardingView: View {
    let capabilities: [any Capability]
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Free Flow")
                    .font(.title2).fontWeight(.semibold)
                Text("Free Flow needs three permissions to hear your voice and paste the transcription at your cursor.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(capabilities.enumerated()), id: \.offset) { _, capability in
                    CapabilityRow(capability: capability)
                }
            }

            Divider()

            HStack {
                Button("Refresh permission status") {
                    Task {
                        for capability in capabilities { await capability.recheck() }
                    }
                }
                Spacer()
                Button("Skip (I've already granted permissions)", action: onSkip)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

private struct CapabilityRow: View {
    let capability: any Capability
    @State private var status: CapabilityStatus

    init(capability: any Capability) {
        self.capability = capability
        _status = State(initialValue: capability.currentStatus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(capability.displayName)
                    .font(.headline)
                Spacer()
                StatusBadge(status: status)
                Button("Grant") {
                    Task { await capability.requestGrant() }
                }
                .disabled(status == .granted)
            }
            if status != .granted, let instructions = capability.setupInstructions {
                Text(instructions)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if status == .unknown && capability.setupInstructions == nil {
                Text("Couldn't confirm the grant. Try the feature, or open System Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onReceive(capability.status) { status = $0 }
    }
}

private struct StatusBadge: View {
    let status: CapabilityStatus

    var body: some View {
        Text(label)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch status {
        case .granted: return "Granted"
        case .denied: return "Not granted"
        case .unknown: return "Couldn't confirm"
        }
    }

    private var color: Color {
        switch status {
        case .granted: return .green
        case .denied: return .red
        case .unknown: return .orange
        }
    }
}
