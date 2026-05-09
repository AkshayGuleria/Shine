import Foundation

final class TimerService {
    var onTick: ((TimeInterval) -> Void)?
    var onExpiry: (() -> Void)?
    var onWatchdogFire: (() -> Void)?

    private let duration: TimeInterval
    private var elapsed: TimeInterval = 0
    private static let tickInterval: TimeInterval = 0.05

    private var ticker: DispatchSourceTimer?
    private var watchdog: DispatchSourceTimer?

    init(duration: TimeInterval) {
        self.duration = duration
    }

    func start() {
        elapsed = 0

        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + Self.tickInterval,
                   repeating: Self.tickInterval,
                   leeway: .milliseconds(10))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        ticker = t

        let wd = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        wd.schedule(deadline: .now() + duration + 5)
        wd.setEventHandler { [weak self] in
            // Watchdog firing means onExpiry did not run within duration+5s —
            // likely a main-thread stall.
            print("[TimerService] watchdog fired — main thread may have been unresponsive")
            self?.onWatchdogFire?()
        }
        wd.resume()
        watchdog = wd
    }

    func cancel() {
        ticker?.cancel()
        ticker = nil
        watchdog?.cancel()
        watchdog = nil
        // Nil callbacks so any in-flight background dispatch (watchdog queue)
        // cannot invoke stale closures after cancel() returns.
        onTick = nil
        onExpiry = nil
        onWatchdogFire = nil
    }

    private func tick() {
        elapsed += Self.tickInterval
        let remaining = max(0, duration - elapsed)
        onTick?(remaining)
        if remaining <= 0 {
            // Capture before cancel() nils the callbacks.
            let expiry = onExpiry
            cancel()
            expiry?()
        }
    }
}
