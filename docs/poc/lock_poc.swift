#!/usr/bin/env swift
// Phase 1 POC: prove CGEventTap can drop all input for N seconds, then restore.
// Run: swift docs/poc/lock_poc.swift
// First run triggers Accessibility prompt — grant it to Terminal.app.

import Cocoa
import ApplicationServices

let kLockDuration: TimeInterval = 5.0

// MARK: - Permission check

let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(opts) else {
    print("ERROR: Accessibility not granted.")
    print("Grant access to Terminal (or your shell) in:")
    print("System Settings → Privacy & Security → Accessibility")
    print("Then re-run this script.")
    exit(1)
}

print("Accessibility: OK")
print("Locking input for \(Int(kLockDuration)) seconds...")
print("(keyboard and trackpad will be unresponsive)")

// MARK: - Event tap

var tap: CFMachPort?
var runLoopSource: CFRunLoopSource?

let mask: CGEventMask =
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

// Callback drops all events unconditionally.
let callback: CGEventTapCallBack = { _, _, event, _ in
    return nil  // nil = drop the event
}

tap = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: mask,
    callback: callback,
    userInfo: nil
)

guard let tap else {
    print("ERROR: Failed to create CGEventTap.")
    print("Make sure Accessibility is granted and re-run.")
    exit(1)
}

runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

// MARK: - Unlock after N seconds

DispatchQueue.main.asyncAfter(deadline: .now() + kLockDuration) {
    CGEvent.tapEnable(tap: tap, enable: false)
    if let src = runLoopSource {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
    }
    print("Input restored. POC done.")
    exit(0)
}

// MARK: - Run

RunLoop.main.run()
