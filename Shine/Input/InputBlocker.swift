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
    private var retainedSelf: UnsafeMutableRawPointer?
    private let abortGuard = AbortGuard()

    private static let eventMask: CGEventMask = {
        let keyboard: CGEventMask =
            CGEventMask(1 << CGEventType.keyDown.rawValue) |
            CGEventMask(1 << CGEventType.keyUp.rawValue) |
            CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let mouse: CGEventMask =
            CGEventMask(1 << CGEventType.mouseMoved.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseUp.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        let drag: CGEventMask =
            CGEventMask(1 << CGEventType.leftMouseDragged.rawValue) |
            CGEventMask(1 << CGEventType.rightMouseDragged.rawValue) |
            CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
        let other: CGEventMask =
            CGEventMask(1 << CGEventType.scrollWheel.rawValue) |
            CGEventMask(1 << CGEventType.tabletPointer.rawValue) |
            CGEventMask(1 << CGEventType.tabletProximity.rawValue)
        return keyboard | mouse | drag | other
    }()

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

        retainedSelf = userInfo
        tap = newTap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        atexit_b { CGEvent.tapEnable(tap: newTap, enable: false) }
    }

    /// Safe to call from any thread — Mach port write only.
    /// Use this from the watchdog to stop input immediately even if the main thread is hung.
    func disableTap() {
        guard let t = tap else { return }
        CGEvent.tapEnable(tap: t, enable: false)
    }

    /// Must be called on the main thread.
    /// CFRunLoopRemoveSource and retainedSelf release are not safe off-thread.
    func uninstall() {
        assert(Thread.isMainThread, "uninstall() must be called on the main thread")
        guard let t = tap else { return }
        CGEvent.tapEnable(tap: t, enable: false)
        tap = nil
        // Remove source before releasing retainedSelf — guarantees no callbacks
        // are in-flight when the retain count drops.
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        if let ptr = retainedSelf {
            Unmanaged<InputBlocker>.fromOpaque(ptr).release()
            retainedSelf = nil
        }
    }
}
