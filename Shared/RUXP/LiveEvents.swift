import Foundation

// MARK: - Model

enum LiveEventKind: String, Codable {
    case fridayNight
    case sundayReset
    case season
}

struct LiveEvent: Identifiable, Equatable {
    let kind: LiveEventKind
    let title: String
    let subtitle: String
    let description: String
    let start: Date
    let end: Date
    let xpReward: Int
    let isSeasonWide: Bool

    /// Stable per occurrence: "fridayNight-2026-09-11".
    var id: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return "\(kind.rawValue)-\(f.string(from: start))"
    }

    func isActive(at date: Date = Date()) -> Bool {
        date >= start && date < end
    }

    func isUpcoming(at date: Date = Date()) -> Bool {
        date < start
    }

    /// True when a workout with this start/end overlaps the event window.
    func covers(start workoutStart: Date, end workoutEnd: Date?) -> Bool {
        let workoutEnd = workoutEnd ?? workoutStart
        return workoutStart < end && workoutEnd >= start
    }

    /// "FRI 5PM", "TODAY 5PM", "SUN"
    func startLabel(now: Date = Date()) -> String {
        let cal = Calendar.current
        let time = DateFormatter()
        time.dateFormat = cal.component(.minute, from: start) == 0 ? "ha" : "h:mma"
        let timeString = time.string(from: start).uppercased()
        if cal.isDate(start, inSameDayAs: now) { return "TODAY \(timeString)" }
        if cal.isDateInTomorrow(start) { return "TOMORROW \(timeString)" }
        let day = DateFormatter()
        day.dateFormat = "EEE"
        return "\(day.string(from: start).uppercased()) \(timeString)"
    }
}

// MARK: - Provider

/// The app asks one question: what is happening right now?
/// Replace `ScheduledEventService` with a backend-driven implementation later.
protocol LiveEventProviding {
    func activeEvent(at date: Date) -> LiveEvent?
    func nextEvent(at date: Date) -> LiveEvent?
    func seasonEvent() -> LiveEvent
    /// Timed events (active or upcoming) that overlap the given range. Used to award bonuses.
    func events(overlapping start: Date, end: Date) -> [LiveEvent]
}

extension LiveEventProviding {
    /// What the Home screen should show: live first, then the next timed event, then the season theme.
    func featuredEvent(at date: Date = Date()) -> LiveEvent {
        activeEvent(at: date) ?? nextEvent(at: date) ?? seasonEvent()
    }
}

/// Recurring events computed from the clock. No backend.
struct ScheduledEventService: LiveEventProviding {
    var season: Season = SeasonCatalog.current
    var calendar: Calendar = .current

    #if DEBUG
    /// Developer override so the event flow can be exercised on any day.
    nonisolated(unsafe) static var clockOverride: Date?
    #endif

    static func now() -> Date {
        #if DEBUG
        if let override = clockOverride { return override }
        #endif
        return Date()
    }

    func activeEvent(at date: Date) -> LiveEvent? {
        timedEvents(around: date).first { $0.isActive(at: date) }
    }

    func nextEvent(at date: Date) -> LiveEvent? {
        timedEvents(around: date)
            .filter { $0.isUpcoming(at: date) }
            .sorted { $0.start < $1.start }
            .first
    }

    func seasonEvent() -> LiveEvent {
        LiveEvent(
            kind: .season,
            title: season.name,
            subtitle: season.displayName,
            description: "\(season.tagline) \(season.goalWorkouts) workouts. Finish the season.",
            start: season.start,
            end: season.end,
            xpReward: 0,
            isSeasonWide: true
        )
    }

    func events(overlapping start: Date, end: Date) -> [LiveEvent] {
        timedEvents(around: start).filter { $0.covers(start: start, end: end) }
    }

    // MARK: - Schedule

    /// Friday Night and Sunday Reset occurrences for the week containing `date` and the following week.
    private func timedEvents(around date: Date) -> [LiveEvent] {
        var events: [LiveEvent] = []
        let weekStart = Calendar.ruxpWeek.startOfWeek(for: date)
        for weekOffset in -1...1 {
            guard let base = calendar.date(byAdding: .day, value: 7 * weekOffset, to: weekStart) else { continue }
            if let friday = fridayNight(weekStarting: base) { events.append(friday) }
            if let sunday = sundayReset(weekStarting: base) { events.append(sunday) }
        }
        return events.sorted { $0.start < $1.start }
    }

    private func fridayNight(weekStarting monday: Date) -> LiveEvent? {
        guard let fridayDay = calendar.date(byAdding: .day, value: 4, to: monday) else { return nil }
        let dayStart = calendar.startOfDay(for: fridayDay)
        guard let start = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: dayStart),
              let end = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        return LiveEvent(
            kind: .fridayNight,
            title: "FRIDAY NIGHT",
            subtitle: "Friday evening",
            description: "Train tonight. Earn bonus XP.",
            start: start,
            end: end,
            xpReward: 500,
            isSeasonWide: false
        )
    }

    private func sundayReset(weekStarting monday: Date) -> LiveEvent? {
        guard let sundayDay = calendar.date(byAdding: .day, value: 6, to: monday) else { return nil }
        let start = calendar.startOfDay(for: sundayDay)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return LiveEvent(
            kind: .sundayReset,
            title: "SUNDAY RESET",
            subtitle: "All day Sunday",
            description: "Complete a workout Sunday. Start the week ahead.",
            start: start,
            end: end,
            xpReward: 250,
            isSeasonWide: false
        )
    }
}
