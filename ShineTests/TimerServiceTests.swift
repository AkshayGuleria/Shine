import XCTest
@testable import Shine

final class TimerServiceTests: XCTestCase {

    func testExpiryFires() async throws {
        let svc = TimerService(duration: 0.2)
        let exp = expectation(description: "expiry")
        svc.onExpiry = { exp.fulfill() }
        svc.start()
        await fulfillment(of: [exp], timeout: 1.0)
    }

    func testTickDeliversDecreasingRemaining() async throws {
        let svc = TimerService(duration: 1.0)
        var ticks: [TimeInterval] = []
        let exp = expectation(description: "expiry")

        svc.onTick = { remaining in ticks.append(remaining) }
        svc.onExpiry = { exp.fulfill() }
        svc.start()

        await fulfillment(of: [exp], timeout: 2.0)

        XCTAssertFalse(ticks.isEmpty)
        // Ticks should be monotonically non-increasing
        for i in 1..<ticks.count {
            XCTAssertLessThanOrEqual(ticks[i], ticks[i - 1])
        }
    }

    func testCancelStopsTicks() async throws {
        let svc = TimerService(duration: 2.0)
        var tickCount = 0
        svc.onTick = { _ in tickCount += 1 }
        svc.start()
        try await Task.sleep(for: .milliseconds(100))
        svc.cancel()
        let countAtCancel = tickCount
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(tickCount, countAtCancel, "No ticks after cancel")
    }

    func testCancelAfterStartDoesNotCrash() {
        // Regression: cancel() immediately after start() must not crash or access-race.
        // Watchdog fires at duration+5s — too slow for a unit test; the 5s delay is
        // intentional production behaviour and cannot be shortened without DI.
        let svc = TimerService(duration: 0.1)
        svc.onWatchdogFire = { XCTFail("watchdog should not fire after cancel") }
        svc.start()
        svc.cancel()
        // No assertion needed — absence of crash / EXC_BAD_ACCESS is the test.
    }
}
