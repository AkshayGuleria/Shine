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
    private var permissionPollStart: Date?

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
            enterArming(lockDuration: min(duration, Self.maxDuration))
            return
        }

        // requestAccessibility() shows the system prompt AND returns current trust state.
        // If the user had already granted before (e.g. prior session), it returns true here.
        if permission.requestAccessibility() {
            enterArming(lockDuration: min(duration, Self.maxDuration))
            return
        }

        // Not yet granted — poll; AXIsProcessTrusted() may require a relaunch to reflect
        // a freshly granted permission, so we cap polling and offer a relaunch if needed.
        pendingDuration = duration
        state = .awaitingPermission
        startPermissionPolling()
    }

    func abort() {
        guard case .locked = state else { return }
        enterUnlocking()
    }

    // MARK: - Permission polling

    private static let permissionPollTimeout: TimeInterval = 30

    private func startPermissionPolling() {
        stopPermissionPolling()
        permissionPollStart = Date()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // Cancel the poller is async — guard against a stale final firing.
            guard case .awaitingPermission = self.state else { return }

            if self.permission.isAccessibilityGranted() {
                self.stopPermissionPolling()
                if let d = self.pendingDuration {
                    self.pendingDuration = nil
                    self.state = .idle
                    // Call enterArming directly — permission confirmed, skip re-check.
                    self.enterArming(lockDuration: min(d, Self.maxDuration))
                }
                return
            }

            // AXIsProcessTrusted() sometimes won't reflect a freshly granted permission
            // until the process relaunches. After the timeout, offer a relaunch.
            if let start = self.permissionPollStart,
               Date().timeIntervalSince(start) >= Self.permissionPollTimeout {
                self.stopPermissionPolling()
                let d = self.pendingDuration
                self.pendingDuration = nil
                self.state = .idle
                self.offerRelaunch(pendingDuration: d)
            }
        }
        timer.resume()
        permissionPoller = timer
    }

    private func stopPermissionPolling() {
        permissionPoller?.cancel()
        permissionPoller = nil
        permissionPollStart = nil
    }

    private func offerRelaunch(pendingDuration: TimeInterval?) {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "Shine needs to restart to activate the Accessibility permission you just granted. Restart now?"
        alert.addButton(withTitle: "Restart Shine")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        NSApp.terminate(nil)
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
        // Guard: abort() may have already transitioned away from .arming.
        // Without this, a pending Task { @MainActor } tick can resurrect arming state.
        guard case .arming = state else { timer.invalidate(); return }
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
            Task { @MainActor in
                self?.playCompletionSound()
                self?.enterUnlocking()
            }
        }
        service.onWatchdogFire = { [weak self] in
            // disableTap() is Mach-port-only — safe from background thread.
            // Full cleanup (CFRunLoopRemoveSource + ARC release) deferred to
            // main actor via enterUnlocking(), which calls uninstall().
            self?.inputBlocker?.disableTap()
            Task { @MainActor in self?.enterUnlocking() }
        }

        blocker.abortHandler = { [weak self] in
            Task { @MainActor in self?.enterUnlocking() }
        }

        do {
            try blocker.install()
        } catch BlockerError.notAuthorized {
            // TCC propagation lag — AXIsProcessTrusted() raced between our check and
            // the kernel's trust state. Surface it rather than silently going idle.
            print("[AppCoordinator] install() notAuthorized — TCC propagation lag")
            inputBlocker = nil
            enterUnlocking()
            return
        } catch BlockerError.tapCreateFailed {
            // CGEvent.tapCreate returned nil. Causes: Secure Input active (e.g. password
            // manager), system tap limit hit, or kernel trust not yet propagated.
            print("[AppCoordinator] install() tapCreateFailed — CGEvent.tapCreate returned nil")
            inputBlocker = nil
            enterUnlocking()
            return
        } catch {
            print("[AppCoordinator] install() unexpected error: \(error)")
            inputBlocker = nil
            enterUnlocking()
            return
        }

        state = .locked(remaining: duration)
        overlayController?.update(state: state)
        service.start()
    }

    private func enterUnlocking() {
        guard state != .unlocking && state != .idle && state != .awaitingPermission else { return }
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

    private func playCompletionSound() {
        guard UserDefaults.standard.bool(forKey: "soundOnCompletion") else { return }
        NSSound(named: "Glass")?.play()
    }
}
