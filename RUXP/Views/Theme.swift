import SwiftUI

// MARK: - Color+Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Theme
//
// RUXP is a game lobby, not a wellness app: near-black ground, one loud "volt" accent,
// red for LIVE, heavy rounded type, monospaced digits for big numbers.

enum Theme {
    // MARK: Backgrounds
    static let background = Color(hex: "0A0A0C")
    static let surface = Color(hex: "141418")
    static let surfaceElevated = Color(hex: "1E1E24")

    // MARK: Accent
    static let accent = Color(hex: "C6FF3D")           // volt
    static let accentSubtle = Color(hex: "C6FF3D").opacity(0.14)
    static let accentDim = Color(hex: "8FBF1F")
    static let onAccent = Color(hex: "0A0A0C")
    static let live = Color(hex: "FF3B3B")
    static let secondary = Color(hex: "8A7CFF")

    // MARK: Text
    static let textPrimary = Color(hex: "F4F4F5")
    static let textSecondary = Color(hex: "9A9AA6")
    static let textTertiary = Color(hex: "5C5C68")

    // MARK: Semantic
    static let success = Color(hex: "C6FF3D")
    static let warning = Color(hex: "FFB020")
    static let error = Color(hex: "FF4D4D")

    // MARK: Border
    static let divider = Color.white.opacity(0.08)
    static let border = Color.white.opacity(0.08)

    // MARK: Corner Radii
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 18
    static let radiusPill: CGFloat = 24

    // MARK: Backward Compat
    static let cardBackground = surface

    // MARK: Type
    enum Fonts {
        /// Big statements: event titles, "WORKOUT COMPLETE".
        static func display(_ size: CGFloat) -> Font {
            .system(size: size, weight: .black, design: .rounded)
        }
        /// Big numbers: lifting-now count, XP totals, level.
        static func number(_ size: CGFloat) -> Font {
            .system(size: size, weight: .heavy, design: .rounded).monospacedDigit()
        }
        static func title(_ size: CGFloat = 22) -> Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        static let eyebrow: Font = .system(size: 11, weight: .bold, design: .rounded)
        static let label: Font = .system(size: 13, weight: .semibold, design: .rounded)
        static let body: Font = .system(size: 15, weight: .medium, design: .rounded)
    }

    enum Motion {
        static let reveal = Animation.spring(response: 0.45, dampingFraction: 0.8)
        static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.72)
        static let pop = Animation.spring(response: 0.35, dampingFraction: 0.55)
    }
}

// MARK: - Theme Card Modifier

struct ThemeCardModifier: ViewModifier {
    var cornerRadius: CGFloat = Theme.radiusMedium

    func body(content: Content) -> some View {
        content
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func themeCard(cornerRadius: CGFloat = Theme.radiusMedium) -> some View {
        modifier(ThemeCardModifier(cornerRadius: cornerRadius))
    }

    /// Small caps label: "LIFTING NOW", "THIS WEEK".
    func eyebrow() -> some View {
        self.font(Theme.Fonts.eyebrow).tracking(1.6).textCase(.uppercase)
    }
}
