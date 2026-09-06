import SwiftUI

/// Watch tokens matching the iOS Theme: neutral near-black, white buttons, system type,
/// with gaming hints (Orbitron hero number, green mono XP, magenta level bar).
enum WatchTheme {
    // MARK: - Colors
    static let accent = Color(red: 1.0, green: 0.176, blue: 0.667)            // #FF2DAA magenta
    static let accentBright = Color(red: 1.0, green: 0.45, blue: 0.78)
    static let accentDim = Color(red: 0.761, green: 0.110, blue: 0.510)       // #C21C82
    static let onAccent = Color(red: 1.0, green: 0.969, blue: 0.992)          // #FFF7FD
    static let cyan = Color(red: 0.490, green: 0.827, blue: 0.988)            // #7DD3FC
    static let button = Color(red: 0.949, green: 0.949, blue: 0.949)          // #F2F2F2
    static let onButton = Color(red: 0.059, green: 0.059, blue: 0.063)        // #0F0F10
    static let xp = Color(red: 0.361, green: 1.0, blue: 0.478)                // #5CFF7A
    static let onXP = Color(red: 0.024, green: 0.129, blue: 0.047)            // #06210C
    static let violet = Color(red: 0.608, green: 0.420, blue: 1.0)            // #9B6BFF
    static let live = Color(red: 1.0, green: 0.231, blue: 0.361)              // #FF3B5C
    static let background = Color(red: 0.059, green: 0.059, blue: 0.063)      // #0F0F10
    static let surface = Color(red: 0.102, green: 0.102, blue: 0.114)         // #1A1A1D
    static let surfaceElevated = Color(red: 0.149, green: 0.149, blue: 0.165) // #26262A

    static let textPrimary = Color(red: 0.925, green: 0.925, blue: 0.925)     // #ECECEC
    static let textSecondary = Color(red: 0.627, green: 0.627, blue: 0.651)   // #A0A0A6
    static let textTertiary = Color(red: 0.431, green: 0.431, blue: 0.459)    // #6E6E75

    // MARK: - Gradients
    static let accentGradient: [Color] = [
        Color(red: 1.0, green: 0.176, blue: 0.667),
        Color(red: 0.761, green: 0.110, blue: 0.510)
    ]

    static let recordingGradient: [Color] = [
        Color(red: 1.0, green: 0.30, blue: 0.40),
        Color(red: 0.85, green: 0.18, blue: 0.28)
    ]

    static let dangerGradient: [Color] = [
        Color(red: 1.0, green: 0.231, blue: 0.361),
        Color(red: 0.800, green: 0.180, blue: 0.280)
    ]

    /// Flat ground with a faint lift at the top.
    static let backgroundGradient = LinearGradient(
        colors: [surface, background],
        startPoint: .top, endPoint: .center
    )

    // MARK: - Type
    enum Fonts {
        static func display(_ size: CGFloat) -> Font { .custom(Typeface.orbitronBlack, size: size, relativeTo: .title) }
        static func number(_ size: CGFloat) -> Font { .custom(Typeface.orbitronBold, size: size, relativeTo: .title) }
        static func tagline(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
        static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
        static func body(_ size: CGFloat = 13) -> Font { .system(size: size) }
        static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font { .custom(Typeface.mono(weight), size: size, relativeTo: .body) }
        static let eyebrow: Font = .system(size: 9, weight: .semibold)
        static let caption: Font = .system(size: 11)
        static let caption2: Font = .system(size: 10)
    }
}

extension View {
    /// Small caps mono label on the wrist.
    func watchEyebrow() -> some View {
        self.font(WatchTheme.Fonts.eyebrow).tracking(0.8).textCase(.uppercase)
    }
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
                    .watchEyebrow()
                    .foregroundStyle(WatchTheme.live)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
