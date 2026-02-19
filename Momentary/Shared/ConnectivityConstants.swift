import Foundation

enum ConnectivityConstants {
    // Legacy keys (kept for backward compatibility)
    static let transcriptionKey = "transcription"
    static let errorKey = "error"

    // Workout message keys
    static let workoutMessageKey = "workoutMessage"
    static let commandKey = "command"
    static let workoutIDKey = "workoutID"
    static let momentIDKey = "momentID"
    static let timestampKey = "timestamp"
    static let transcriptKey = "transcript"
    static let confidenceKey = "confidence"

    // Health data keys (watch → phone)
    static let avgHeartRateKey = "avgHeartRate"
    static let activeCaloriesKey = "activeCalories"

    // Application context keys
    static let contextWorkoutIDKey = "ctx_workoutID"
    static let contextIsActiveKey = "ctx_isActive"
    static let contextStartedAtKey = "ctx_startedAt"
    static let contextMomentCountKey = "ctx_momentCount"

    // File transfer metadata keys
    static let fileTypeMomentAudio = "momentAudio"
    static let fileTypeKey = "fileType"
    static let metadataMomentIDKey = "momentID"
    static let metadataWorkoutIDKey = "workoutID"
}
