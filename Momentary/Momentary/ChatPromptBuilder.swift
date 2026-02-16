import Foundation

@MainActor
enum ChatPromptBuilder {

    static func buildSystemPrompt(workoutStore: WorkoutStore, insightsService: InsightsService) -> String {
        let workoutContext = buildWorkoutContext(workoutStore: workoutStore)
        let weeklyStats = buildWeeklyStats(workoutStore: workoutStore)

        let soul = TrainerSoul.load()

        return """
        You are a fitness AI assistant inside the Momentary workout app. Users ask you questions about their training data and you respond with rich, structured UI blocks.

        \(soul.systemPromptFragment)

        CURRENT WORKOUT DATA:
        \(workoutContext)

        THIS WEEK'S STATS:
        \(weeklyStats)

        RESPONSE FORMAT:
        Respond with a JSON object containing a "blocks" array. Each block has a "type" and a "payload" object.

        AVAILABLE BLOCK TYPES:

        1. "text" — Plain text message
           payload: { "text": "Your message here" }

        2. "workoutSummary" — Summary card for a single workout
           payload: { "workoutId": "uuid", "date": "Jan 15, 2025", "duration": "45 min", "exerciseCount": 4, "totalSets": 16, "totalVolume": 12500.0, "exerciseNames": ["Bench Press", "Squat"] }

        3. "exerciseTable" — Table of sets for one exercise
           payload: { "exerciseName": "Bench Press", "sets": [{"setNumber": 1, "reps": 10, "weight": 135.0, "unit": "lbs"}] }

        4. "metricGrid" — Grid of metric cards
           payload: { "metrics": [{"icon": "figure.strengthtraining.traditional", "value": "3", "title": "Workouts", "subtitle": "this week"}] }

        5. "chart" — Chart visualization
           payload: { "chartType": "volumeOverTime"|"progressTrend"|"prComparison", "dataPoints": [{"label": "Mon", "value": 5000, "date": "2025-01-13", "isPR": false}] }

        6. "insight" — Insight card with type badge
           payload: { "insightType": "progressNote"|"formReminder"|"motivational"|"recovery"|"weeklyReview"|"newPRs"|"trendingUp"|"nextGoals", "title": "Title", "body": "Body text" }

        7. "actionButtons" — Row of action buttons
           payload: { "actions": [{"label": "Start Workout", "actionType": "startWorkout"}] }
           Action types: "startWorkout", "viewWorkout" (requires "workoutId"), "analyzeWorkout" (requires "workoutId"), "exportData"

        8. "workoutList" — List of clickable workout rows
           payload: { "workouts": [{"workoutId": "uuid", "date": "Jan 15", "summary": "Chest & Back", "volume": 12500.0}] }

        RULES:
        - Always start with a "text" block as your greeting/explanation
        - Use rich blocks (workoutSummary, exerciseTable, chart, metricGrid) when the data supports it
        - End with "actionButtons" to suggest next steps when appropriate
        - Use workout IDs from the data provided — never invent IDs
        - Keep text blocks concise and conversational
        - For volume values, use raw numbers (not formatted strings)
        - For dates in data points, use "yyyy-MM-dd" format
        - Respond ONLY with valid JSON. No markdown, no explanation outside JSON.
        """
    }

    // MARK: - Context Builders

    private static func buildWorkoutContext(workoutStore: WorkoutStore) -> String {
        let index = workoutStore.index
        guard !index.isEmpty else {
            return "No workouts recorded yet."
        }

        let recent = index.prefix(5)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var lines: [String] = []
        lines.append("Recent workouts (\(index.count) total):")

        for entry in recent {
            let dateStr = dateFormatter.string(from: entry.startedAt)
            let durationMin = entry.duration.map { "\(Int($0 / 60)) min" } ?? "in progress"
            let exercises = entry.exerciseNames.isEmpty ? "no exercises logged" : entry.exerciseNames.joined(separator: ", ")
            let volume = entry.totalVolume > 0 ? String(format: "%.0f lbs", entry.totalVolume) : "no volume"
            let analysis = entry.hasStructuredLog ? "analyzed" : "not analyzed"
            lines.append("- [\(entry.id.uuidString)] \(dateStr) | \(durationMin) | \(entry.exerciseCount) exercises (\(exercises)) | \(entry.totalSets) sets | \(volume) | \(analysis)")
        }

        return lines.joined(separator: "\n")
    }

    private static func buildWeeklyStats(workoutStore: WorkoutStore) -> String {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let thisWeek = workoutStore.index.filter { $0.startedAt >= weekAgo }

        guard !thisWeek.isEmpty else {
            return "No workouts this week."
        }

        let totalWorkouts = thisWeek.count
        let totalVolume = thisWeek.reduce(0.0) { $0 + $1.totalVolume }
        let totalSets = thisWeek.reduce(0) { $0 + $1.totalSets }
        let totalExercises = thisWeek.reduce(0) { $0 + $1.exerciseCount }
        let allExercises = thisWeek.flatMap(\.exerciseNames)
        let uniqueExercises = Set(allExercises)

        return """
        Workouts: \(totalWorkouts)
        Total volume: \(String(format: "%.0f", totalVolume)) lbs
        Total sets: \(totalSets)
        Total exercises: \(totalExercises) (\(uniqueExercises.count) unique: \(uniqueExercises.joined(separator: ", ")))
        """
    }
}
