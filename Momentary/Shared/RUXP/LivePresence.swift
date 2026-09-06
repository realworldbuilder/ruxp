import Foundation
import Observation

// MARK: - Snapshot

struct LiveSnapshot: Equatable {
    var liftingNow: Int
    var workoutsLastHour: Int
    var workoutsToday: Int
    /// People who trained since 17:00 local (or today, before 17:00).
    var trainedTonight: Int
    var isEvening: Bool
    /// True when the numbers are generated locally rather than from a backend.
    var isDemo: Bool

    var trainedTonightLabel: String {
        isEvening ? "people trained tonight" : "people trained today"
    }

    static let empty = LiveSnapshot(liftingNow: 0, workoutsLastHour: 0, workoutsToday: 0, trainedTonight: 0, isEvening: false, isDemo: true)
}

// MARK: - Provider

/// The feeling RUXP sells: other people are doing this with you.
/// A real-time backend should implement this protocol; nothing else in the app should care.
@MainActor
protocol LivePresenceProviding: AnyObject {
    var snapshot: LiveSnapshot { get }
    func start()
    func stop()
    func participantCount(for event: LiveEvent) -> Int
}

// MARK: - Simulated provider

/// DEMO DATA. Generates believable presence numbers from a time-of-day curve plus a
/// gentle random walk so the digits move. It proves the UX; it is not real production data.
@Observable
@MainActor
final class SimulatedLivePresence: LivePresenceProviding {
    private(set) var snapshot: LiveSnapshot = .empty

    private let tickInterval: TimeInterval
    private var task: Task<Void, Never>?
    private var drift: Double = 0
    private var generator = SystemRandomNumberGenerator()

    /// - Parameter tickInterval: seconds between updates (phone ≈ 4 s, watch ≈ 15 s).
    init(tickInterval: TimeInterval = 4) {
        self.tickInterval = tickInterval
        refresh()
    }

    func start() {
        guard task == nil else { return }
        refresh()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.tickInterval ?? 4))
                await MainActor.run { self?.tick() }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func participantCount(for event: LiveEvent) -> Int {
        let now = ScheduledEventService.now()
        if event.isSeasonWide { return Int(Double(snapshot.workoutsToday) * 6.5) }
        if event.isActive(at: now) { return Int(Double(snapshot.liftingNow) * 0.34) }
        return Int(Double(Self.baseline(at: event.start)) * 0.12)
    }

    // MARK: - Curve

    private func tick() {
        // Random walk that decays back toward the curve so numbers wander but never run away.
        let step = Double.random(in: -0.004...0.004, using: &generator)
        drift = drift * 0.9 + step
        refresh()
    }

    private func refresh() {
        let now = ScheduledEventService.now()
        let base = Double(Self.baseline(at: now))
        let liftingNow = max(120, Int(base * (1 + drift)))
        let hour = Self.fractionalHour(now)
        let isEvening = hour >= 17

        var workoutsToday = 0.0
        var trainedTonight = 0.0
        var h = 0.0
        while h < hour {
            let f = Double(Self.baseline(at: now, hourOverride: h))
            workoutsToday += f / 25 * 0.5
            if h >= 17 { trainedTonight += f * 0.35 * 0.5 }
            h += 0.5
        }
        if !isEvening { trainedTonight = workoutsToday * 1.6 }

        snapshot = LiveSnapshot(
            liftingNow: liftingNow,
            workoutsLastHour: max(1, liftingNow / 25),
            workoutsToday: Int(workoutsToday),
            trainedTonight: Int(trainedTonight),
            isEvening: isEvening,
            isDemo: true
        )
    }

    private static func fractionalHour(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    /// Deterministic "lifting now" baseline for a moment in time.
    static func baseline(at date: Date, hourOverride: Double? = nil) -> Int {
        let h = hourOverride ?? fractionalHour(date)
        func bump(center: Double, width: Double, height: Double) -> Double {
            let d = h - center
            return height * exp(-(d * d) / (2 * width * width))
        }
        var value = 1800 + bump(center: 7, width: 1.5, height: 5200) + bump(center: 18, width: 2.5, height: 12200)
        let weekday = Calendar.current.component(.weekday, from: date) // 1 = Sunday, 6 = Friday
        if weekday == 1 || weekday == 7 { value *= 1.15 }
        if weekday == 6 && h >= 17 { value *= 1.3 }
        return Int(value)
    }
}
