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
// ChatGPT with hints of gaming. Neutral near-black ground, flat surfaces, hairline
// borders, white pill buttons, system type for everything you read. The game shows up
// in small doses: Orbitron on the wordmark and one hero number per screen, terminal
// green mono for XP values, a magenta progress bar and tab tint, a red LIVE dot.

enum Theme {
    // MARK: Backgrounds
    static let background = Color(hex: "0F0F10")
    static let surface = Color(hex: "1A1A1D")
    static let surfaceElevated = Color(hex: "26262A")
    static let surfaceGlow = Color(hex: "2E2E33")

    // MARK: Accent
    static let accent = Color(hex: "FF2DAA")            // magenta
    static let accentSubtle = Color(hex: "FF2DAA").opacity(0.16)
    static let accentDim = Color(hex: "C21C82")
    static let onAccent = Color(hex: "FFF7FD")
    /// Primary buttons are white on dark, ChatGPT style.
    static let button = Color(hex: "F2F2F2")
    static let onButton = Color(hex: "0F0F10")
    static let cyan = Color(hex: "7DD3FC")
    static let cyanSubtle = Color(hex: "7DD3FC").opacity(0.14)
    static let violet = Color(hex: "A78BFA")
    static let violetSubtle = Color(hex: "A78BFA").opacity(0.14)
    static let xp = Color(hex: "5CFF7A")                // terminal green
    static let xpSubtle = Color(hex: "5CFF7A").opacity(0.14)
    static let onXP = Color(hex: "06210C")
    static let live = Color(hex: "FF3B5C")
    /// Season chrome (kept under the old name so call sites read the same).
    static let secondary = violet

    // MARK: Text
    static let textPrimary = Color(hex: "ECECEC")
    static let textSecondary = Color(hex: "A0A0A6")
    static let textTertiary = Color(hex: "6E6E75")

    // MARK: Semantic
    static let success = Color(hex: "5CFF7A")
    static let warning = Color(hex: "FFB84D")
    static let error = Color(hex: "FF4D6D")

    // MARK: Border
    static let divider = Color.white.opacity(0.08)
    static let border = Color.white.opacity(0.10)
    static let borderNeon = Color(hex: "FF2DAA").opacity(0.45)

    // MARK: Corner Radii (ChatGPT-generous; the slant lives in tag bars and type, not every box)
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 14
    static let radiusLarge: CGFloat = 20
    static let radiusPill: CGFloat = 999

    // MARK: Backward Compat
    static let cardBackground = surface

    // MARK: Type
    enum Fonts {
        /// Big statements: event titles, "WORKOUT COMPLETE", the wordmark.
        static func display(_ size: CGFloat) -> Font {
            .custom(Typeface.orbitronBlack, size: size, relativeTo: .largeTitle)
        }
        /// Big numbers: lifting-now count, XP totals, level.
        static func number(_ size: CGFloat) -> Font {
            .custom(Typeface.orbitronBold, size: size, relativeTo: .largeTitle)
        }
        /// Button labels and small shouts. System, not italic: the restraint is the point.
        static func tagline(_ size: CGFloat) -> Font {
            .system(size: size, weight: .semibold)
        }
        static func title(_ size: CGFloat = 22) -> Font {
            .system(size: size, weight: .semibold)
        }
        /// Readouts: XP values, timers, set × rep data.
        static func mono(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
            .custom(Typeface.mono(weight), size: size, relativeTo: .body)
        }
        static let eyebrow: Font = .system(size: 11, weight: .semibold)
        static let label: Font = .system(size: 13, weight: .medium)
        static let body: Font = .system(size: 15, weight: .regular)

        /// System text styles, with JetBrains Mono when `mono` is true (numbers, readouts).
        static func ui(_ style: Font.TextStyle, weight: Font.Weight? = nil, mono: Bool = false) -> Font {
            if mono {
                let size: CGFloat
                switch style {
                case .largeTitle: size = 34
                case .title: size = 28
                case .title2: size = 22
                case .title3: size = 20
                case .headline, .body: size = 17
                case .callout: size = 16
                case .subheadline: size = 15
                case .footnote: size = 13
                case .caption: size = 12
                case .caption2: size = 11
                @unknown default: size = 15
                }
                return .custom(Typeface.mono(weight ?? .medium), size: size, relativeTo: style)
            }
            let base = Font.system(style)
            return weight.map { base.weight($0) } ?? base
        }
    }

    enum Motion {
        static let reveal = Animation.spring(response: 0.45, dampingFraction: 0.8)
        static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.72)
        static let pop = Animation.spring(response: 0.35, dampingFraction: 0.55)
    }

    /// Skew used for slanted buttons and tag bars (points of horizontal offset per point of height).
    static let slant: CGFloat = 0.22
}

