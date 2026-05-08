import SwiftUI

struct MenuBarView: View {
    @ObservedObject var coordinator: AppCoordinator
    @AppStorage("defaultDuration") private var defaultDuration: Double = 60
    @Environment(\.openWindow) private var openWindow

    private let durations: [Double] = [15, 30, 60, 90, 120]

    var body: some View {
        let isActive = coordinator.state != .idle

        Button(action: { coordinator.start(duration: defaultDuration) }) {
            Label("Start cleaning (\(Int(defaultDuration))s)", systemImage: "sparkles")
        }
        .disabled(isActive)

        Picker("Duration", selection: $defaultDuration) {
            ForEach(durations, id: \.self) { d in
                Text("\(Int(d))s").tag(d)
            }
        }
        .pickerStyle(.inline)
        .disabled(isActive)

        Divider()

        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("Settings…")
            }
        } else {
            // Fallback on earlier versions
            
        }

        Button("About Shine…") {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit Shine") {
            NSApplication.shared.terminate(nil)
        }
    }
}
