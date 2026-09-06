import Foundation

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id: UUID
    var role: ChatRole
    var blocks: [ChatBlock]
    var timestamp: Date
    var isLoading: Bool

    init(
        id: UUID = UUID(),
        role: ChatRole,
        blocks: [ChatBlock] = [],
        timestamp: Date = Date(),
        isLoading: Bool = false
    ) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.timestamp = timestamp
        self.isLoading = isLoading
    }
}

enum ChatRole {
    case user
    case assistant
}

// MARK: - Chat Block

struct ChatBlock: Identifiable {
    let id: UUID
    var type: ChatBlockType
    var payload: ChatBlockPayload

    init(id: UUID = UUID(), type: ChatBlockType, payload: ChatBlockPayload) {
        self.id = id
        self.type = type
        self.payload = payload
    }
}

enum ChatBlockType: String, Codable {
    case text
    case workoutSummary
    case exerciseTable
    case metricGrid
    case chart
    case insight
    case actionButtons
    case workoutList
    case workoutPlan
    case progressCard
    case splitOverview
    case prBoard
    case tipCard
    case checklist
    case comparison
}

// MARK: - Chat Block Payload

struct ChatBlockPayload: Codable {
    var text: String?
    var workoutId: String?
    var date: String?
    var duration: String?
    var exerciseCount: Int?
    var totalSets: Int?
    var totalVolume: Double?
    var exerciseNames: [String]?
    var exerciseName: String?
    var sets: [ChatSetRow]?
    var metrics: [ChatMetric]?
    var chartType: String?
    var dataPoints: [ChatChartPoint]?
    var insightType: String?
    var title: String?
    var body: String?
    var actions: [ChatAction]?
    var workouts: [ChatWorkoutListItem]?
    
    // New payload properties for rich components
    var planTitle: String?
    var estimatedDuration: String?
    var warmup: String?
    var exercises: [PlanExercise]?
    var cooldown: String?
    
    var previous: ProgressEntry?
    var current: ProgressEntry?
    var volumeChange: String?
    var trend: String?
    
    var days: [SplitDay]?
    
    var records: [ChatPRRecord]?
    
    var icon: String?
    var category: String?
    
    var items: [ChecklistItem]?
    
    var leftLabel: String?
    var rightLabel: String?
    var rows: [ComparisonRow]?
}

// MARK: - Supporting Types

struct ChatSetRow: Codable {
    var setNumber: Int?
    var reps: Int?
    var weight: Double?
    var unit: String?
}

struct ChatMetric: Codable, Identifiable {
    var id: String { title ?? icon ?? UUID().uuidString }
    var icon: String?
    var value: String?
    var title: String?
    var subtitle: String?
}

struct ChatChartPoint: Codable {
    var label: String?
    var value: Double?
    var secondaryValue: Double?
    var date: String?
    var isPR: Bool?

    func toChartDataPoint() -> ChartDataPoint {
        let parsedDate: Date? = {
            guard let dateStr = date else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if let d = formatter.date(from: dateStr) { return d }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            return df.date(from: dateStr)
        }()

        return ChartDataPoint(
            label: label ?? "",
            value: value ?? 0,
            secondaryValue: secondaryValue,
            date: parsedDate,
            isPR: isPR
        )
    }
}

struct ChatAction: Codable, Identifiable {
    var id: String { label }
    var label: String
    var actionType: ChatActionType
    var workoutId: String?
    var prompt: String?       // For .askTrainer — pre-fills and sends this message
    var tabIndex: Int?        // For .switchTab — index of tab to navigate to
}

enum ChatActionType: String, Codable {
    case startWorkout
    case viewWorkout
    case analyzeWorkout
    case exportData
    case askTrainer           // Send a follow-up message to the trainer
    case switchTab            // Navigate to a different tab
    case viewInsights         // Jump to insights tab
}

struct ChatWorkoutListItem: Codable, Identifiable {
    var id: String { workoutId ?? UUID().uuidString }
    var workoutId: String?
    var date: String?
    var summary: String?
    var volume: Double?
}

// MARK: - Supporting Types for Rich Components

struct PlanExercise: Codable, Identifiable {
    var id: String { name }
    var name: String
    var prescription: String
    var rest: String?
    var notes: String?
    var targetRPE: String?
}

struct ProgressEntry: Codable {
    var date: String
    var topSet: String
    var totalVolume: Double
}

struct SplitDay: Codable, Identifiable {
    var id: String { day }
    var day: String
    var focus: String
    var completed: Bool
}

struct ChatPRRecord: Codable, Identifiable {
    var id: String { exercise }
    var exercise: String
    var value: String
    var date: String
    var isNew: Bool
}

struct ChecklistItem: Codable, Identifiable {
    var id: String { text }
    var text: String
    var checked: Bool
}

struct ComparisonRow: Codable, Identifiable {
    var id: String { label }
    var label: String
    var left: String
    var right: String
    var trend: String
}

// MARK: - API Response

struct ChatAPIResponse: Codable {
    var blocks: [ChatAPIBlock]?
}

struct ChatAPIBlock: Codable {
    var type: String?
    var payload: ChatBlockPayload?

    func toChatBlock() -> ChatBlock? {
        guard let typeStr = type, let blockType = ChatBlockType(rawValue: typeStr) else { return nil }
        return ChatBlock(type: blockType, payload: payload ?? ChatBlockPayload())
    }
}

// MARK: - Plan Conversion

extension PlannedWorkout {
    /// Convert a `workoutPlan` chat block payload into a real plan.
    /// Returns nil when the payload carries no exercises.
    init?(payload: ChatBlockPayload) {
        guard let planExercises = payload.exercises, !planExercises.isEmpty else { return nil }
        let exercises = planExercises.map { ex -> PlannedExercise in
            let parsed = PrescriptionParser.parse(ex.prescription)
            return PlannedExercise(
                name: ex.name,
                prescription: ex.prescription,
                targetSets: parsed.sets,
                targetReps: parsed.reps,
                targetWeight: parsed.weight,
                weightUnit: parsed.unit,
                restSeconds: ex.rest.flatMap { PrescriptionParser.parseRestSeconds($0) },
                restDisplay: ex.rest,
                notes: ex.notes,
                targetRPE: ex.targetRPE
            )
        }
        self.init(
            title: payload.planTitle ?? "Workout Plan",
            estimatedDuration: payload.estimatedDuration,
            warmup: payload.warmup,
            cooldown: payload.cooldown,
            exercises: exercises,
            source: "trainer"
        )
    }
}
