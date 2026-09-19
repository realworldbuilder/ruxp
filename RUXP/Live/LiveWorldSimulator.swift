#if DEBUG
import Foundation
import Observation

/// -RUXPLiveDemo: a believable live world for screenshots and demos. Presence, the shared
/// objective, and the floor all come from this one object so every surface agrees.
///
/// DEBUG only and never the release source. Shipping builds read Game Center; "Counts are
/// real" stands. Every screen this feeds shows a SIMULATED eyebrow.
@Observable
@MainActor
final class LiveWorldSimulator: LivePresenceProviding, SessionObjectiveProviding, LiveActivityProviding {
    /// Set by `-RUXPLiveDemo` or the Settings › Developer toggle (`defaultsKey`, relaunch to apply).
    nonisolated(unsafe) static var isRequested = false
    static let defaultsKey = "ruxp.debugLiveDemo"
    /// Same seed, same night: screenshots are reproducible. `-RUXPLiveDemo <seed>` changes it.
    nonisolated(unsafe) static var seed: UInt64 = 0x5255_5850

    private(set) var snapshot: LiveSnapshot
    private(set) var state: SessionObjectiveState
    private(set) var events: [LiveActivityEvent] = []
    var onSnapshotChanged: ((LiveSnapshot) -> Void)?
    var onStateChanged: ((SessionObjectiveState) -> Void)?

    let seed: UInt64
    private var rng: SplitMix64
    private let schedule: LiveEventProviding
    private var countTask: Task<Void, Never>?
    private var floorTask: Task<Void, Never>?
    private var lastTick = Date()
    private var liftingNow: Double
    private var workoutsToday: Double
    private var contributors: Double
    private var joined: Double
    private var totalLB: Double
    private var localVolumeLB: Double = 0
    private var announcedMilestones: Set<Int> = []

    init(events: LiveEventProviding, seed: UInt64 = LiveWorldSimulator.seed) {
        var rng = SplitMix64(state: seed)
        let now = ScheduledEventService.now()
        let lifting = Self.baseline(at: now) + Double(Int.random(in: -30...30, using: &rng))
        let today = Self.baselineToday(at: now)
        let session = events.activeEvent(at: now)
        let target = session?.objective?.targetLB ?? LiveSessionCatalog.objectiveTargetLB
        var total = 0.0
        if let session {
            // Mid-session at launch: most of the way there, never already met.
            let elapsed = now.timeIntervalSince(session.start) / session.end.timeIntervalSince(session.start)
            total = target * min(0.93, max(0.04, elapsed)) * 0.92
        }

        self.schedule = events
        self.seed = seed
        self.rng = rng
        self.liftingNow = lifting
        self.workoutsToday = today
        self.contributors = lifting * 0.62
        self.joined = lifting * 0.71
        self.totalLB = total
        self.snapshot = LiveSnapshot(liftingNow: Int(lifting), workoutsToday: Int(today), isAvailable: true, updatedAt: now)
        self.state = SessionObjectiveState(targetLB: target, totalLB: total, contributors: Int(lifting * 0.62),
                                           isAvailable: true, updatedAt: now, leaders: [])
        self.announcedMilestones = Set(0...Int(total / ObservedLiveActivity.milestoneStepLB))
    }

    // MARK: - LivePresenceProviding

    func participantCount(for event: LiveEvent) -> Int {
        if event.isSeasonWide { return 248 }
        guard event.isActive(at: ScheduledEventService.now()) else { return 0 }
        return Int(joined)
    }

