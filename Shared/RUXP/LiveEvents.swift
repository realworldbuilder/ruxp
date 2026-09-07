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

    /// "Ends in 2h 14m", "Ends in 40m", "Ended".
    func endsInLabel(now: Date = Date()) -> String {
        let remaining = Int(end.timeIntervalSince(now))
        guard remaining > 0 else { return "Ended" }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 { return "Ends in \(hours)h \(minutes)m" }
        return "Ends in \(max(1, minutes))m"
    }

    /// Game Center hooks for timed events. Season-wide events have none.
    var gameCenterLeaderboardID: String? {
        isSeasonWide ? nil : GameCenterCatalog.liveSessions
    }

    var gameCenterAchievementID: String? {
        isSeasonWide ? nil : GameCenterCatalog.liveFirstSession
    }

    /// Share-sheet copy for INVITE A FRIEND.
    var shareText: String {
        "Join me for \(title) on RUXP. Complete any strength workout and earn +\(xpReward) XP."
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
    /// Live Ops rules (see `LiveOps.swift`). Defaults read `LiveOpsCatalog.current`.
    func activeModifiers(at date: Date) -> [LiveModifier]
    func nextModifier(at date: Date) -> LiveModifier?
    func modifiers(overlapping start: Date, end: Date) -> [LiveModifier]
}

extension LiveEventProviding {
    /// What the Home screen should show: live first, then the next timed event, then the season theme.
    func featuredEvent(at date: Date = Date()) -> LiveEvent {
        activeEvent(at: date) ?? nextEvent(at: date) ?? seasonEvent()
    }

    func activeModifiers(at date: Date) -> [LiveModifier] {
        LiveOpsCatalog.current.activeModifiers(at: date)
    }

    func nextModifier(at date: Date) -> LiveModifier? {
        LiveOpsCatalog.current.nextModifier(at: date)
    }

    func modifiers(overlapping start: Date, end: Date) -> [LiveModifier] {
        LiveOpsCatalog.current.modifiers(overlapping: start, end: end)
    }

    /// The rule worth showing on Home: active now, else one starting within `horizon`.
    func featuredModifier(at date: Date, horizon: TimeInterval = 48 * 3600) -> LiveModifier? {
        if let live = activeModifiers(at: date).first { return live }
        if let next = nextModifier(at: date), next.start.timeIntervalSince(date) <= horizon { return next }
        return nil
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

    /// Friday Night and Sunday Reset occurrences for the previous, current, and following ISO week.
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
            description: "Complete any strength workout today. Start the week ahead.",
            start: start,
            end: end,
            xpReward: 500,
            isSeasonWide: false
        )
    }
}
