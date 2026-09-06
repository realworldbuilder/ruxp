import SwiftUI

// MARK: - Wordmark

/// RUXP in Orbitron Black with a one-pixel chromatic offset. The one loud thing on a screen.
struct RUXPWordmark: View {
    var size: CGFloat = 28
    var color: Color = Theme.textPrimary
    var glitch: Bool = true

    var body: some View {
        if glitch {
            GlitchText(text: "RUXP", font: Theme.Fonts.display(size), color: color, offset: max(1.0, size * 0.035))
        } else {
            Text("RUXP")
                .font(Theme.Fonts.display(size))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Live indicator

struct LiveDot: View {
    var label: String? = "LIVE"
    var color: Color = Theme.live
    var size: CGFloat = 8
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: size * 2, height: size * 2)
                    .scaleEffect(pulse ? 1.5 : 0.7)
                    .opacity(pulse ? 0 : 1)
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
            }
            .frame(width: size * 2, height: size * 2)
            if let label {
                Text(label).eyebrow().foregroundStyle(color)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

// MARK: - Big animated number

struct BigNumber: View {
    let value: Int
    var size: CGFloat = 56
    var color: Color = Theme.textPrimary

    var body: some View {
        Text(value.grouped)
            .font(Theme.Fonts.number(size))
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(value)))
            .animation(Theme.Motion.snappy, value: value)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - XP bar

struct XPBar: View {
    let level: Int
    let xpIntoLevel: Int
    let xpToNext: Int
    var compact = false

    private var fraction: Double {
        xpToNext > 0 ? min(1, Double(xpIntoLevel) / Double(xpToNext)) : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("LVL").eyebrow().foregroundStyle(Theme.textSecondary)
                    Text("\(level)")
                        .font(Theme.Fonts.number(compact ? 20 : 28))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText(value: Double(level)))
                }
                Spacer()
                Text(xpToNext > 0 ? "\(xpIntoLevel.grouped) / \(xpToNext.grouped) XP" : "MAX LEVEL")
                    .font(Theme.Fonts.mono(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceElevated)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(10, geo.size.width * fraction))
                }
            }
            .frame(height: compact ? 5 : 6)
            .animation(Theme.Motion.reveal, value: fraction)
        }
    }
}

// MARK: - XP chip

/// "+240 XP" in terminal green mono. Prominent = filled.
struct XPChip: View {
    let amount: Int
    var prominent = true

    var body: some View {
        Text("+\(amount.grouped) XP")
            .font(Theme.Fonts.mono(12, weight: .heavy))
            .foregroundStyle(prominent ? Theme.onXP : Theme.xp)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(prominent ? Theme.xp : Theme.xpSubtle, in: Capsule())
    }
}

// MARK: - Slanted tag

/// Quiet outlined chip: season code, LEVEL UP. Magenta text is the hint.
struct SlantTag: View {
    let text: String
    var fill: Color = Theme.accentSubtle
    var textColor: Color = Theme.accent
    var size: CGFloat = 11

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(fill, in: Capsule())
    }
}

// MARK: - Buttons

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

/// Full-width white pill, ChatGPT style. Title case, no shouting.
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var height: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                }
                Text(title.capitalized)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Theme.onButton)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Theme.button, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
                Text(title.capitalized)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Theme.surfaceElevated, in: Capsule())
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Small pill action: "START" on a plan row, "End" in a toolbar.
struct PillButton: View {
    let title: String
    var fill: Color = Theme.button
    var textColor: Color = Theme.onButton
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textColor)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(fill, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let title: String
    let value: String
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).eyebrow().foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(accent ? Theme.xp : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - Section header

/// Quiet mono eyebrow with a hairline, ChatGPT-style section rhythm.
struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title).eyebrow().foregroundStyle(Theme.textTertiary)
            Spacer()
            if let trailing { Text(trailing).eyebrow().foregroundStyle(Theme.textTertiary) }
        }
    }
}
