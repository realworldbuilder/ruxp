import Foundation
import Observation
import os

/// Your crew: Game Center friends who lift. Nobody is expecting you until this exists.
/// Reads the crew boards, pays CREW WEEK once per week when everyone showed up, and keeps the
/// last known crew on disk (Documents/crew.json) so Home never goes blank offline.
/// Rule: show who is in, never who is out.
@Observable
@MainActor
final class CrewService {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "CrewService")

    private(set) var snapshot: CrewSnapshot?
    private(set) var lastError: String?
    /// Fired after every successful read (the world ledger listens).
    var onSnapshotChanged: (() -> Void)?

    private let gameCenter: GameCenterService
    private let progression: ProgressionService
    private let season: Season
    private let fileURL: URL
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?
    private var refreshing = false
    private let calendar = Calendar.ruxpWeek

    #if DEBUG
    /// -RUXPCrewDemo [room|last|complete|empty]: seed a crew when Game Center is off.
    nonisolated(unsafe) static var demoMode: String?
    #endif

    init(gameCenter: GameCenterService, progression: ProgressionService, season: Season,
         pollInterval: Duration = .seconds(180), fileURL: URL? = nil) {
        self.gameCenter = gameCenter
        self.progression = progression
        self.season = season
        self.pollInterval = pollInterval
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = fileURL ?? docs.appendingPathComponent("crew.json")
        load()
        #if DEBUG
        if let mode = Self.demoMode { snapshot = Self.demo(mode: mode, weekKey: currentWeekKey) }
        #endif
    }

    // MARK: - Derived

    var currentWeekKey: String { calendar.weekKey(for: ScheduledEventService.now()) }
    var previousWeekKey: String {
        let start = calendar.startOfWeek(for: ScheduledEventService.now())
        return calendar.weekKey(for: calendar.date(byAdding: .day, value: -7, to: start) ?? start)
    }
    var localThisWeek: Int {
        #if DEBUG
        // Demo modes decide whether "you" are in, so every copy variant can be captured.
        switch Self.demoMode {
        case "last": return 0
        case "complete": return max(1, progression.workoutsThisWeek)
        default: break
        }
        #endif
        return progression.workoutsThisWeek
    }


    /// Active members only.
    var crew: [CrewMember] { (snapshot?.members ?? []).filter(\.isActive) }
    var isEmpty: Bool { crew.isEmpty }
    var liftingNow: [CrewMember] { crew.filter(\.liftingNow) }
    var inThisWeek: [CrewMember] { crew.filter { $0.thisWeek > 0 } }
    var state: CrewState? { snapshot.map { CrewState.from($0, localThisWeek: localThisWeek) } }
    var size: Int { crew.count + 1 }
    var inCount: Int { inThisWeek.count + (localThisWeek > 0 ? 1 : 0) }
    var remaining: Int { max(0, size - inCount) }
    var goalMet: Bool { state?.met ?? false }
    var youAreLast: Bool { !isEmpty && remaining == 1 && localThisWeek == 0 }
    /// Snapshot is from an earlier week: counts are stale until the next read.
    var isStale: Bool { snapshot.map { $0.weekKey != currentWeekKey } ?? true }

    /// The one line under the names.
    var line: String {
        if isEmpty { return "Nobody in your crew yet. Friends who lift show up here." }
        if goalMet { return "Crew week complete. +\(ProgressionRules.crewWeekXP) XP for everyone." }
        if crew.count < ProgressionRules.crewMinimumOthers {
            return youAreLast ? "You're the last one. Get in." : "Room for one more."
        }
        if youAreLast { return "You're the last one. Get in." }
        return remaining == 1 ? "Room for one more." : "Room for \(remaining) more."
    }

    /// "MARCUS is lifting right now" / "MARCUS and JADE are lifting right now"
    var liftingLine: String? {
        let names = liftingNow.map(\.displayName)
        switch names.count {
        case 0: return nil
        case 1: return "\(names[0]) is lifting right now"
        case 2: return "\(names[0]) and \(names[1]) are lifting right now"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) more are lifting right now"
        }
    }

    /// "You're the 4th in your crew this week." for the reward screen.
    func completionLine(paid: Bool) -> String? {
        guard !isEmpty else { return nil }
        if paid { return "Crew week complete. +\(ProgressionRules.crewWeekXP) XP for everyone who trained." }
        if goalMet { return "Crew week complete. Everyone showed up." }
        let n = max(1, inCount)
        return "You're the \(Self.ordinal(n)) in your crew this week. \(line)"
    }

    // MARK: - Lifecycle

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshNow() { Task { await refresh() } }

    /// After a rewarded completion: tell friends, then look again (your workout may complete the crew week).
    func noteRewardedCompletion() {
        Task {
            await gameCenter.submitCrewWeek(count: progression.workoutsThisWeek)
            await refresh()
        }
    }

    @discardableResult
    func refresh() async -> CrewState? {
        #if DEBUG
        if Self.demoMode != nil { settle(); return state }
        #endif
        guard gameCenter.isActive, !refreshing else { return state }
        refreshing = true
        defer { refreshing = false }
        guard let fresh = await gameCenter.loadCrew(season: season) else {
            lastError = "Crew boards unavailable"
            return state
        }
        lastError = nil
        snapshot = fresh
        persist()
        settle()
        onSnapshotChanged?()
        return state
    }

    // MARK: - Settlement

    /// Pay CREW WEEK for this week when everyone is in; pay last week on the first read after the
    /// week rolls (the previous occurrence still holds everyone's counts).
    private func settle() {
        guard let snapshot else { return }
        if goalMet, !progression.crewWeekBonusPaid(weekKey: currentWeekKey) {
            progression.rewardCrewWeek(weekKey: currentWeekKey)
        }
        let lastCrew = snapshot.members.filter { $0.lastWeek > 0 || $0.thisWeek > 0 }
        let lastMet = lastCrew.count >= ProgressionRules.crewMinimumOthers
            && lastCrew.allSatisfy { $0.lastWeek > 0 }
            && snapshot.localLastWeek > 0
        if lastMet, !progression.crewWeekBonusPaid(weekKey: previousWeekKey) {
            progression.rewardCrewWeek(weekKey: previousWeekKey)
        }
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save crew: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try decoder.decode(CrewSnapshot.self, from: Data(contentsOf: fileURL))
        } catch {
            Self.logger.error("Failed to load crew: \(error)")
        }
    }

    // MARK: - Helpers

    static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)th"
    }

    #if DEBUG
    /// room: MARCUS and JADE in, TOBI not yet → "Room for one more."  last: everyone in but you.
    /// final: everyone else in, you as you really are (finish a workout to complete the week).
    /// complete: everyone in.  empty: nobody. KAI has been quiet for weeks and is not in the crew.
    private static func demo(mode: String, weekKey: String) -> CrewSnapshot {
        func m(_ id: String, _ name: String, _ level: Int, _ tw: Int, _ lw: Int, _ live: Bool) -> CrewMember {
            CrewMember(id: id, displayName: name, level: level, thisWeek: tw, lastWeek: lw, liftingNow: live)
        }
        let members: [CrewMember]
        switch mode {
        case "empty": members = []
        case "last", "final", "complete": members = [m("d1", "MARCUS", 9, 2, 3, mode != "complete"), m("d2", "JADE", 5, 1, 2, false), m("d3", "TOBI", 3, 1, 1, false), m("d4", "KAI", 2, 0, 0, false)]

        default: members = [m("d1", "MARCUS", 9, 2, 3, true), m("d2", "JADE", 5, 1, 2, false), m("d3", "TOBI", 3, 0, 1, false), m("d4", "KAI", 2, 0, 0, false)]
        }
        return CrewSnapshot(members: members, localLastWeek: 1, weekKey: weekKey, fetchedAt: Date())
    }
    #endif
}
