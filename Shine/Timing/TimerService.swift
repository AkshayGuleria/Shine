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
        wd.setEventHandler { [weak self] in self?.onWatchdogFire?() }
        wd.resume()
        watchdog = wd
    }

    func cancel() {
        ticker?.cancel()
        ticker = nil
        watchdog?.cancel()
        watchdog = nil
    }

    private func tick() {
        elapsed += Self.tickInterval
        let remaining = max(0, duration - elapsed)
        onTick?(remaining)
        if remaining <= 0 {
            cancel()
            onExpiry?()
        }
    }
}
