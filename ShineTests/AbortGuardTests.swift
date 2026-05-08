import XCTest
import CoreGraphics
@testable import Shine

final class AbortGuardTests: XCTestCase {

    func testEscKeyPassesThrough() {
        let guard_ = AbortGuard()
        var aborted = false
        guard_.abortHandler = { aborted = true }

        // Simulate keyDown for Esc (keycode 53)
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
        let pass = guard_.shouldPassThrough(event: event, type: .keyDown)
        XCTAssertTrue(pass, "Esc keyDown must pass through")
        XCTAssertFalse(aborted, "Should not abort immediately on keyDown")
    }

    func testNonEscDropped() {
        let guard_ = AbortGuard()
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        let pass = guard_.shouldPassThrough(event: event, type: .keyDown)
        XCTAssertFalse(pass, "Non-Esc keys must be dropped")
    }

    func testEscKeyUpCancelsAbort() async throws {
        let guard_ = AbortGuard()
        var aborted = false
        guard_.abortHandler = { aborted = true }

        let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
        _ = guard_.shouldPassThrough(event: downEvent, type: .keyDown)

        // Release before 2s
        try await Task.sleep(for: .milliseconds(500))
        let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)!
        _ = guard_.shouldPassThrough(event: upEvent, type: .keyUp)

        // Wait past the 2s threshold
        try await Task.sleep(for: .milliseconds(1600))
        XCTAssertFalse(aborted, "Abort should not fire after early key-up")
    }

    func testEscHeld2SecondsTriggersAbort() async throws {
        let guard_ = AbortGuard()
        var aborted = false
        guard_.abortHandler = { aborted = true }

        let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
        _ = guard_.shouldPassThrough(event: downEvent, type: .keyDown)

        // Wait > 2s without releasing
        try await Task.sleep(for: .milliseconds(2100))
        XCTAssertTrue(aborted, "Abort must fire after Esc held ≥ 2s")
    }
}
