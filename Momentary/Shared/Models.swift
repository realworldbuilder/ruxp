import Foundation
import SwiftUI

// MARK: - Workout Session

struct WorkoutSession: Codable, Identifiable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var healthWorkoutUUID: UUID?
    var moments: [Moment]
    var structuredLog: StructuredLog?
    var contentPack: ContentPack?
    var stories: [InsightStory]
    var averageHeartRate: Double?
    var activeCalories: Double?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        healthWorkoutUUID: UUID? = nil,
        moments: [Moment] = [],
        structuredLog: StructuredLog? = nil,
        contentPack: ContentPack? = nil,
        stories: [InsightStory] = [],
        averageHeartRate: Double? = nil,
        activeCalories: Double? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.healthWorkoutUUID = healthWorkoutUUID
        self.moments = moments
        self.structuredLog = structuredLog
        self.contentPack = contentPack
        self.stories = stories
        self.averageHeartRate = averageHeartRate
        self.activeCalories = activeCalories
    }

    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}

// MARK: - Moment

struct Moment: Codable, Identifiable {
    let id: UUID
    var timestamp: Date
    var transcript: String
    var source: MomentSource
    var tags: [String]
    var confidence: Double

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        transcript: String = "",
        source: MomentSource = .watch,
        tags: [String] = [],
        confidence: Double = 1.0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.transcript = transcript
        self.source = source
        self.tags = tags
        self.confidence = confidence
    }
}

enum MomentSource: String, Codable {
    case watch
    case phone
}

// MARK: - Structured Log

struct StructuredLog: Codable {
    var exercises: [ExerciseGroup]
    var summary: String
    var highlights: [String]
    var ambiguities: [Ambiguity]

    private enum CodingKeys: String, CodingKey {
        case exercises, summary, highlights, ambiguities
    }

    init(
        exercises: [ExerciseGroup] = [],
        summary: String = "",
        highlights: [String] = [],
        ambiguities: [Ambiguity] = []
    ) {
        self.exercises = exercises
        self.summary = summary
        self.highlights = highlights
        self.ambiguities = ambiguities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.exercises = (try? container.decode([ExerciseGroup].self, forKey: .exercises)) ?? []
        self.summary = (try? container.decode(String.self, forKey: .summary)) ?? ""
        self.highlights = (try? container.decode([String].self, forKey: .highlights)) ?? []
        self.ambiguities = (try? container.decode([Ambiguity].self, forKey: .ambiguities)) ?? []
    }
}

struct ExerciseGroup: Codable, Identifiable {
    let id: UUID
    var exerciseName: String
    var sets: [ExerciseSet]
    var notes: String?

    private enum CodingKeys: String, CodingKey {
        case id, exerciseName, sets, notes
    }

    init(
        id: UUID = UUID(),
        exerciseName: String,
        sets: [ExerciseSet] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.sets = sets
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.exerciseName = (try? container.decode(String.self, forKey: .exerciseName)) ?? "Unknown Exercise"
        self.sets = (try? container.decode([ExerciseSet].self, forKey: .sets)) ?? []
        self.notes = try? container.decodeIfPresent(String.self, forKey: .notes)
    }
}

struct ExerciseSet: Codable, Identifiable {
    let id: UUID
    var setNumber: Int
    var reps: Int?
    var weight: Double?
    var weightUnit: WeightUnit
    var duration: TimeInterval?
    var notes: String?

    private enum CodingKeys: String, CodingKey {
        case id, setNumber, reps, weight, weightUnit, duration, notes
    }

    init(
        id: UUID = UUID(),
        setNumber: Int,
        reps: Int? = nil,
        weight: Double? = nil,
        weightUnit: WeightUnit = .lbs,
        duration: TimeInterval? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.reps = reps
        self.weight = weight
        self.weightUnit = weightUnit
        self.duration = duration
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()

        // setNumber: try Int, then String→Int, then fallback to 1
        if let intVal = try? container.decode(Int.self, forKey: .setNumber) {
            self.setNumber = intVal
        } else if let strVal = try? container.decode(String.self, forKey: .setNumber), let parsed = Int(strVal) {
            self.setNumber = parsed
        } else {
            self.setNumber = 1
        }

        // reps: try Int, then String→Int
        if let intVal = try? container.decodeIfPresent(Int.self, forKey: .reps) {
            self.reps = intVal
        } else if let strVal = try? container.decode(String.self, forKey: .reps), let parsed = Int(strVal) {
            self.reps = parsed
        } else {
            self.reps = nil
        }

        // weight: try Double, then String→Double
        if let dblVal = try? container.decodeIfPresent(Double.self, forKey: .weight) {
            self.weight = dblVal
        } else if let strVal = try? container.decode(String.self, forKey: .weight), let parsed = Double(strVal) {
            self.weight = parsed
        } else {
            self.weight = nil
        }

        self.weightUnit = (try? container.decode(WeightUnit.self, forKey: .weightUnit)) ?? .lbs
        self.duration = try? container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        self.notes = try? container.decodeIfPresent(String.self, forKey: .notes)
    }
}

