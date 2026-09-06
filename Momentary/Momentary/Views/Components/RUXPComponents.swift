import SwiftUI

// MARK: - Wordmark

struct RUXPWordmark: View {
    var size: CGFloat = 28
    var color: Color = Theme.textPrimary

    var body: some View {
        Text("RUXP")
            .font(.system(size: size, weight: .black, design: .rounded))
            .tracking(-size * 0.04)
            .foregroundStyle(color)
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("LVL").eyebrow().foregroundStyle(Theme.textSecondary)
                    Text("\(level)")
                        .font(Theme.Fonts.number(compact ? 24 : 36))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText(value: Double(level)))
                }
                Spacer()
                Text(xpToNext > 0 ? "\(xpIntoLevel.grouped) / \(xpToNext.grouped) XP" : "MAX LEVEL")
                    .font(Theme.Fonts.label)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceElevated)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(10, geo.size.width * fraction))
                        .shadow(color: Theme.accent.opacity(0.45), radius: 6)
                }
            }
            .frame(height: compact ? 8 : 12)
            .animation(Theme.Motion.reveal, value: fraction)
        }
    }
}

// MARK: - XP chip

struct XPChip: View {
    let amount: Int
    var prominent = true

    var body: some View {
        Text("+\(amount.grouped) XP")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(prominent ? Theme.onAccent : Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(prominent ? Theme.accent : Theme.accentSubtle, in: Capsule())
    }
}

// MARK: - Primary button

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var height: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 18, weight: .bold))
                }
                Text(title)
                    .font(.system(size: height > 56 ? 20 : 16, weight: .black, design: .rounded))
                    .tracking(1)
            }
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.35), radius: 16, y: 6)
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
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
                Text(title).font(.system(size: 15, weight: .bold, design: .rounded)).tracking(0.5)
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title).eyebrow().foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.Fonts.number(26))
                .foregroundStyle(accent ? Theme.accent : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
    }
}
