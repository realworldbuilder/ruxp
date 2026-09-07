import Foundation

// MARK: - Rules

/// A temporary change to how XP is earned. Ship rules, not features: a rule needs no new
/// screen, applies at reward time, and expires on its own.
enum LiveRule: Equatable {
    /// Awards of `reason` pay `factor`× while the rule is on (PR WEEKEND: personalRecord ×2).
    case multiplier(reason: XPReason, factor: Int)
    /// Every rewarded workout pays this much extra (S00 FINALE: +250).
    case flatBonus(amount: Int)
    /// Workouts started before `hour` (local, 0–23) pay this much extra (EARLY SHIFT).
    case startedBefore(hour: Int, amount: Int)
    /// Workouts started at or after `hour` (local, 0–23) pay this much extra (NIGHT SHIFT).
    case startedAfter(hour: Int, amount: Int)

    /// Time-of-day rules describe a season, not a weekend: Friday is not Tuesday, and night
    /// is not morning. They may run season-long; multipliers and flat bonuses stay short.
    var isTimeOfDay: Bool {
        switch self {
        case .startedBefore, .startedAfter: return true
        case .multiplier, .flatBonus: return false
        }
    }

    /// "×2 PR XP", "+250 XP", "+250 XP BEFORE 8 AM", "+250 XP AFTER 8 PM"
    var summaryLabel: String {
        switch self {
        case .multiplier(let reason, let factor): return "×\(factor) \(reason.shortLabel)"
        case .flatBonus(let amount): return "+\(amount.grouped) XP"
        case .startedBefore(let hour, let amount): return "+\(amount.grouped) XP BEFORE \(LiveRule.hourLabel(hour))"
        case .startedAfter(let hour, let amount): return "+\(amount.grouped) XP AFTER \(LiveRule.hourLabel(hour))"
        }
    }

    static func hourLabel(_ hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        switch h {
        case 0: return "12 AM"
        case 12: return "12 PM"
        case 1...11: return "\(h) AM"
        default: return "\(h - 12) PM"
        }
    }
}

extension XPReason {
    /// Short form for rule labels.
    var shortLabel: String {
        switch self {
        case .workoutComplete: return "WORKOUT XP"
        case .eventBonus: return "EVENT XP"
        case .weeklyBonus: return "WEEKLY XP"
        case .personalRecord: return "PR XP"
        case .modifier: return "XP"
        case .crewWeek: return "CREW XP"

        }
    }
}

// MARK: - Modifier

/// One dated rule with its copy. IDs are stable ("s00-pr-weekend") because a rewarded workout
/// remembers which rules covered it.
struct LiveModifier: Identifiable, Equatable {
    let id: String
    let title: String
    let eyebrow: String
    let description: String
    /// Local wall-clock window, like the timed events.
    let start: Date
    let end: Date
    let rule: LiveRule

    func isActive(at date: Date) -> Bool { date >= start && date < end }
    func isUpcoming(at date: Date) -> Bool { date < start }

    /// True when a workout with this start/end overlaps the window.
    func covers(start workoutStart: Date, end workoutEnd: Date?) -> Bool {
        let workoutEnd = workoutEnd ?? workoutStart
        return workoutStart < end && workoutEnd >= start
    }

    /// Extra XP this rule pays on top of `baseAwards` for a workout that started at `workoutStart`.
    /// Zero when the rule does not apply to these awards.
    func bonus(baseAwards: [XPAward], workoutStart: Date, calendar: Calendar = .current) -> Int {
        guard !baseAwards.isEmpty else { return 0 }
        switch rule {
        case .multiplier(let reason, let factor):
            let base = baseAwards.filter { $0.reason == reason }.reduce(0) { $0 + $1.amount }
            return max(0, factor - 1) * base
        case .flatBonus(let amount):
            return amount
        case .startedBefore(let hour, let amount):
            return calendar.component(.hour, from: workoutStart) < hour ? amount : 0
        case .startedAfter(let hour, let amount):
            return calendar.component(.hour, from: workoutStart) >= hour ? amount : 0
        }
    }