enum WeightUnit: String, Codable {
    case lbs
    case kg

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self))?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        switch raw {
        case "lbs", "lb", "pounds", "pound":
            self = .lbs
        case "kg", "kgs", "kilograms", "kilogram":
            self = .kg
        default:
            self = .lbs
        }
    }
}

struct Ambiguity: Codable, Identifiable {
    let id: UUID
    var field: String
    var rawTranscript: String
    var bestGuess: String
    var alternatives: [String]

    private enum CodingKeys: String, CodingKey {
        case id, field, rawTranscript, bestGuess, alternatives
    }

    init(
        id: UUID = UUID(),
        field: String,
        rawTranscript: String,
        bestGuess: String,
        alternatives: [String] = []
    ) {
        self.id = id
        self.field = field
        self.rawTranscript = rawTranscript
        self.bestGuess = bestGuess
        self.alternatives = alternatives
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.field = (try? container.decode(String.self, forKey: .field)) ?? ""
        self.rawTranscript = (try? container.decode(String.self, forKey: .rawTranscript)) ?? ""
        self.bestGuess = (try? container.decode(String.self, forKey: .bestGuess)) ?? ""
        self.alternatives = (try? container.decode([String].self, forKey: .alternatives)) ?? []
    }
}

// MARK: - Content Pack

struct ContentPack: Codable {
    var igCaptions: [String]
    var tweetThread: [String]
    var reelScript: String
    var storyCards: [StoryCard]
    var hooks: [String]
    var takeaways: [String]

    private enum CodingKeys: String, CodingKey {
        case igCaptions, tweetThread, reelScript, storyCards, hooks, takeaways
    }

    init(
        igCaptions: [String] = [],
        tweetThread: [String] = [],
        reelScript: String = "",
        storyCards: [StoryCard] = [],
        hooks: [String] = [],
        takeaways: [String] = []
    ) {
        self.igCaptions = igCaptions
        self.tweetThread = tweetThread
        self.reelScript = reelScript
        self.storyCards = storyCards
        self.hooks = hooks
        self.takeaways = takeaways
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.igCaptions = (try? container.decode([String].self, forKey: .igCaptions)) ?? []
        self.tweetThread = (try? container.decode([String].self, forKey: .tweetThread)) ?? []
        self.reelScript = (try? container.decode(String.self, forKey: .reelScript)) ?? ""
        self.storyCards = (try? container.decode([StoryCard].self, forKey: .storyCards)) ?? []
        self.hooks = (try? container.decode([String].self, forKey: .hooks)) ?? []
        self.takeaways = (try? container.decode([String].self, forKey: .takeaways)) ?? []
    }
}

struct StoryCard: Codable, Identifiable {
    let id: UUID
    var title: String
    var body: String

    private enum CodingKeys: String, CodingKey {
        case id, title, body
    }

    init(id: UUID = UUID(), title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.title = (try? container.decode(String.self, forKey: .title)) ?? ""
        self.body = (try? container.decode(String.self, forKey: .body)) ?? ""
    }
}

// MARK: - Insight Story

