import AppKit
import ApplicationServices

struct PermissionCoordinator {
    func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows system prompt if not yet granted. Call only when user explicitly requests access.
    func requestAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
