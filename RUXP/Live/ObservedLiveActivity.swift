import Foundation
import Observation

/// The floor, from real signals only. Nothing here polls: every line comes from a hook that
/// already fires elsewhere (presence, crew, the objective board, the room, your own parse).
/// A small player base makes it sparse. That is honest; the empty state says so.
@Observable
@MainActor
final class ObservedLiveActivity: LiveActivityProviding {
    static let capacity = 30
    /// A milestone line every 250K LB, and one at the target.
    static let milestoneStepLB: Double = 250_000

    private(set) var events: [LiveActivityEvent] = []

    private var lastPresence: LiveSnapshot?
    private var knownLeaders: [String: Double] = [:]
    private var announcedMilestones: Set<Int> = []
    private var lastTotalLB: Double = 0
    private var lastCrewLifting: Set<String> = []
    /// Your own Game Center alias, so your board entry is not echoed back as a stranger.
    var localAlias: () -> String? = { nil }

    func start() {}
    func stop() {}

    // MARK: - Signals

    func notePresence(_ snapshot: LiveSnapshot) {
        defer { lastPresence = snapshot }
        guard snapshot.isAvailable, let previous = lastPresence, previous.isAvailable else { return }
        let finished = snapshot.workoutsToday - previous.workoutsToday
        let delta = snapshot.liftingNow - previous.liftingNow
        if finished > 0 {
            push(.finished, finished == 1 ? "someone just finished a workout" : "\(finished) people just finished")
        } else if delta < 0 {
            push(.finished, delta == -1 ? "someone just finished" : "\(-delta) people just finished")
        }
        if delta > 0 {
            push(.joined, delta == 1 ? "someone just started a workout" : "\(delta) people just started lifting")
        }
    }

    func noteObjective(_ state: SessionObjectiveState) {
        guard state.isAvailable else { return }
        // A new window: the total drops back. Forget last night's milestones and leaders.
        if state.totalLB < lastTotalLB {
            announcedMilestones = []
            knownLeaders = [:]
        }
        lastTotalLB = state.totalLB

        if state.targetLB > 0 {
            let step = Int(state.totalLB / Self.milestoneStepLB)
            if step > 0, !announcedMilestones.contains(step), state.totalLB < state.targetLB {
                announcedMilestones.insert(step)
                push(.milestone, "the room passed \((Double(step) * Self.milestoneStepLB).groupedLB) LB")
            }
            if state.isMet, !announcedMilestones.contains(Int.max) {
                announcedMilestones.insert(Int.max)
                push(.milestone, "the room moved \(state.targetLB.groupedLB) LB together")
            }
        }

        // New or grown entries become lines. The first read shows only the top few so the floor
        // is not flooded with last hour's history.
        let me = localAlias()?.uppercased()
        let firstRead = knownLeaders.isEmpty
        var announced = 0
        for leader in state.leaders {
            let previous = knownLeaders[leader.id] ?? 0
            knownLeaders[leader.id] = leader.volumeLB
            guard leader.volumeLB > previous, leader.alias.uppercased() != me else { continue }
            if firstRead, announced >= 3 { continue }
            announced += 1
            push(.moved, "\(leader.alias.uppercased()) moved \(leader.volumeLB.groupedLB) LB tonight")
        }
    }

    func noteCrew(lifting names: [String]) {
        let now = Set(names)
        for name in now.subtracting(lastCrewLifting).sorted() {
            push(.joined, "\(name.uppercased()) is lifting right now")
        }
        lastCrewLifting = now
    }

    func noteReaction(_ reaction: LiveRoomReactionEvent) {
        push(.reaction, "\(reaction.senderName) \(reaction.reaction.glyph)")
    }

    func noteOwnContribution(volumeLB: Double) {
        guard volumeLB > 0 else { return }
        push(.you, "you moved \(volumeLB.groupedLB) LB")
    }

    func noteJoined(_ event: LiveEvent) {
        push(.you, "you're in \(event.title)")
    }

    // MARK: - Ring

    private func push(_ kind: LiveActivityEvent.Kind, _ text: String) {
        events.append(LiveActivityEvent(at: Date(), kind: kind, text: text))
        if events.count > Self.capacity { events.removeFirst(events.count - Self.capacity) }
    }
}
