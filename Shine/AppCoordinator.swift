import Cocoa
import Combine

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var state: LockState = .idle

    private let permission = PermissionCoordinator()
    private var inputBlocker: InputBlocker?
    private var timerService: TimerService?
    private var overlayController: OverlayWindowController?
    private var armingTimer: Timer?
    private var armingCount = 3
    private var sleepObserver: NSObjectProtocol?
    private var permissionPoller: DispatchSourceTimer?
    private var pendingDuration: TimeInterval?

    private static let maxDuration: TimeInterval = 120
    private static let armSeconds = 3

    init() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSleep() }
        }
    }

    deinit {
        if let obs = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    // MARK: - Public API

    func start(duration: TimeInterval) {
        guard case .idle = state else { return }

        if permission.isAccessibilityGranted() {
            let clamped = min(duration, Self.maxDuration)
            enterArming(lockDuration: clamped)
            return
        }

        // Not granted — show system prompt once, then poll until granted.
        _ = permission.requestAccessibility()
        pendingDuration = duration
        startPermissionPolling()
    }

    func abort() {
        guard case .locked = state else { return }
        enterUnlocking()
    }

    // MARK: - Permission polling

    private func startPermissionPolling() {
        stopPermissionPolling()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.permission.isAccessibilityGranted() {
                self.stopPermissionPolling()
                if let d = self.pendingDuration {
                    self.pendingDuration = nil
                    self.start(duration: d)
                }
            }
        }
        timer.resume()
        permissionPoller = timer
    }

    private func stopPermissionPolling() {
        permissionPoller?.cancel()
        permissionPoller = nil
    }

    // MARK: - State transitions

    private func enterArming(lockDuration: TimeInterval) {
        armingCount = Self.armSeconds
        state = .arming(remaining: armingCount)

        overlayController = OverlayWindowController()
        overlayController?.show(state: state)

        armingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in self.tickArming(lockDuration: lockDuration, timer: timer) }
        }
    }

    private func tickArming(lockDuration: TimeInterval, timer: Timer) {
        armingCount -= 1
        if armingCount > 0 {
            state = .arming(remaining: armingCount)
            overlayController?.update(state: state)
        } else {
            timer.invalidate()
            armingTimer = nil
            enterLocked(duration: lockDuration)
        }
    }

    private func enterLocked(duration: TimeInterval) {
        let blocker = InputBlocker()
        inputBlocker = blocker

        let service = TimerService(duration: duration)
        timerService = service

        service.onTick = { [weak self] remaining in
            Task { @MainActor in
                guard let self, case .locked = self.state else { return }
                self.state = .locked(remaining: remaining)
                self.overlayController?.update(state: self.state)
            }
        }
        service.onExpiry = { [weak self] in
            Task { @MainActor in self?.enterUnlocking() }
        }
        service.onWatchdogFire = { [weak self] in
            // Called on background queue. Uninstall tap immediately —
            // don't wait for main actor in case main thread is hung.
            self?.inputBlocker?.uninstall()
            Task { @MainActor in self?.enterUnlocking() }
        }

        blocker.abortHandler = { [weak self] in
            Task { @MainActor in self?.enterUnlocking() }
        }

        do {
            try blocker.install()
        } catch {
            enterUnlocking()
            return
        }

        state = .locked(remaining: duration)
        overlayController?.update(state: state)
        service.start()
    }

    private func enterUnlocking() {
        guard state != .unlocking && state != .idle else { return }
        state = .unlocking

        timerService?.cancel()
        timerService = nil

        inputBlocker?.uninstall()
        inputBlocker = nil

        overlayController?.dismiss {
            Task { @MainActor in
                self.overlayController = nil
                self.state = .idle
            }
        }
    }

    private func handleSleep() {
        guard case .locked = state else { return }
        enterUnlocking()
    }
}