// MARK: - Shapes

/// Parallelogram: the slanted magenta bar under OVERRIDE, as a shape.
struct Slant: Shape {
    var skew: CGFloat = Theme.slant

    func path(in rect: CGRect) -> Path {
        let dx = min(rect.height * skew, rect.width / 3)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + dx, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - dx, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Four small L-shaped ticks in the corners of a rect: HUD framing for cards and tiles.
struct HUDCorners: Shape {
    var length: CGFloat = 10
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let l = min(length, r.width / 3, r.height / 3)
        var p = Path()
        // top-left
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        // top-right
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        // bottom-right
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        // bottom-left
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

// MARK: - Backgrounds

/// Flat neutral ground. `glow` adds one faint magenta wash at the top (workout, reward);
/// `grid` adds a barely-there HUD grid. Both are off by default.
struct HUDBackground: View {
    var glow: Bool = false
    var grid: Bool = false

    var body: some View {
        ZStack {
            Theme.background
            if glow {
                RadialGradient(colors: [Theme.accent.opacity(0.10), .clear],
                               center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 420)
            }
            if grid {
                Canvas { ctx, size in
                    let step: CGFloat = 32
                    var path = Path()
                    var x: CGFloat = 0
                    while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                    var y: CGFloat = 0
                    while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                    ctx.stroke(path, with: .color(.white.opacity(0.02)), lineWidth: 0.5)
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Paints an opaque strip over the top safe area so scrolled content slides under the
    /// status bar instead of through it. `fade` extends a soft gradient below the strip
    /// (use on screens with a glow so the hard edge doesn't show).
    func statusBarBackdrop(_ color: Color = Theme.background, fade: CGFloat = 0) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            LinearGradient(colors: [color, color.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
                .background(color.ignoresSafeArea(edges: .top))
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Glitch text

/// Display text with a one-pixel chromatic offset (cyan left, magenta right). Static by
/// default; the wordmark is the only place it lives now.
struct GlitchText: View {
    let text: String
    var font: Font = Theme.Fonts.display(32)
    var color: Color = Theme.textPrimary
    var offset: CGFloat = 1.0
    var animated: Bool = false
    var skew: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var jitter: CGFloat = 0
    @State private var sliceShift: CGFloat = 0

    var body: some View {
        ZStack {
            layer.foregroundStyle(Theme.cyan).offset(x: -offset - jitter).blendMode(.screen)
            layer.foregroundStyle(Theme.accent).offset(x: offset + jitter).blendMode(.screen)
            layer.foregroundStyle(color)
            if sliceShift != 0 {
                layer.foregroundStyle(color)
                    .offset(x: sliceShift)
                    .mask(
                        VStack(spacing: 0) {
                            Color.clear
                            Rectangle().frame(height: 6)
                            Color.clear.frame(height: 5)
                            Rectangle().frame(height: 3)
                            Color.clear
                        }
                    )
            }
        }
        .task {
            guard animated, !reduceMotion else { return }
            let steps: [(CGFloat, CGFloat)] = [(3, -6), (-2, 8), (1, -3), (0, 0)]
            for (j, s) in steps {
                try? await Task.sleep(for: .milliseconds(70))
                jitter = j; sliceShift = s
            }
        }
    }

    private var layer: some View {
        Text(text)
            .font(font)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .modifier(SkewModifier(enabled: skew))
    }
}

/// Italicises a face that has no italic (Orbitron) by shearing the rendered text.
private struct SkewModifier: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.16, d: 1, tx: 0, ty: 0))
                .padding(.leading, 4)
        } else {
            content
        }
    }
}

// MARK: - Theme Card Modifier

struct ThemeCardModifier: ViewModifier {
    var cornerRadius: CGFloat = Theme.radiusMedium
    var hud: Bool = false

    func body(content: Content) -> some View {
        content
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .overlay {
                if hud {
                    HUDCorners(length: 10, inset: -1).stroke(Theme.violet.opacity(0.7), lineWidth: 1.5)
                }
            }
    }
}

extension View {
    func themeCard(cornerRadius: CGFloat = Theme.radiusMedium, hud: Bool = false) -> some View {
        modifier(ThemeCardModifier(cornerRadius: cornerRadius, hud: hud))
    }

    /// Small caps label: "LIFTING NOW", "THIS WEEK". Tracked, uppercase, quiet.
    func eyebrow() -> some View {
        self.font(Theme.Fonts.eyebrow).tracking(1.0).textCase(.uppercase)
    }

    /// Kept for call sites; glows are off in this season's restrained look.
    func neonGlow(_ color: Color = Theme.accent, radius: CGFloat = 14, opacity: Double = 0.45) -> some View {
        self
    }
}
