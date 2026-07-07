import SwiftUI

/// The recording-indicator HUD's SwiftUI content (planning 0002/0018/0020). Pure
/// presentation: it reads the shared `AppState` and renders the recording/processing
/// variant, the live level meter, any transient error toast, and the live
/// reconfiguration notice. All show/hide *decisions* live in the pure
/// `RecordingIndicatorPresentation`; panel/focus behavior lives in the coordinator.
/// This view is not unit-tested — animation and layout are the documented manual
/// check (planning 0002 AC5).
struct RecordingIndicatorView: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 8) {
            if let toast = appState.toast {
                ToastRow(toast: toast)
            }
            statusRow
            if let notice = appState.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.08))
        )
        .opacity(RecordingIndicatorPresentation.isOnScreen(
            state: appState.state, hasToast: appState.toast != nil) ? 1 : 0)
        .animation(.easeInOut(duration: Constants.hudFadeSeconds), value: appState.state)
        .animation(.easeInOut(duration: Constants.hudFadeSeconds), value: appState.toast)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch RecordingIndicatorPresentation.variant(for: appState.state) {
        case .recording:
            HStack(spacing: 12) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                LevelMeterView(level: appState.inputLevel)
            }
        case .processing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Transcribing…").font(.callout)
            }
        case .idle:
            // Nothing to show when idle; the panel is fading out (or up only for a
            // lingering toast, which the toast row above handles).
            EmptyView()
        }
    }
}

/// The transient error toast row: headline + recovery hint (planning 0018).
private struct ToastRow: View {
    let toast: ErrorToast

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.headline).font(.callout.weight(.semibold))
                Text(toast.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The live input-level meter (planning 0020). Bar count and which bars light come
/// from `Constants` and the pure `LevelMeterPresentation.litBars`; the heights are
/// center-weighted so it reads like a classic meter.
private struct LevelMeterView: View {
    let level: Float

    var body: some View {
        let lit = LevelMeterPresentation.litBars(
            level: level, barCount: Constants.levelMeterBarCount
        )
        HStack(spacing: 3) {
            ForEach(0..<Constants.levelMeterBarCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < lit ? Color.green : Color.secondary.opacity(0.25))
                    .frame(width: 3, height: Self.barHeight(index))
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.08), value: lit)
    }

    private static func barHeight(_ index: Int) -> CGFloat {
        let count = Constants.levelMeterBarCount
        let center = Double(count - 1) / 2
        let distance = abs(Double(index) - center) / center
        return 8 + CGFloat((1 - distance)) * 16
    }
}
