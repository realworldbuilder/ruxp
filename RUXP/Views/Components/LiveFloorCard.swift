import SwiftUI

// MARK: - Volume copy

/// Volume is stored in lb; players who think in kg see kg. One place for the wording.
enum VolumeFormat {
    static func unitLabel(_ unit: String) -> String { unit == WeightUnit.kg.rawValue ? "KG" : "LB" }

    static func amount(_ lb: Double, unit: String) -> Double {
        unit == WeightUnit.kg.rawValue ? lb / StructuredLog.poundsPerKilogram : lb
    }

    /// "742,391 LB"
    static func text(_ lb: Double, unit: String) -> String {
        "\(amount(lb, unit: unit).groupedLB) \(unitLabel(unit))"
    }

    /// "742K LB", "1M LB"
    static func compact(_ lb: Double, unit: String) -> String {
        "\(amount(lb, unit: unit).compactLB) \(unitLabel(unit))"
    }
}

// MARK: - Simulated

/// DEBUG builds running `-RUXPLiveDemo` say so on every surface the simulator feeds.
struct SimulatedTag: View {
    @Environment(\.livePresence) private var presence

    var body: some View {
        #if DEBUG
        if presence as? LiveWorldSimulator != nil {
            SlantTag(text: "Simulated", fill: Theme.warning.opacity(0.14), textColor: Theme.warning, size: 10)
        }
        #else
        EmptyView()
        #endif
    }
}

// MARK: - Shared objective

/// MOVE 1,000,000 LB TOGETHER: the bar and the honest line under it. Real counts only; when
/// the source is unavailable the message says why instead of showing zeros as progress.
struct SessionObjectiveBar: View {
    @Environment(\.liveObjective) private var objective
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue

    let event: LiveEvent
    /// Shown when the source has no numbers yet (Game Center off, not signed in).
    var unavailableMessage: String = "Counts appear once Game Center is on."
    var compact = false

    private var state: SessionObjectiveState {
        objective?.state ?? .unavailable(targetLB: event.objective?.targetLB ?? LiveSessionCatalog.objectiveTargetLB)
    }

    var body: some View {
        let target = event.objective?.targetLB ?? state.targetLB
        let met = state.isAvailable && state.totalLB >= target
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            if !compact {
                Text(met ? "OBJECTIVE COMPLETE" : "MOVE \(VolumeFormat.text(target, unit: weightUnit)) TOGETHER")
                    .eyebrow()
                    .foregroundStyle(met ? Theme.xp : Theme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceElevated)
                    Capsule()
                        .fill(met ? Theme.xp : Theme.accent)
                        .frame(width: state.isAvailable ? max(state.totalLB > 0 ? 6 : 0, geo.size.width * min(1, state.totalLB / max(1, target))) : 0)
                        .animation(.easeOut(duration: 0.8), value: state.totalLB)
                }
            }
            .frame(height: 6)
            Text(line(target: target))
                .font(Theme.Fonts.mono(compact ? 11 : 12))
                .monospacedDigit()
                .foregroundStyle(state.isAvailable ? Theme.textSecondary : Theme.textTertiary)
                .contentTransition(.numericText())
                .animation(Theme.Motion.snappy, value: state.totalLB)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func line(target: Double) -> String {
        guard state.isAvailable else { return unavailableMessage }
        let progress = "\(VolumeFormat.amount(state.totalLB, unit: weightUnit).groupedLB) / \(VolumeFormat.text(target, unit: weightUnit))"
        switch state.contributors {
        case 0: return compact ? progress : "\(progress) · nobody has logged sets yet"
        case 1: return "\(progress) · 1 lifter contributing"
        default: return "\(progress) · \(state.contributors.grouped) lifters contributing"
        }
    }
}

// MARK: - The floor

/// What is happening around you, as a passive stream. Not a chat. Full in the lobby, one
/// line during a workout. Lines come from `LiveActivityProviding`, so nothing here polls.
struct LiveFloorCard: View {
    @Environment(\.liveActivity) private var activity
    @Environment(\.livePresence) private var presence

    var compact = false
    var unavailableMessage: String? = nil
    private let shown = 8

    private var events: [LiveActivityEvent] { activity?.events ?? [] }

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    // MARK: Lobby

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("THE FLOOR").eyebrow().foregroundStyle(Theme.textSecondary)
                Spacer()
                SimulatedTag()
                if !events.isEmpty { LiveDot(label: nil, size: 6) }
            }
            if events.isEmpty {
                Text(emptyLine)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(events.suffix(shown).reversed()) { event in
                        row(event)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(Theme.Motion.snappy, value: events.count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private var emptyLine: String {
        if let unavailableMessage, !(presence?.snapshot.isAvailable ?? false) { return unavailableMessage }
        return "Quiet right now. Lines land here as people train."
    }

    private func row(_ event: LiveActivityEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: glyph(for: event.kind))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint(for: event.kind))
                .frame(width: 14)
            Text(event.text)
                .font(Theme.Fonts.body)
                .foregroundStyle(event.kind == .you ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(event.at, format: .dateTime.hour().minute())
                .font(Theme.Fonts.mono(10))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: During a workout

    /// One quiet line: the newest thing that happened. Fixed height so the mic never moves.
    @ViewBuilder
    private var compactBody: some View {
        if let latest = events.last {
            HStack(spacing: 8) {
                Image(systemName: glyph(for: latest.kind))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint(for: latest.kind))
                    .frame(width: 12)
                Text(latest.text)
                    .font(Theme.Fonts.label)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .transition(.opacity)
                    .id(latest.id)
                Spacer()
            }
            .frame(height: 28)
            .padding(.horizontal, 16)
            .animation(Theme.Motion.snappy, value: events.count)
            .overlay(alignment: .bottom) { Divider().overlay(Theme.divider) }
        }
    }

    private func glyph(for kind: LiveActivityEvent.Kind) -> String {
        switch kind {
        case .set: return "dumbbell"
        case .joined: return "person.fill"
        case .finished: return "checkmark"
        case .milestone: return "flag.fill"
        case .training: return "figure.strengthtraining.traditional"
        case .moved: return "arrow.up"
        case .reaction: return "bubble.fill"
        case .you: return "person.crop.circle.fill"
        }
    }

    private func tint(for kind: LiveActivityEvent.Kind) -> Color {
        switch kind {
        case .milestone: return Theme.violet
        case .you: return Theme.accent
        case .finished: return Theme.xp
        default: return Theme.textTertiary
        }
    }
}
