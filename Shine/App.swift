import SwiftUI

@main
struct ShineApp: App {
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
