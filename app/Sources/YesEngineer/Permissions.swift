import ApplicationServices
import Foundation

enum Permissions {
    private static var lastPromptAt = Date.distantPast

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibility(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    @discardableResult
    static func requestAccessibilityIfNeeded(minPromptInterval: TimeInterval = 60) -> Bool {
        if isAccessibilityTrusted { return true }

        let now = Date()
        guard now.timeIntervalSince(lastPromptAt) >= minPromptInterval else {
            return false
        }
        lastPromptAt = now
        return requestAccessibility(prompt: true)
    }
}
