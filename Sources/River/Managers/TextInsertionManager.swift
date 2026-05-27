import Foundation

@MainActor
final class TextInsertionManager {
    private let accessibility: AccessibilityCapability

    init(accessibility: AccessibilityCapability) {
        self.accessibility = accessibility
    }
}
