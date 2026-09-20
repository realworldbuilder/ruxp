import Foundation
import Observation

/// Quests: NEW GAME (the first workout in three steps) and STAGE 2 (the mechanics), cleared
/// from hooks that already fire. Chained in `RUXPApp.init` next to the composer. State lives on
/// `PlayerProgress`; this service only decides which quests a signal satisfies and asks
/// `ProgressionService` to record and pay. Inactive until `activate` has run, so the progression
/// rebuild on first upgrade never pays quest XP for history.
@Observable
@MainActor
final class QuestService {
    struct Entry: Identifiable {
        let chain: QuestChain
        let quest: Quest
        /// 1-based position inside its chain.
        let number: Int
        let completion: QuestCompletion?
        var id: QuestID { quest.id }
        var isCleared: Bool { completion != nil }
    }

    private let progression: ProgressionService
    private(set) var isActive = false
    /// `clearQuests` fires `onRewardChanged`, which lands back here; ignore that one bounce.
    private var evaluating = false
    /// Developer row.
    private(set) var lastSignal = "none"

    init(progression: ProgressionService) {
        self.progression = progression
    }

    // MARK: - Derived (read through `progression.progress`, one observed source)

    var entries: [Entry] {
        QuestCatalog.chains.flatMap { chain in
            chain.quests.enumerated().map { index, quest in
                Entry(chain: chain, quest: quest, number: index + 1, completion: progression.questCompletion(quest.id))
            }
        }
    }

    func entries(in chain: QuestChain) -> [Entry] { entries.filter { $0.chain.id == chain.id } }

    func count(in chain: QuestChain) -> (cleared: Int, total: Int) {
        let rows = entries(in: chain)
        return (rows.filter(\.isCleared).count, rows.count)
    }

    func isCleared(_ chain: QuestChain) -> Bool { progression.isChainCleared(chain) }
    func isUnlocked(_ chain: QuestChain) -> Bool { progression.isChainUnlocked(chain) }

    /// The chain the player is on: first not cleared whose requirement is met.
    var activeChain: QuestChain? {
        QuestCatalog.chains.first { !isCleared($0) && isUnlocked($0) }
    }

    /// First uncleared quest of the active chain; what Home and the workout screen feature.
    var featured: Entry? {
        guard let chain = activeChain else { return nil }
        return entries(in: chain).first { !$0.isCleared }
    }

    var isChainVisible: Bool { isActive && featured != nil }
    var isAllClear: Bool { QuestCatalog.chains.allSatisfy(isCleared) }
    var clearedCount: Int { entries.filter(\.isCleared).count }
    var totalCount: Int { QuestCatalog.all.count }

    // MARK: - Lifecycle

    /// Once, after the progression rebuild and before any hook can fire. Both flags come from
    /// `store.index`: any workout stored at all, and any with a recorded moment.
    func activate(hasAnyWorkout: @autoclosure () -> Bool, hasVoiceMoment: @autoclosure () -> Bool,
                  now: Date = ScheduledEventService.now()) {
        if progression.progress.questsBackfilledAt == nil {
            let ids = QuestEvaluator.backfill(progress: progression.progress,
                                              hasAnyWorkout: hasAnyWorkout(), hasVoiceMoment: hasVoiceMoment())
            progression.backfillQuests(ids, now: now)
        }
        isActive = true
    }

    // MARK: - Intake

    func noteWorkoutStarted(_ session: WorkoutSession) {
        clear([.pressStart], workoutID: session.id, signal: "started")
    }

    func noteMomentAdded(_ moment: Moment, workoutID: UUID) {
        clear([.sayItOutLoud], workoutID: workoutID, signal: "moment")
    }

    /// Fires again when a PR bonus or CREW WEEK lands; the ledger makes repeats harmless.
    func noteReward(_ summary: WorkoutRewardSummary) {
        clear(QuestEvaluator.satisfied(by: summary), workoutID: summary.workoutID, signal: "reward")
    }

    private func clear(_ ids: Set<QuestID>, workoutID: UUID, signal: String) {
        guard isActive, !evaluating else { return }
        // Locked chains are left in: recording a step may unlock them within the same call.
        let fresh = QuestCatalog.all.map(\.id).filter { ids.contains($0) && progression.questCompletion($0) == nil }
        guard !fresh.isEmpty else { return }
        evaluating = true
        defer { evaluating = false }
        lastSignal = "\(signal) → \(fresh.map(\.rawValue).joined(separator: ", "))"
        progression.clearQuests(fresh, workoutID: workoutID)
    }

    #if DEBUG
    /// -RUXPQuests <0…7> or <id,id,…>: exactly those quests cleared, as backfilled (no XP).
    /// Persisted, so it is a real state, not a mock.
    nonisolated(unsafe) static var debugPreset: Set<QuestID>?

    static func parseDebugPreset(_ raw: String) -> Set<QuestID> {
        if let n = Int(raw) { return Set(QuestCatalog.all.prefix(max(0, n)).map(\.id)) }
        return Set(raw.split(separator: ",").compactMap { QuestID(rawValue: String($0).trimmingCharacters(in: .whitespaces)) })
    }

    func applyDebugPreset() {
        guard let ids = Self.debugPreset else { return }
        progression.debugResetQuests()
        progression.backfillQuests(ids)
    }

    func debugReset(hasAnyWorkout: Bool, hasVoiceMoment: Bool) {
        progression.debugResetQuests()
        isActive = false
        activate(hasAnyWorkout: hasAnyWorkout, hasVoiceMoment: hasVoiceMoment)
    }

    var debugDescription: String {
        let when = progression.progress.questsBackfilledAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "never"
        return "\(clearedCount)/\(totalCount) · backfilled \(when) · \(lastSignal)"
    }
    #endif
}
