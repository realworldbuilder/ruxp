import Foundation
import Observation

/// Turns hooks that already fire into `CommunityMoment`s, applies `MomentPolicy`, dedups, and
/// hands the survivors to the publisher. Never polls. Chained in `RUXPApp.init` next to the
/// floor: join, presence, objective, PRs, reward.
@Observable
@MainActor
final class CommunityMomentComposer {
    let events: LiveEventProviding
    var publisher: CommunityPublishing
    var sharingProvider: () -> CommunitySharing = { CommunitySharing() }
    var aliasProvider: () -> String? = { nil }

    /// The last few that left the phone, newest last (Developer rows).
    private(set) var recent: [CommunityMoment] = []
    private(set) var publishedCount = 0
    private(set) var suppressedCount = 0

    private var seen: Set<String> = []
    private var lastLifters: [String: Int] = [:]
    private var lastVolume: [String: Double] = [:]
    private var prsByWorkout: [UUID: Int] = [:]

    init(events: LiveEventProviding, publisher: CommunityPublishing) {
        self.events = events
        self.publisher = publisher
    }

    // MARK: - Intake

    func noteJoined(_ event: LiveEvent, liftingNow: Int?) {
        var moment = base(.sessionJoined, id: "sessionJoined:\(event.id)", event: event)
        moment.liftingNow = liftingNow
        emit(moment)
    }

    /// Lifters in the active occurrence, read from presence. Posts once per threshold.
    func noteLifters(_ count: Int, for event: LiveEvent) {
        let previous = lastLifters[event.id] ?? 0
        lastLifters[event.id] = count
        guard let threshold = MomentPolicy.lifterMilestone(previous: previous, current: count) else { return }
        var moment = base(.lifterMilestone, id: "lifterMilestone:\(event.id):\(threshold)", event: event)
        moment.lifters = count
        emit(moment)
    }

    /// Tonight's total, read from the objective board. Posts once per 250K step.
    func noteObjective(_ state: SessionObjectiveState, now: Date = ScheduledEventService.now()) {
        guard state.isAvailable, let event = events.activeEvent(at: now), !event.isSeasonWide else { return }
        let previous = lastVolume[event.id] ?? 0
        lastVolume[event.id] = state.totalLB
        // A window rollover drops the total; forget the old occurrence's thresholds.
        if state.totalLB < previous { return }
        guard let step = MomentPolicy.volumeMilestone(previous: previous, current: state.totalLB) else { return }
        var moment = base(.volumeMilestone, id: "volumeMilestone:\(event.id):\(Int(step))", event: event)
        moment.totalLB = state.totalLB
        moment.targetLB = state.targetLB
        moment.lifters = state.contributors
        emit(moment)
    }

    /// PRs paid for one workout, with the XP each paid. Capped like PR XP.
    func notePersonalRecords(_ records: [PRRecord], workoutID: UUID, xp: [Int], now: Date = ScheduledEventService.now()) {
        let already = prsByWorkout[workoutID] ?? 0
        let room = max(0, MomentPolicy.maxPRsPerWorkout - already)
        let event = events.activeEvent(at: now).flatMap { $0.isSeasonWide ? nil : $0 }
        for (index, record) in records.prefix(room).enumerated() {
            var moment = base(.personalRecord, id: "personalRecord:\(workoutID.uuidString):\(record.exercise)", event: event)
            moment.exercise = record.exercise
            moment.weightLB = record.weight
            moment.reps = record.reps
            moment.xp = index < xp.count ? xp[index] : nil
            emit(moment)
        }
        prsByWorkout[workoutID] = already + min(room, records.count)
    }

    /// Level-ups and completed sessions ride on the reward summary; it fires again when a PR
    /// bonus lands, so ids carry the workout.
    func noteReward(_ summary: WorkoutRewardSummary, now: Date = ScheduledEventService.now()) {
        if summary.didLevelUp {
            var moment = base(.levelUp, id: "levelUp:\(summary.workoutID.uuidString):\(summary.levelAfter)", event: nil)
            moment.level = summary.levelAfter
            moment.xp = summary.totalXP
            emit(moment)
        }
        for id in summary.completedSessionIDs ?? [] {
            guard let event = events.event(id: id) else { continue }
            var moment = base(.sessionComplete, id: "sessionComplete:\(id):\(summary.workoutID.uuidString)", event: event)
            moment.xp = summary.eventAwards.first { $0.eventID == id }?.amount
            emit(moment)
        }
    }

    // MARK: - Policy

    private func base(_ kind: CommunityMoment.Kind, id: String, event: LiveEvent?) -> CommunityMoment {
        let community = event.flatMap { events.community(for: $0) }
        let audience = MomentPolicy.audience(for: kind, sharing: sharingProvider(), hasCommunity: community?.discord != nil)
        var moment = CommunityMoment(id: id, kind: kind, at: ScheduledEventService.now(), audience: audience)
        moment.eventID = event?.id
        moment.eventTitle = event?.title
        moment.guildID = community?.discord?.guildID
        moment.channelID = community?.discord?.channelID
        moment.joinURL = event.map { AppLinks.join(eventID: $0.id) } ?? AppLinks.joinLive
        if MomentPolicy.isPlayerMoment(kind), audience.leavesTheDevice { moment.alias = aliasProvider() }
        return moment
    }

    private func emit(_ moment: CommunityMoment) {
        guard seen.insert(moment.id).inserted else { return }
        guard moment.audience.leavesTheDevice else { suppressedCount += 1; return }
        publishedCount += 1
        recent.append(moment)
        if recent.count > 10 { recent.removeFirst(recent.count - 10) }
        publisher.publish(moment)
    }

    #if DEBUG
    /// Developer: one aggregate moment through the whole path, no workout needed.
    func sendTestMoment(now: Date = ScheduledEventService.now()) {
        let event = events.featuredEvent(at: now)
        var moment = base(.lifterMilestone, id: "test:\(UUID().uuidString)", event: event.isSeasonWide ? nil : event)
        moment.lifters = 10
        moment.audience = .event
        publishedCount += 1
        recent.append(moment)
        publisher.publish(moment)
    }
    #endif
}
