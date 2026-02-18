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

enum Theme {
    // MARK: - Backgrounds
    static let background = Color(hex: "0d0d0d")
    static let surface = Color(hex: "1a1a1a")
    static let surfaceElevated = Color(hex: "2a2a2a")

    // MARK: - Accent
    static let accent = Color(hex: "10a37f")           // OpenAI green
    static let accentSubtle = Color(hex: "10a37f").opacity(0.15)
    static let secondary = Color(hex: "5a67d8")         // Indigo

    // MARK: - Text
    static let textPrimary = Color(hex: "ececf1")
    static let textSecondary = Color(hex: "8e8ea0")
    static let textTertiary = Color(hex: "565869")

    // MARK: - Semantic
    static let success = Color(hex: "10a37f")
    static let warning = Color(hex: "f59e0b")
    static let error = Color(hex: "ef4444")

    // MARK: - Border
    static let divider = Color.white.opacity(0.08)
    static let border = Color.white.opacity(0.08)

    // MARK: - Corner Radii
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let radiusPill: CGFloat = 24

    // MARK: - Backward Compat
    static let cardBackground = surface
}

// MARK: - Theme Card Modifier

struct ThemeCardModifier: ViewModifier {
    var cornerRadius: CGFloat = Theme.radiusMedium

    func body(content: Content) -> some View {
        content
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func themeCard(cornerRadius: CGFloat = Theme.radiusMedium) -> some View {
        modifier(ThemeCardModifier(cornerRadius: cornerRadius))
    }
}