struct InsightStory: Codable, Identifiable {
    let id: UUID
    var title: String
    var body: String
    var tags: [String]
    var type: InsightType
    var pages: [InsightPage]?
    var preview: String?
    var generatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, title, body, tags, type, pages, preview, generatedAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        tags: [String] = [],
        type: InsightType,
        pages: [InsightPage]? = nil,
        preview: String? = nil,
        generatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.type = type
        self.pages = pages
        self.preview = preview
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.title = (try? container.decode(String.self, forKey: .title)) ?? ""
        self.body = (try? container.decode(String.self, forKey: .body)) ?? ""
        self.tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        self.type = (try? container.decode(InsightType.self, forKey: .type)) ?? .progressNote
        self.pages = try? container.decodeIfPresent([InsightPage].self, forKey: .pages)
        self.preview = try? container.decodeIfPresent(String.self, forKey: .preview)
        self.generatedAt = try? container.decodeIfPresent(Date.self, forKey: .generatedAt)
    }

    var resolvedPages: [InsightPage] {
        if let pages, !pages.isEmpty { return pages }
        return [InsightPage(title: title, content: body)]
    }

    var storyIdentifier: String {
        type.rawValue
    }

    var contentHash: Int {
        var hasher = Hasher()
        hasher.combine(type.rawValue)
        hasher.combine(title)
        for page in resolvedPages {
            hasher.combine(page.content)
            hasher.combine(page.actionable)
        }
        return hasher.finalize()
    }
}

enum InsightType: String, Codable, CaseIterable {
    case progressNote
    case formReminder
    case motivational
    case recovery
    case weeklyReview
    case newPRs
    case trendingUp
    case nextGoals
    case trainerFeedback

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        let normalized = raw.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "progressnote", "progress":
            self = .progressNote
        case "formreminder", "form":
            self = .formReminder
        case "motivational", "motivation":
            self = .motivational
        case "recovery":
            self = .recovery
        case "weeklyreview", "weekly":
            self = .weeklyReview
        case "newprs", "prs", "pr":
            self = .newPRs
        case "trendingup", "trending":
            self = .trendingUp
        case "nextgoals", "goals":
            self = .nextGoals
        case "trainerfeedback", "trainer", "feedback":
            self = .trainerFeedback
        default:
            self = .progressNote
        }
    }

    var displayName: String {
        switch self {
        case .progressNote: return "Progress"
        case .formReminder: return "Form"
        case .motivational: return "Motivation"
        case .recovery: return "Recovery"
        case .weeklyReview: return "Weekly Review"
        case .newPRs: return "New PRs"
        case .trendingUp: return "Trending Up"
        case .nextGoals: return "Next Goals"
        case .trainerFeedback: return "Trainer"
        }
    }

    var systemIcon: String {
        switch self {
        case .progressNote: return "chart.line.uptrend.xyaxis"
        case .formReminder: return "checkmark.circle.fill"
        case .motivational: return "star.fill"
        case .recovery: return "bed.double.fill"
        case .weeklyReview: return "chart.bar.fill"
        case .newPRs: return "trophy.fill"
        case .trendingUp: return "arrow.up.right.circle.fill"
        case .nextGoals: return "flag.fill"
        case .trainerFeedback: return "bubble.left.and.text.bubble.right.fill"
        }
    }

    var color: Color {
        switch self {
        case .progressNote: return .blue
        case .formReminder: return .orange
        case .motivational: return .green
        case .recovery: return .purple
        case .weeklyReview: return .cyan
        case .newPRs: return .yellow
        case .trendingUp: return .mint
        case .nextGoals: return .indigo
        case .trainerFeedback: return Color(red: 0.06, green: 0.64, blue: 0.50)
        }
    }
}

// MARK: - Insight Page

struct InsightPage: Codable, Identifiable {
    let id: UUID
    var title: String
    var content: String
    var chartData: InsightChartData?
    var actionable: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, content, chartData, actionable
    }

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        chartData: InsightChartData? = nil,
        actionable: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.chartData = chartData
        self.actionable = actionable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.title = (try? container.decode(String.self, forKey: .title)) ?? ""
        self.content = (try? container.decode(String.self, forKey: .content)) ?? ""
        self.chartData = try? container.decodeIfPresent(InsightChartData.self, forKey: .chartData)
        self.actionable = try? container.decodeIfPresent(String.self, forKey: .actionable)
    }
}

// MARK: - Insight Chart Data

struct InsightChartData: Codable {
    var chartType: InsightChartType
    var dataPoints: [ChartDataPoint]

    init(chartType: InsightChartType, dataPoints: [ChartDataPoint]) {
        self.chartType = chartType
        self.dataPoints = dataPoints
    }
}

enum InsightChartType: String, Codable {
    case volumeOverTime
    case progressTrend
    case prComparison
}