    /// "ENDS IN 2H 14M", "SAT–SUN"
    func windowLabel(now: Date, calendar: Calendar = .current) -> String {
        if isActive(at: now) {
            let remaining = Int(end.timeIntervalSince(now))
            let hours = remaining / 3600, minutes = (remaining % 3600) / 60
            if hours >= 48 { return "ENDS IN \(hours / 24)D" }
            if hours > 0 { return "ENDS IN \(hours)H \(minutes)M" }
            return "ENDS IN \(max(1, minutes))M"
        }
        let day = DateFormatter()
        // A season-long rule is announced by its first day, not a weekday span.
        if end.timeIntervalSince(start) > 7 * 24 * 3600 {
            day.dateFormat = "MMM d"
            return day.string(from: start).uppercased()
        }
        day.dateFormat = "EEE"
        let last = calendar.date(byAdding: .minute, value: -1, to: end) ?? end
        let first = day.string(from: start).uppercased()
        let lastDay = day.string(from: last).uppercased()
        return first == lastDay ? first : "\(first)–\(lastDay)"
    }
}

// MARK: - Calendar

/// A dated list of rules. The bundled copy is the offline truth; a validated remote copy
/// (`docs/live.json` on the site) can replace it without a build.
struct LiveOpsCalendar: Equatable {
    let version: Int
    let modifiers: [LiveModifier]

    func activeModifiers(at date: Date) -> [LiveModifier] {
        modifiers.filter { $0.isActive(at: date) }
    }

    func modifiers(overlapping start: Date, end: Date) -> [LiveModifier] {
        modifiers.filter { $0.covers(start: start, end: end) }
    }

    /// The next rule to start after `date`.
    func nextModifier(at date: Date) -> LiveModifier? {
        modifiers.filter { $0.isUpcoming(at: date) }.min { $0.start < $1.start }
    }

    func modifier(id: String) -> LiveModifier? {
        modifiers.first { $0.id == id }
    }

    // MARK: Validation

    /// Why a calendar must not be used. Empty means it is safe.
    /// Rules are capped so a bad edit to the JSON cannot turn the season into a slot machine.
    func validationErrors() -> [String] {
        var errors: [String] = []
        if version < 1 { errors.append("version must be ≥ 1") }
        if modifiers.count > 32 { errors.append("more than 32 modifiers") }
        var ids: Set<String> = []
        for m in modifiers {
            if m.id.isEmpty || !ids.insert(m.id).inserted { errors.append("duplicate or empty id \(m.id)") }
            if m.title.isEmpty { errors.append("\(m.id): empty title") }
            if m.end <= m.start { errors.append("\(m.id): end before start") }
            let maxDays = m.rule.isTimeOfDay ? 92 : 14
            if m.end.timeIntervalSince(m.start) > Double(maxDays) * 24 * 3600 { errors.append("\(m.id): window longer than \(maxDays) days") }
            switch m.rule {
            case .multiplier(_, let factor):
                if !(1...3).contains(factor) { errors.append("\(m.id): factor must be 1…3") }
            case .flatBonus(let amount):
                if !(0...1000).contains(amount) { errors.append("\(m.id): bonus must be 0…1000") }
            case .startedBefore(let hour, let amount), .startedAfter(let hour, let amount):
                if !(0...23).contains(hour) { errors.append("\(m.id): hour must be 0…23") }
                if !(0...1000).contains(amount) { errors.append("\(m.id): bonus must be 0…1000") }
            }
        }
        return errors
    }
}

// MARK: - Catalog

enum LiveOpsCatalog {
    /// What the app believes right now. The iOS `LiveOpsService` replaces it with a validated
    /// remote calendar; the watch and previews keep the bundled one. Same pattern as
    /// `ScheduledEventService.clockOverride`.
    nonisolated(unsafe) static var current: LiveOpsCalendar = bundled

    private static func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// S00 closes with PR WEEKEND and CONTINUE?. S01 NIGHTMARE MODE is defined by one season-long
    /// rule (NIGHT SHIFT), one weekend (FINAL BOSS on Halloween), and CONTINUE? again: the continue
    /// screen is every season's last call. Generic arcade vocabulary only; nothing names a game.
    /// Mirrors docs/live.json v3.
    static let bundled = LiveOpsCalendar(version: 3, modifiers: [
        LiveModifier(
            id: "s00-pr-weekend",
            title: "PR WEEKEND",
            eyebrow: "THIS WEEKEND ONLY",
            description: "Every PR pays double. Bring the voice notes.",
            start: local(2026, 9, 26),
            end: local(2026, 9, 28),
            rule: .multiplier(reason: .personalRecord, factor: 2)
        ),
        LiveModifier(
            id: "s00-finale",
            title: "CONTINUE?",
            eyebrow: "LAST CALL",
            description: "Season 00 closes Sep 30. Everything you earn now is Early Adopter forever. Season 01 starts Oct 1. Everyone continues at LVL 1 and keeps what they earned.",
            start: local(2026, 9, 28),
            end: local(2026, 10, 1),
            rule: .flatBonus(amount: 250)
        ),
        LiveModifier(
            id: "s01-night-shift",
            title: "NIGHT SHIFT",
            eyebrow: "ALL SEASON",
            description: "Start after 8 PM. +250 XP. Lights off, same weights.",
            start: local(2026, 10, 1),
            end: local(2026, 12, 1),
            rule: .startedAfter(hour: 20, amount: 250)
        ),
        LiveModifier(
            id: "s01-final-boss",
            title: "FINAL BOSS",
            eyebrow: "HALLOWEEN WEEKEND",
            description: "The boss is your best number. Beat it this weekend and the PR pays double.",
            start: local(2026, 10, 30),
            end: local(2026, 11, 2),
            rule: .multiplier(reason: .personalRecord, factor: 2)
        ),
        LiveModifier(
            id: "s01-finale",
            title: "CONTINUE?",
            eyebrow: "LAST CALL",
            description: "Season 01 closes Nov 30. Everything you earn now is Season 01 forever. Season 02 starts Dec 1. Everyone continues at LVL 1 and keeps what they earned.",
            start: local(2026, 11, 27),
            end: local(2026, 12, 1),
            rule: .flatBonus(amount: 250)
        ),
    ])
}

