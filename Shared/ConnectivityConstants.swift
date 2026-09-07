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
    static let contextPlanDataKey = "ctx_planData"
    /// Watch → phone: the watch has a live HealthKit session for `ctx_workoutID`, so the phone
    /// must not write its own Health workout for it.
    static let contextWatchHealthSessionKey = "ctx_watchHealthSession"

    // Progression context keys (phone → watch, piggyback on application context)
    static let contextLevelKey = "ctx_level"
    static let contextSeasonXPKey = "ctx_seasonXP"
    static let contextXPIntoLevelKey = "ctx_xpIntoLevel"
    static let contextXPToNextKey = "ctx_xpToNext"

    // Live presence context keys (phone → watch, piggyback on application context)
    static let contextLiftingNowKey = "ctx_liftingNow"
    static let contextTrainedTodayKey = "ctx_trainedToday"
    static let contextPresenceAvailableKey = "ctx_presenceAvailable"
    static let contextPresenceUpdatedAtKey = "ctx_presenceUpdatedAt"
    static let contextGameCenterSyncKey = "ctx_gameCenterSync"

    // File transfer metadata keys
    static let fileTypeMomentAudio = "momentAudio"
    static let fileTypeKey = "fileType"
    static let metadataMomentIDKey = "momentID"
    static let metadataWorkoutIDKey = "workoutID"
}