struct ChartDataPoint: Codable, Identifiable {
    let id: UUID
    var label: String
    var value: Double
    var secondaryValue: Double?
    var date: Date?
    var isPR: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, label, value, secondaryValue, date, isPR
    }

    init(
        id: UUID = UUID(),
        label: String,
        value: Double,
        secondaryValue: Double? = nil,
        date: Date? = nil,
        isPR: Bool? = nil
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.secondaryValue = secondaryValue
        self.date = date
        self.isPR = isPR
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.label = (try? container.decode(String.self, forKey: .label)) ?? ""
        self.value = (try? container.decode(Double.self, forKey: .value)) ?? 0
        self.secondaryValue = try? container.decodeIfPresent(Double.self, forKey: .secondaryValue)
        self.date = try? container.decodeIfPresent(Date.self, forKey: .date)
        self.isPR = try? container.decodeIfPresent(Bool.self, forKey: .isPR)
    }
}

// MARK: - Dashboard Metric

struct DashboardMetric: Identifiable {
    let id: UUID
    var title: String
    var value: String
    var subtitle: String?
    var icon: String
    var color: Color
    var trend: TrendDirection?
    var trendValue: String?

    init(
        id: UUID = UUID(),
        title: String,
        value: String,
        subtitle: String? = nil,
        icon: String,
        color: Color,
        trend: TrendDirection? = nil,
        trendValue: String? = nil
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
        self.trend = trend
        self.trendValue = trendValue
    }
}

enum TrendDirection {
    case up, down, stable

    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .stable: return .secondary
        }
    }
}

// MARK: - Insight Pack

struct InsightPack: Codable {
    var takeaways: [String]
    var formCues: [String]
    var prNotes: [String]

    private enum CodingKeys: String, CodingKey {
        case takeaways, formCues, prNotes
    }

    init(
        takeaways: [String] = [],
        formCues: [String] = [],
        prNotes: [String] = []
    ) {
        self.takeaways = takeaways
        self.formCues = formCues
        self.prNotes = prNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.takeaways = (try? container.decode([String].self, forKey: .takeaways)) ?? []
        self.formCues = (try? container.decode([String].self, forKey: .formCues)) ?? []
        self.prNotes = (try? container.decode([String].self, forKey: .prNotes)) ?? []
    }
}

// MARK: - Connectivity

enum WorkoutCommand: String, Codable {
    case start
    case stop
    case momentRecorded
    case momentTranscribed
}

struct WorkoutMessage: Codable {
    var command: WorkoutCommand
    var workoutID: UUID
    var momentID: UUID?
    var transcript: String?
    var confidence: Double?
    var timestamp: Date
    var error: String?
    var healthWorkoutUUID: UUID?
    var avgHeartRate: Double?
    var activeCalories: Double?

    init(
        command: WorkoutCommand,
        workoutID: UUID,
        momentID: UUID? = nil,
        transcript: String? = nil,
        confidence: Double? = nil,
        timestamp: Date = Date(),
        error: String? = nil,
        healthWorkoutUUID: UUID? = nil,
        avgHeartRate: Double? = nil,
        activeCalories: Double? = nil
    ) {
        self.command = command
        self.workoutID = workoutID
        self.momentID = momentID
        self.transcript = transcript
        self.confidence = confidence
        self.timestamp = timestamp
        self.error = error
        self.healthWorkoutUUID = healthWorkoutUUID
        self.avgHeartRate = avgHeartRate
        self.activeCalories = activeCalories
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "command": command.rawValue,
            "workoutID": workoutID.uuidString,
            "timestamp": timestamp.timeIntervalSince1970
        ]
        if let momentID { dict["momentID"] = momentID.uuidString }
        if let transcript { dict["transcript"] = transcript }
        if let confidence { dict["confidence"] = confidence }
        if let error { dict["error"] = error }
        if let healthWorkoutUUID { dict["healthWorkoutUUID"] = healthWorkoutUUID.uuidString }
        if let avgHeartRate { dict["avgHeartRate"] = avgHeartRate }
        if let activeCalories { dict["activeCalories"] = activeCalories }
        return dict
    }

    static func from(dictionary dict: [String: Any]) -> WorkoutMessage? {
        guard
            let commandRaw = dict["command"] as? String,
            let command = WorkoutCommand(rawValue: commandRaw),
            let workoutIDString = dict["workoutID"] as? String,
            let workoutID = UUID(uuidString: workoutIDString),
            let timestampInterval = dict["timestamp"] as? TimeInterval
        else { return nil }

        return WorkoutMessage(
            command: command,
            workoutID: workoutID,
            momentID: (dict["momentID"] as? String).flatMap(UUID.init),
            transcript: dict["transcript"] as? String,
            confidence: dict["confidence"] as? Double,
            timestamp: Date(timeIntervalSince1970: timestampInterval),
            error: dict["error"] as? String,
            healthWorkoutUUID: (dict["healthWorkoutUUID"] as? String).flatMap(UUID.init),
            avgHeartRate: dict["avgHeartRate"] as? Double,
            activeCalories: dict["activeCalories"] as? Double
        )
    }
}

