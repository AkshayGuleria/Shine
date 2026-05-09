import SwiftUI

struct MenuBarView: View {
    @ObservedObject var coordinator: AppCoordinator
    @AppStorage("defaultDuration") private var defaultDuration: Double = 60
    @Environment(\.openWindow) private var openWindow

    private let durations: [Double] = [15, 30, 60, 90, 120]

    var body: some View {
        let isIdle = coordinator.state == .idle
        let isAwaitingPermission = coordinator.state == .awaitingPermission

        if isAwaitingPermission {
            Text("Waiting for Accessibility permission…")
                .foregroundStyle(.secondary)
            Button("I've Approved It — Restart Shine") {
                coordinator.checkPermissionNow()
            }
            Button("Cancel") {
                coordinator.cancelPermissionWait()
            }
            Divider()
        }

        Button(action: { coordinator.start(duration: defaultDuration) }) {
            Label("Start cleaning (\(Int(defaultDuration))s)", systemImage: "sparkles")
        }
        .disabled(!isIdle)

        Picker("Duration", selection: $defaultDuration) {
            ForEach(durations, id: \.self) { d in
                Text("\(Int(d))s").tag(d)
            }
        }
        .pickerStyle(.inline)
        .disabled(!isIdle)

        Divider()

        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("Settings…")
            }
        } else {
            Button("Settings…") {
                let handled = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                if handled { NSApp.activate(ignoringOtherApps: true) }
            }
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
