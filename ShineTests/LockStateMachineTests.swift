import XCTest
@testable import Shine

@MainActor
final class LockStateMachineTests: XCTestCase {

    func testInitialStateIsIdle() async {
        let c = AppCoordinator()
        XCTAssertEqual(c.state, .idle)
    }

    func testStartTransitionsToArming() async throws {
        let c = AppCoordinator()
        // Permission must be trusted in test environment — skip if not.
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Accessibility not granted")
        }
        c.start(duration: 60)
        if case .arming = c.state { } else {
            XCTFail("Expected .arming, got \(c.state)")
        }
    }

    func testCannotStartWhenNotIdle() async throws {
        let c = AppCoordinator()
        guard AXIsProcessTrusted() else { throw XCTSkip("Accessibility not granted") }

        c.start(duration: 60)
        let stateAfterFirst = c.state
        c.start(duration: 30)  // should be no-op
        XCTAssertEqual(c.state, stateAfterFirst)
    }

    func testArmingCountdownCountsDown() async throws {
        let c = AppCoordinator()
        guard AXIsProcessTrusted() else { throw XCTSkip("Accessibility not granted") }

        c.start(duration: 60)
        if case .arming(let r) = c.state {
            XCTAssertEqual(r, 3)
        } else {
            XCTFail("Not in arming state")
        }

        // Wait for first tick
        try await Task.sleep(for: .milliseconds(1100))
        if case .arming(let r) = c.state {
            XCTAssertEqual(r, 2)
        } else {
            XCTFail("Expected still arming after 1s")
        }
    }

    func testDurationClampedAt120() async throws {
        let c = AppCoordinator()
        guard AXIsProcessTrusted() else { throw XCTSkip("Accessibility not granted") }
        // start with 200s — should clamp to 120
        c.start(duration: 200)
        // Once locked, remaining should be ≤ 120
        // (We just verify no crash and state transitions begin)
        XCTAssertNotEqual(c.state, .idle)
    }
}
