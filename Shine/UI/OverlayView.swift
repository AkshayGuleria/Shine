import SwiftUI

struct OverlayView: View {
    let state: LockState

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                switch state {
                case .arming(let remaining):
                    Text("Get ready…")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("\(remaining)")
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())

                case .locked(let remaining):
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.8))
                    Text(formatTime(remaining))
                        .font(.system(size: 96, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("Hold Esc key for 2 seconds to cancel")
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))

                default:
                    EmptyView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: state)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(ceil(t))
        let m = total / 60
        let s = total % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : String(format: "%d", s)
    }
}
