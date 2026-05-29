import Foundation

/// Single source of truth for "should onboarding open?". The gate is purely a
/// function of capability status — "any capability not granted" — never "did a
/// manager fail to start." This makes anti-pattern #6 (onboarding only on hard
/// failure) structurally impossible: there is no other predicate to consult.
enum OnboardingGate {
    @MainActor
    static func shouldPresent(for capabilities: [any Capability]) -> Bool {
        capabilities.contains { $0.currentStatus != .granted }
    }
}