    func start() {
        guard countTask == nil else { return }
        lastTick = Date()
        countTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(Double.random(in: 3...9, using: &self.rng)))
                guard !Task.isCancelled else { return }
                self.tick()
            }
        }
        floorTask = Task { [weak self] in
            // The first line lands quickly so the floor is never blank on arrival.
            try? await Task.sleep(for: .milliseconds(600))
            for _ in 0..<4 { self?.emitFloorEvent() }
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.nextDelay()))
                guard !Task.isCancelled else { return }
                self.emitFloorEvent()
            }
        }
    }

    func stop() {
        countTask?.cancel(); countTask = nil
        floorTask?.cancel(); floorTask = nil
    }

    // MARK: - SessionObjectiveProviding

    func submit(volumeLB: Double, for event: LiveEvent) async {
        let delta = volumeLB - localVolumeLB
        guard delta > 0 else { return }
        if localVolumeLB == 0 { contributors += 1 }
        localVolumeLB = volumeLB
        totalLB += delta
        publishState()
    }

    // MARK: - Ticks

    /// Lifters drift toward the hour's baseline; the objective grows with them.
    private func tick() {
        let wall = Date()
        let dt = wall.timeIntervalSince(lastTick)
        lastTick = wall
        let now = ScheduledEventService.now()

        let base = Self.baseline(at: now)
        let pull = (base - liftingNow) / 40
        let step = Double(Int.random(in: -4...5, using: &rng))
        liftingNow = max(0, liftingNow + pull + step)
        // Roughly one finish per lifter per hour, so today's count keeps climbing.
        workoutsToday += liftingNow * dt / 3300
        contributors += (liftingNow * 0.62 - contributors) / 20 + Double(Int.random(in: -1...2, using: &rng))
        joined += (liftingNow * 0.71 - joined) / 20 + Double(Int.random(in: -1...2, using: &rng))
        snapshot = LiveSnapshot(liftingNow: Int(liftingNow), workoutsToday: Int(workoutsToday), isAvailable: true, updatedAt: wall)
        onSnapshotChanged?(snapshot)

        if let session = schedule.activeEvent(at: now), !session.isSeasonWide {
            let target = session.objective?.targetLB ?? LiveSessionCatalog.objectiveTargetLB
            let window = max(3600, session.end.timeIntervalSince(session.start))
            let rate = target / window * 1.25 * Double.random(in: 0.5...1.6, using: &rng)
            totalLB += rate * dt
            if state.targetLB != target { announcedMilestones = [] }
            state.targetLB = target
        }
        publishState()
    }

    private func publishState() {
        state = SessionObjectiveState(targetLB: state.targetLB, totalLB: totalLB, contributors: Int(contributors),
                                      isAvailable: true, updatedAt: Date(), leaders: [])
        onStateChanged?(state)
        let stepLB = ObservedLiveActivity.milestoneStepLB
        let milestone = Int(totalLB / stepLB)
        if milestone > 0, !announcedMilestones.contains(milestone) {
            announcedMilestones.insert(milestone)
            let text = totalLB >= state.targetLB && Double(milestone) * stepLB >= state.targetLB
                ? "the room moved \(state.targetLB.groupedLB) LB together"
                : "the room passed \((Double(milestone) * stepLB).groupedLB) LB"
            push(.milestone, text)
        }
    }

    /// Lifters by local hour: a small morning bump, the evening peak, nearly empty at 4 AM.
    private static func baseline(at date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
        func bump(center: Double, width: Double) -> Double {
            let d = min(abs(hour - center), 24 - abs(hour - center))
            return exp(-(d * d) / (2 * width * width))
        }
        return 140 + 1100 * bump(center: 18.5, width: 3.2) + 380 * bump(center: 7, width: 1.5)
    }

    private static func baselineToday(at date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
        return 900 * hour
    }

    // MARK: - The floor

    /// Log-normal gaps: mostly a few seconds, sometimes a long lull, never a metronome.
    private func nextDelay() -> Double {
        let u1 = max(Double.random(in: 0..<1, using: &rng), 1e-9)
        let u2 = Double.random(in: 0..<1, using: &rng)
        let gaussian = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        return min(14, max(1.5, exp(log(4.5) + 0.6 * gaussian)))
    }

    private enum FloorKind: CaseIterable { case set, joined, started, finished, training, duration, moved, reaction }

    private func emitFloorEvent() {
        let kind = pick([(FloorKind.set, 38), (.joined, 12), (.started, 10), (.finished, 9),
                         (.training, 7), (.duration, 6), (.moved, 8), (.reaction, 2)])
        switch kind {
        case .set:
            let lift = pick(Self.exercises.map { ($0, $0.weight) })
            let reps = Int.random(in: lift.reps, using: &rng)
            if let load = lift.load(using: &rng) {
                push(.set, "\(handle()) hit \(lift.name) — \(load) × \(reps)")
            } else {
                push(.set, "\(handle()) hit \(lift.name) — \(reps) reps")
            }
        case .joined:
            push(.joined, "someone in \(city()) just joined")
        case .started:
            push(.joined, "someone just started a workout in \(city())")
        case .finished:
            let n = pick([(1, 6), (2, 5), (3, 4), (Int.random(in: 4...9, using: &rng), 4), (Int.random(in: 10...24, using: &rng), 3)])
            push(.finished, n == 1 ? "someone just finished" : "\(n) lifters just finished")
        case .training:
            let group = pick([("chest", 9), ("back", 8), ("legs", 9), ("shoulders", 6), ("arms", 6), ("glutes", 4), ("core", 3)])
            let n = Int(liftingNow * Double.random(in: 0.04...0.11, using: &rng))
            push(.training, "\(max(2, n)) people are training \(group) right now")
        case .duration:
            let minutes = pick([(Int.random(in: 35...60, using: &rng), 5), (Int.random(in: 61...95, using: &rng), 4), (Int.random(in: 96...150, using: &rng), 2)])
            push(.training, "someone has been lifting for \(minutes) minutes")
        case .moved:
            let lb = Double(Int.random(in: 40...280, using: &rng) * 100)
            push(.moved, "\(handle()) moved \(lb.groupedLB) LB tonight")
        case .reaction:
            let glyph = pick([("🔥", 5), ("🫡", 3), ("💀", 2), ("W", 3)])
            push(.reaction, "\(handle()) \(glyph)")
        }
    }

    private func push(_ kind: LiveActivityEvent.Kind, _ text: String) {
        events.append(LiveActivityEvent(at: Date(), kind: kind, text: text))
        if events.count > ObservedLiveActivity.capacity { events.removeFirst(events.count - ObservedLiveActivity.capacity) }
    }

    // MARK: - Tables

    private func pick<T>(_ weighted: [(T, Int)]) -> T {
        let total = weighted.reduce(0) { $0 + $1.1 }
        var roll = Int.random(in: 0..<max(1, total), using: &rng)
        for (item, weight) in weighted {
            roll -= weight
            if roll < 0 { return item }
        }
        return weighted[weighted.count - 1].0
    }

    private func handle() -> String { pick(Self.handles.map { ($0, 1) }) }
    private func city() -> String { pick(Self.cities) }

    private struct Lift {
        enum Load { case barbell(ClosedRange<Int>), stepped(ClosedRange<Int>, step: Int), bodyweight }
        let name: String
        let load: Load
        let reps: ClosedRange<Int>
        let weight: Int

        /// Plate math for barbells; round numbers for dumbbells and stacks.
        func load(using rng: inout SplitMix64) -> Int? {
            switch load {
            case .bodyweight:
                return nil
            case .stepped(let range, let step):
                let steps = (range.upperBound - range.lowerBound) / step
                return range.lowerBound + Int.random(in: 0...steps, using: &rng) * step
            case .barbell(let range):
                let plates = [95, 115, 135, 155, 185, 205, 225, 245, 275, 295, 315, 335, 365, 385, 405, 455, 495]
                    .filter { range.contains($0) }
                return plates.randomElement(using: &rng)
            }
        }
    }

    private static let exercises: [Lift] = [
        Lift(name: "Bench Press", load: .barbell(95...315), reps: 3...12, weight: 14),
        Lift(name: "Squat", load: .barbell(135...405), reps: 3...10, weight: 12),
        Lift(name: "Deadlift", load: .barbell(185...495), reps: 1...8, weight: 11),
        Lift(name: "Curls", load: .stepped(20...50, step: 5), reps: 8...15, weight: 9),
        Lift(name: "Lat Pulldown", load: .stepped(90...200, step: 10), reps: 8...12, weight: 9),
        Lift(name: "Shoulder Press", load: .stepped(65...185, step: 10), reps: 5...12, weight: 8),
        Lift(name: "Leg Press", load: .stepped(180...630, step: 90), reps: 8...15, weight: 8),
        Lift(name: "Rows", load: .barbell(95...225), reps: 6...12, weight: 7),
        Lift(name: "Incline Bench", load: .barbell(95...225), reps: 6...12, weight: 5),
        Lift(name: "RDL", load: .barbell(135...315), reps: 6...12, weight: 5),
        Lift(name: "Hip Thrust", load: .barbell(135...365), reps: 8...15, weight: 4),
        Lift(name: "Overhead Press", load: .barbell(95...155), reps: 3...10, weight: 4),
        Lift(name: "Leg Curl", load: .stepped(60...150, step: 10), reps: 8...15, weight: 3),
        Lift(name: "Lateral Raise", load: .stepped(10...30, step: 5), reps: 10...20, weight: 3),
        Lift(name: "Tricep Pushdown", load: .stepped(40...100, step: 10), reps: 10...15, weight: 3),
        Lift(name: "Pull-ups", load: .bodyweight, reps: 5...12, weight: 3),
        Lift(name: "Dips", load: .bodyweight, reps: 8...15, weight: 2),
        Lift(name: "Front Squat", load: .barbell(95...225), reps: 3...8, weight: 2),
        Lift(name: "Face Pulls", load: .stepped(30...70, step: 10), reps: 12...20, weight: 2),
        Lift(name: "Zercher Squat", load: .barbell(95...185), reps: 5...8, weight: 1),
        Lift(name: "Pendlay Row", load: .barbell(95...185), reps: 5...8, weight: 1)
    ]

    private static let handles = [
        "ronin33", "heavyhands", "ironlung", "plate_pusher", "deadlift_dan", "squatqueen", "benchmark_",
        "kai.lifts", "nightshift_nate", "marcus_moves", "jade.pr", "tobi_tank", "gymrat_gio", "rack_city",
        "5am_sam", "pr_hunter", "quadfather", "delt_force", "liftlikelina", "oneMoreRep", "chalk_dust",
        "barbell_beth", "lowbarluke", "sumo_sue", "hypertrophy_hal", "cablecrew", "rest_pause", "tempo_tim",
        "spotter_needed", "big_dawg", "mia_moves", "grip_it", "legday_leo", "volume_v", "deload_diane",
        "rowbot", "ghost_lifter", "wrist_wraps", "bulking_ben", "cutting_cara"
    ]

    private static let cities: [(String, Int)] = [
        ("New York", 12), ("Los Angeles", 10), ("Chicago", 10), ("Atlanta", 9), ("Houston", 9), ("Dallas", 8),
        ("Miami", 8), ("Phoenix", 7), ("Austin", 7), ("Denver", 6), ("Seattle", 6), ("Philadelphia", 6),
        ("Nashville", 5), ("Boston", 5), ("San Diego", 5), ("Toronto", 5), ("Detroit", 4), ("Minneapolis", 4),
        ("Charlotte", 4), ("Las Vegas", 4), ("Tampa", 4), ("London", 4), ("Portland", 3), ("Columbus", 3),
        ("Kansas City", 3), ("Salt Lake City", 3), ("Sydney", 3), ("Mexico City", 3), ("Berlin", 2),
        ("São Paulo", 2), ("Honolulu", 1)
    ]
}

/// Tiny seeded generator so a demo night replays the same way.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
#endif
