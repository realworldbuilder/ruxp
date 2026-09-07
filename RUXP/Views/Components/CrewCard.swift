import SwiftUI

/// Your crew this week. Who is lifting right now, who is in, and one honest line about the
/// week's stake. Shows who is in; never lists who is out.
struct CrewCard: View {
    @Environment(CrewService.self) private var crew
    @Environment(ProgressionService.self) private var progression
    @Environment(\.liveEvents) private var events
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("CREW").eyebrow().foregroundStyle(Theme.textSecondary)
                Spacer()
                if crew.goalMet {
                    SlantTag(text: "CREW WEEK ✓", fill: Theme.xpSubtle, textColor: Theme.xp, size: 10)
                } else if !crew.isEmpty {
                    Text("\(crew.inCount)/\(crew.size) IN THIS WEEK").eyebrow().foregroundStyle(Theme.textTertiary)
                }
            }

            if let lifting = crew.liftingLine {
                HStack(spacing: 8) {
                    LiveDot(label: nil, size: 6)
                    Text(lifting)
                        .font(Theme.Fonts.title(16))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }
            }

            if !crew.isEmpty {
                pills
            }

            Text(sundayLine ?? crew.line)
                .font(Theme.Fonts.body)
                .foregroundStyle(crew.goalMet ? Theme.xp : (crew.youAreLast ? Theme.accent : Theme.textSecondary))
                .fixedSize(horizontal: false, vertical: true)

            if crew.isEmpty {
                ShareLink(item: "Lift with me on RUXP. Add me on Game Center and we're a crew.") {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Invite a friend")
                    }
                    .font(Theme.Fonts.ui(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.surfaceElevated, in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                .stroke(crew.liftingNow.isEmpty ? Theme.border : Theme.borderNeon, lineWidth: 1)
        )
    }

    /// Names who are in, with their count. "YOU" first when you are in.
    private var pills: some View {
        let me = crew.localThisWeek
        let entries: [(String, Int, Bool)] = (me > 0 ? [("YOU", me, false)] : [])
            + crew.inThisWeek.map { ($0.displayName, $0.thisWeek, $0.liftingNow) }
        return FlowPills(entries: entries)
    }

    /// On Sunday, while the reset is live and the crew is not done, the stake has a deadline.
    private var sundayLine: String? {
        guard !crew.isEmpty, !crew.goalMet,
              let live = events.activeEvent(at: now), live.kind == .sundayReset else { return nil }
        return "Crew at \(crew.inCount)/\(crew.size). Sunday is last call. \(crew.youAreLast ? "Get in." : "")"
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Mono name pills that wrap. Lifting members carry a red dot.
private struct FlowPills: View {
    let entries: [(String, Int, Bool)]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                HStack(spacing: 5) {
                    if e.2 { Circle().fill(Theme.live).frame(width: 5, height: 5) }
                    Text(e.0).font(Theme.Fonts.mono(11))
                    Text("\(e.1)").font(Theme.Fonts.mono(11)).foregroundStyle(Theme.xp)
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Theme.surfaceElevated, in: Capsule())
            }
        }
    }
}