// MARK: - Index

struct WorkoutSessionIndex: Codable, Identifiable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var momentCount: Int
    var hasStructuredLog: Bool
    var exerciseNames: [String]
    var exerciseCount: Int
    var totalSets: Int
    var totalVolume: Double
    var hasStories: Bool
    var averageHeartRate: Double?
    var activeCalories: Double?

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, momentCount, hasStructuredLog, exerciseNames
        case exerciseCount, totalSets, totalVolume, hasStories, averageHeartRate, activeCalories
    }

    init(from session: WorkoutSession) {
        self.id = session.id
        self.startedAt = session.startedAt
        self.endedAt = session.endedAt
        self.momentCount = session.moments.count
        self.hasStructuredLog = session.structuredLog != nil
        self.exerciseNames = session.structuredLog?.exercises.map(\.exerciseName) ?? []
        let exercises = session.structuredLog?.exercises ?? []
        self.exerciseCount = exercises.count
        self.totalSets = exercises.reduce(0) { $0 + $1.sets.count }
        self.totalVolume = exercises.reduce(0.0) { total, group in
            total + group.sets.reduce(0.0) { setTotal, set in
                setTotal + Double(set.reps ?? 0) * (set.weight ?? 0)
            }
        }
        self.hasStories = !session.stories.isEmpty
        self.averageHeartRate = session.averageHeartRate
        self.activeCalories = session.activeCalories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.startedAt = try container.decode(Date.self, forKey: .startedAt)
        self.endedAt = try? container.decodeIfPresent(Date.self, forKey: .endedAt)
        self.momentCount = (try? container.decode(Int.self, forKey: .momentCount)) ?? 0
        self.hasStructuredLog = (try? container.decode(Bool.self, forKey: .hasStructuredLog)) ?? false
        self.exerciseNames = (try? container.decode([String].self, forKey: .exerciseNames)) ?? []
        self.exerciseCount = (try? container.decode(Int.self, forKey: .exerciseCount)) ?? 0
        self.totalSets = (try? container.decode(Int.self, forKey: .totalSets)) ?? 0
        self.totalVolume = (try? container.decode(Double.self, forKey: .totalVolume)) ?? 0
        self.hasStories = (try? container.decode(Bool.self, forKey: .hasStories)) ?? false
        self.averageHeartRate = try? container.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        self.activeCalories = try? container.decodeIfPresent(Double.self, forKey: .activeCalories)
    }

    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    /// Smart workout title based on exercises (e.g. "Chest Day", "Pull Day", "Full Body")
    var title: String {
        WorkoutTitleGenerator.generate(from: exerciseNames)
    }
}

// MARK: - Workout Title Generator

enum WorkoutTitleGenerator {
    private static let muscleMap: [String: Set<String>] = [
        "chest": ["bench", "chest", "fly", "flye", "pec", "dumbbell press", "incline press", "decline press", "push up", "pushup", "dip"],
        "back": ["row", "pull up", "pullup", "chin up", "chinup", "lat", "deadlift", "pulldown", "pull-down", "back extension", "barbell row", "cable row", "t-bar"],
        "shoulders": ["shoulder", "overhead press", "ohp", "military press", "lateral raise", "front raise", "rear delt", "face pull", "shrug", "delt"],
        "legs": ["squat", "leg press", "lunge", "hamstring", "quad", "calf", "calves", "leg curl", "leg extension", "hip thrust", "glute", "rdl", "romanian", "goblet"],
        "arms": ["bicep", "curl", "tricep", "triceps", "hammer curl", "preacher", "skull crusher", "pushdown", "extension"],
        "core": ["ab", "abs", "crunch", "plank", "sit up", "situp", "cable crunch", "leg raise", "oblique", "core"]
    ]

