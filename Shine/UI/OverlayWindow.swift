import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private var windows: [NSWindow] = []
    private var hostingViews: [NSHostingView<OverlayView>] = []

    func show(state: LockState) {
        let screens = NSScreen.screens
        for screen in screens {
            let win = makeWindow(for: screen)
            let hosting = NSHostingView(rootView: OverlayView(state: state))
            hosting.frame = win.contentView!.bounds
            hosting.autoresizingMask = [.width, .height]
            win.contentView?.addSubview(hosting)
            win.alphaValue = 0
            win.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                win.animator().alphaValue = 1
            }
            windows.append(win)
            hostingViews.append(hosting)
        }
    }

    func update(state: LockState) {
        for hosting in hostingViews {
            hosting.rootView = OverlayView(state: state)
        }
    }

    func dismiss(completion: @escaping () -> Void) {
        let captureWindows = windows
        let captureViews = hostingViews
        windows.removeAll()
        hostingViews.removeAll()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            captureWindows.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            // Defer close by one run loop pass: SwiftUI autoreleases ObjC objects
            // during NSHostingView teardown; closing synchronously here leaves stale
            // autorelease pool entries that crash on drain. The async hop lets the
            // pool drain first.
            DispatchQueue.main.async {
                captureWindows.forEach { $0.close() }
                _ = captureViews  // keep hosting views alive past close()
                completion()
            }
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return win
    }
}
