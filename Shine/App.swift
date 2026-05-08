import SwiftUI

@main
struct ShineApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("Shine", systemImage: "sparkles") {
            MenuBarView(coordinator: coordinator)
        }

        Settings {
            SettingsView(coordinator: coordinator)
        }
    }
}