    static func generate(from exerciseNames: [String]) -> String {
        guard !exerciseNames.isEmpty else { return "Workout" }

        // Tally which muscle groups are hit
        var hits: [String: Int] = [:]
        for name in exerciseNames {
            let lower = name.lowercased()
            for (group, keywords) in muscleMap {
                if keywords.contains(where: { lower.contains($0) }) {
                    hits[group, default: 0] += 1
                }
            }
        }

        // No matches — just use the first exercise
        guard !hits.isEmpty else {
            return exerciseNames.first.map { formatExerciseName($0) + " Day" } ?? "Workout"
        }

        let sorted = hits.sorted { $0.value > $1.value }
        let total = exerciseNames.count
        let topGroup = sorted[0].key
        let topCount = sorted[0].value

        // If one group dominates (>60%), name it that
        if Double(topCount) / Double(total) > 0.6 || sorted.count == 1 {
            return friendlyName(topGroup)
        }

        // Check for push/pull/legs patterns
        let groupSet = Set(sorted.map(\.key))
        if groupSet.isSuperset(of: ["chest", "shoulders"]) && !groupSet.contains("back") {
            return "Push Day"
        }
        if groupSet.isSuperset(of: ["back"]) && !groupSet.contains("chest") && (groupSet.contains("arms") || sorted.count <= 2) {
            return "Pull Day"
        }
        if groupSet.contains("legs") && sorted.count <= 2 {
            return "Leg Day"
        }

        // Upper vs lower
        let upperGroups: Set<String> = ["chest", "back", "shoulders", "arms"]
        let lowerGroups: Set<String> = ["legs"]
        let hasUpper = !groupSet.intersection(upperGroups).isEmpty
        let hasLower = !groupSet.intersection(lowerGroups).isEmpty

        if hasUpper && hasLower && sorted.count >= 3 {
            return "Full Body"
        }
        if hasUpper && !hasLower {
            return "Upper Body"
        }
        if hasLower && !hasUpper {
            return "Lower Body"
        }

        // Two groups
        if sorted.count == 2 {
            return "\(friendlyName(sorted[0].key)) & \(friendlyName(sorted[1].key))"
        }

        return "Full Body"
    }

    private static func friendlyName(_ group: String) -> String {
        switch group {
        case "chest": return "Chest Day"
        case "back": return "Back Day"
        case "shoulders": return "Shoulder Day"
        case "legs": return "Leg Day"
        case "arms": return "Arms Day"
        case "core": return "Core Day"
        default: return "Workout"
        }
    }

    private static func formatExerciseName(_ name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }
}

// MARK: - AI Processing

struct AIWorkoutOutput: Codable {
    var structuredLog: StructuredLog
    var contentPack: ContentPack
    var stories: [InsightStory]
    var insightPack: InsightPack?

    private enum CodingKeys: String, CodingKey {
        case structuredLog, contentPack, stories, insightPack
    }

    init(
        structuredLog: StructuredLog = StructuredLog(),
        contentPack: ContentPack = ContentPack(),
        stories: [InsightStory] = [],
        insightPack: InsightPack? = nil
    ) {
        self.structuredLog = structuredLog
        self.contentPack = contentPack
        self.stories = stories
        self.insightPack = insightPack
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.structuredLog = (try? container.decode(StructuredLog.self, forKey: .structuredLog)) ?? StructuredLog()
        self.contentPack = (try? container.decode(ContentPack.self, forKey: .contentPack)) ?? ContentPack()
        self.stories = (try? container.decode([InsightStory].self, forKey: .stories)) ?? []
        self.insightPack = try? container.decodeIfPresent(InsightPack.self, forKey: .insightPack)
    }
}

struct WorkoutProcessingRequest: Codable, Identifiable {
    let id: UUID
    var workoutID: UUID
    var transcripts: [MomentTranscript]
    var workoutDate: Date
    var duration: TimeInterval
    var retryCount: Int
    var lastAttempt: Date?

    init(
        workoutID: UUID,
        transcripts: [MomentTranscript],
        workoutDate: Date,
        duration: TimeInterval,
        retryCount: Int = 0,
        lastAttempt: Date? = nil
    ) {
        self.id = UUID()
        self.workoutID = workoutID
        self.transcripts = transcripts
        self.workoutDate = workoutDate
        self.duration = duration
        self.retryCount = retryCount
        self.lastAttempt = lastAttempt
    }
}

struct MomentTranscript: Codable {
    var momentID: UUID
    var timestamp: Date
    var transcript: String
}

// MARK: - Legacy Support

struct LegacyTranscriptionRecord: Codable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date
}
