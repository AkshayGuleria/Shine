import CoreGraphics
import Foundation

/// Watches for Esc held ≥ 2 seconds and fires abortHandler.
/// Uses a DispatchWorkItem: arm on keyDown, cancel on keyUp.
final class AbortGuard {
    var abortHandler: (() -> Void)?

    private static let holdThreshold: TimeInterval = 2.0
    private var pendingAbort: DispatchWorkItem?

    func shouldPassThrough(event: CGEvent, type: CGEventType) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isEsc = (keyCode == 53)  // kVK_Escape = 53

        switch type {
        case .keyDown where isEsc:
            if pendingAbort == nil {
                let work = DispatchWorkItem { [weak self] in
                    self?.pendingAbort = nil
                    self?.abortHandler?()
                }
                pendingAbort = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdThreshold, execute: work)
            }
            return true

        case .keyUp where isEsc:
            pendingAbort?.cancel()
            pendingAbort = nil
            return true

        default:
            return false
        }
    }
}
