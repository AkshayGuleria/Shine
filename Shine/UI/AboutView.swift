import SwiftUI

struct AboutView: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("Shine")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            Text("Version \(version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Temporarily disables keyboard and trackpad\nso you can wipe your Mac clean.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            Text("© 2026 Akshay Guleria")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 300)
    }
}
