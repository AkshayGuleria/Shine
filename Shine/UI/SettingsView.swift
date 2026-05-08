import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @AppStorage("defaultDuration") private var defaultDuration: Double = 60
    @AppStorage("soundOnCompletion") private var soundOnCompletion: Bool = true
    @State private var launchAtLogin: Bool = false

    private let durationRange: ClosedRange<Double> = 15...120
    private let durationStep: Double = 15

    var body: some View {
        Form {
            Section("Lock") {
                VStack(alignment: .leading) {
                    Text("Default duration: \(Int(defaultDuration))s")
                    Slider(value: $defaultDuration, in: durationRange, step: durationStep)
                }
                Toggle("Play sound on completion", isOn: $soundOnCompletion)
            }

            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }

                Button("Open Accessibility Settings") {
                    PermissionCoordinator().openAccessibilitySettings()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 260)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !enable  // revert toggle on failure
        }
    }
}