// MARK: - Wire format (docs/live.json)

/// Hand-written JSON on the site. Dates are local wall-clock "yyyy-MM-dd'T'HH:mm" so a rule
/// starts at each player's own midnight, like FRIDAY NIGHT does. Rule shape:
/// {"type":"multiplier","reason":"personalRecord","factor":2}
/// {"type":"flatBonus","amount":250}
/// {"type":"startedBefore","hour":8,"amount":250}
/// {"type":"startedAfter","hour":20,"amount":250}
extension LiveOpsCalendar: Codable {
    private enum CodingKeys: String, CodingKey { case version, modifiers }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        modifiers = try c.decode([LiveModifier].self, forKey: .modifiers)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(modifiers, forKey: .modifiers)
    }

    static func decode(_ data: Data) throws -> LiveOpsCalendar {
        try JSONDecoder().decode(LiveOpsCalendar.self, from: data)
    }
}

extension LiveModifier: Codable {
    private enum CodingKeys: String, CodingKey { case id, title, eyebrow, description, start, end, rule }

    nonisolated(unsafe) private static let wallClock: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        eyebrow = try c.decodeIfPresent(String.self, forKey: .eyebrow) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        let startString = try c.decode(String.self, forKey: .start)
        let endString = try c.decode(String.self, forKey: .end)
        guard let s = Self.wallClock.date(from: startString), let e = Self.wallClock.date(from: endString) else {
            throw DecodingError.dataCorruptedError(forKey: .start, in: c, debugDescription: "dates must be yyyy-MM-dd'T'HH:mm")
        }
        start = s
        end = e
        rule = try c.decode(LiveRule.self, forKey: .rule)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(eyebrow, forKey: .eyebrow)
        try c.encode(description, forKey: .description)
        try c.encode(Self.wallClock.string(from: start), forKey: .start)
        try c.encode(Self.wallClock.string(from: end), forKey: .end)
        try c.encode(rule, forKey: .rule)
    }
}

extension LiveRule: Codable {
    private enum CodingKeys: String, CodingKey { case type, reason, factor, amount, hour }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "multiplier":
            self = .multiplier(reason: try c.decode(XPReason.self, forKey: .reason), factor: try c.decode(Int.self, forKey: .factor))
        case "flatBonus":
            self = .flatBonus(amount: try c.decode(Int.self, forKey: .amount))
        case "startedBefore":
            self = .startedBefore(hour: try c.decode(Int.self, forKey: .hour), amount: try c.decode(Int.self, forKey: .amount))
        case "startedAfter":
            self = .startedAfter(hour: try c.decode(Int.self, forKey: .hour), amount: try c.decode(Int.self, forKey: .amount))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown rule type \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .multiplier(let reason, let factor):
            try c.encode("multiplier", forKey: .type)
            try c.encode(reason, forKey: .reason)
            try c.encode(factor, forKey: .factor)
        case .flatBonus(let amount):
            try c.encode("flatBonus", forKey: .type)
            try c.encode(amount, forKey: .amount)
        case .startedBefore(let hour, let amount):
            try c.encode("startedBefore", forKey: .type)
            try c.encode(hour, forKey: .hour)
            try c.encode(amount, forKey: .amount)
        case .startedAfter(let hour, let amount):
            try c.encode("startedAfter", forKey: .type)
            try c.encode(hour, forKey: .hour)
            try c.encode(amount, forKey: .amount)
        }
    }
}
