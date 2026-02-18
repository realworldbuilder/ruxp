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
}

enum ChatActionType: String, Codable {
    case startWorkout
    case viewWorkout
    case analyzeWorkout
    case exportData
}

struct ChatWorkoutListItem: Codable, Identifiable {
    var id: String { workoutId ?? UUID().uuidString }
    var workoutId: String?
    var date: String?
    var summary: String?
    var volume: Double?
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
