import SwiftUI

// LSUIElement suppresses the dock icon but not terminate-on-last-window.
// SwiftUI's auto-delegate returns true from applicationShouldTerminateAfterLastWindowClosed
// when its Window scene has no open windows, so we must override it explicitly.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct ShineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("Shine", image: "MenuBarIcon") {
            MenuBarView(coordinator: coordinator)
        }

        Settings {
            SettingsView(coordinator: coordinator)
        }

        Window("About Shine", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
