import SwiftUI

/// "Wait, what happened?" Up to four true lines about what changed while the player was away.
/// Quieter than the event card on purpose: hairline border, no hero number, no spinner.
struct ReturnLedgerCard: View {
    let items: [ReturnItem]
    let awayLabel: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("WHILE YOU WERE GONE").eyebrow().foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(awayLabel) AWAY").eyebrow().foregroundStyle(Theme.textTertiary)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Theme.surfaceElevated, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        glyph(item.accent)
                            .frame(width: 12)
                        Text(item.text)
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(Theme.Motion.reveal, value: items)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func glyph(_ accent: ReturnItem.Accent) -> some View {
        switch accent {
        case .live: LiveDot(label: nil, size: 5)
        case .xp: Circle().fill(Theme.xp).frame(width: 6, height: 6)
        case .violet: Circle().fill(Theme.violet).frame(width: 6, height: 6)
        case .warning: Circle().fill(Theme.warning).frame(width: 6, height: 6)
        case .neutral: Circle().fill(Theme.textTertiary).frame(width: 6, height: 6)
        }
    }
}
