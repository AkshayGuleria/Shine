import ApplicationServices
import CoreGraphics
import Foundation

enum BlockerError: Error {
    case notAuthorized
    case tapCreateFailed
}

final class InputBlocker {
    var abortHandler: (() -> Void)? {
        get { abortGuard.abortHandler }
        set { abortGuard.abortHandler = newValue }
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let abortGuard = AbortGuard()

    private static let eventMask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue)           |
        (1 << CGEventType.keyUp.rawValue)             |
        (1 << CGEventType.flagsChanged.rawValue)      |
        (1 << CGEventType.mouseMoved.rawValue)        |
        (1 << CGEventType.leftMouseDown.rawValue)     |
        (1 << CGEventType.leftMouseUp.rawValue)       |
        (1 << CGEventType.rightMouseDown.rawValue)    |
        (1 << CGEventType.rightMouseUp.rawValue)      |
        (1 << CGEventType.otherMouseDown.rawValue)    |
        (1 << CGEventType.otherMouseUp.rawValue)      |
        (1 << CGEventType.leftMouseDragged.rawValue)  |
        (1 << CGEventType.rightMouseDragged.rawValue) |
        (1 << CGEventType.otherMouseDragged.rawValue) |
        (1 << CGEventType.scrollWheel.rawValue)       |
        (1 << CGEventType.tabletPointer.rawValue)     |
        (1 << CGEventType.tabletProximity.rawValue)

    func install() throws {
        guard AXIsProcessTrusted() else { throw BlockerError.notAuthorized }

        let userInfo = Unmanaged.passRetained(self).toOpaque()

        let newTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                let me = Unmanaged<InputBlocker>.fromOpaque(refcon!).takeUnretainedValue()
                if me.abortGuard.shouldPassThrough(event: event, type: type) {
                    return Unmanaged.passUnretained(event)
                }
                return nil
            },
            userInfo: userInfo
        )

        guard let newTap else {
            Unmanaged<InputBlocker>.fromOpaque(userInfo).release()
            throw BlockerError.tapCreateFailed
        }

        tap = newTap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        // Safety net: OS cleans the tap on process death, but atexit handles graceful exit.
        atexit_b {
            CGEvent.tapEnable(tap: newTap, enable: false)
        }
    }

    func uninstall() {
        guard let t = tap else { return }
        CGEvent.tapEnable(tap: t, enable: false)
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        tap = nil
        Unmanaged<InputBlocker>.passUnretained(self).release()
    }
}
