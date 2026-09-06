import SwiftUI

/// Watch tokens matching the iOS Theme: near-black ground, volt accent, red LIVE.
enum WatchTheme {
    // MARK: - Colors
    static let accent = Color(red: 0.776, green: 1.0, blue: 0.239)          // #C6FF3D volt
    static let accentBright = Color(red: 0.85, green: 1.0, blue: 0.45)
    static let onAccent = Color(red: 0.039, green: 0.039, blue: 0.047)      // #0A0A0C
    static let live = Color(red: 1.0, green: 0.231, blue: 0.231)            // #FF3B3B
    static let background = Color(red: 0.039, green: 0.039, blue: 0.047)    // #0A0A0C
    static let surface = Color(red: 0.078, green: 0.078, blue: 0.094)       // #141418
    static let surfaceElevated = Color(red: 0.118, green: 0.118, blue: 0.141) // #1E1E24

    static let textPrimary = Color(red: 0.957, green: 0.957, blue: 0.961)   // #F4F4F5
    static let textSecondary = Color(red: 0.604, green: 0.604, blue: 0.651) // #9A9AA6
    static let textTertiary = Color(red: 0.361, green: 0.361, blue: 0.408)  // #5C5C68

    // MARK: - Gradients
    static let accentGradient: [Color] = [
        Color(red: 0.776, green: 1.0, blue: 0.239),
        Color(red: 0.62, green: 0.84, blue: 0.16)
    ]

    static let recordingGradient: [Color] = [
        Color(red: 1.0, green: 0.30, blue: 0.30),
        Color(red: 0.85, green: 0.18, blue: 0.18)
    ]

    static let dangerGradient: [Color] = [
        Color(red: 1.0, green: 0.231, blue: 0.231),
        Color(red: 0.800, green: 0.200, blue: 0.200)
    ]
}

/// Compact pulsing LIVE marker for the watch.
struct WatchLiveDot: View {
    var label: String? = nil
    var size: CGFloat = 6
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().fill(WatchTheme.live.opacity(0.35))
                    .frame(width: size * 2, height: size * 2)
                    .scaleEffect(pulse ? 1.5 : 0.7)
                    .opacity(pulse ? 0 : 1)
                Circle().fill(WatchTheme.live).frame(width: size, height: size)
            }
            .frame(width: size * 2, height: size * 2)
            if let label {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(WatchTheme.live)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
