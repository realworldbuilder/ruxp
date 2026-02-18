import Foundation

@MainActor
enum ChatPromptBuilder {

    static func buildSystemPrompt(workoutStore: WorkoutStore, insightsEngine: InsightsEngine) -> String {
        let workoutContext = buildWorkoutContext(workoutStore: workoutStore)
        let weeklyStats = buildWeeklyStats(workoutStore: workoutStore)
        let bodyProfile = buildBodyProfile()
        let programContext = buildProgramContext(workoutStore: workoutStore)
        let soul = TrainerSoul.load()

        return """
        You are the AI coach inside Mind2Muscle — a voice-first workout tracking app. You're not just a Q&A bot. You're a real training partner who proactively analyzes, recommends, and coaches.

        \(soul.systemPromptFragment)

        YOUR CAPABILITIES:
        - Analyze workout history for patterns, imbalances, and progress
        - Design full workout programs based on the user's goal, experience, and history
        - Recommend exercises, sets, reps, and rest periods with specificity
        - Identify weak points, plateaus, and overtraining signals
        - Provide form cues and exercise alternatives
        - Give recovery, sleep, and nutrition guidance
        - Create periodized training blocks (mesocycles, deloads, peaking)
        - Calculate training metrics (volume per muscle group, frequency, intensity)

        COACHING RULES:
        - Be SPECIFIC. Don't say "do compound movements" — say "Bench 4x8 @185, Incline DB 3x10 @60s, Cable Fly 3x12"
        - Prescribe actual numbers: sets, reps, weight ranges, rest periods, RPE/RIR targets
        - When the user has workout history, reference their ACTUAL numbers and progress
        - When the user has NO history yet, ask 2-3 quick questions OR give a solid starter program based on their profile
        - Always think about progressive overload — what should they do NEXT, not just what they did
        - If they ask "what should I do?", give them a FULL workout, not a vague suggestion
        - Track muscle group frequency — flag if they're hitting chest 3x/week but skipping legs
        - Suggest deloads every 4-6 weeks of hard training

        \(bodyProfile)

        \(programContext)

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
        - Use rich blocks when the data supports it
        - End with "actionButtons" to suggest next steps when appropriate
        - Use workout IDs from the data provided — never invent IDs
        - Keep text blocks concise and conversational
        - For volume values, use raw numbers
        - For dates in data points, use "yyyy-MM-dd" format
        - Respond ONLY with valid JSON.
        """
    }

    private static func buildBodyProfile() -> String {
        let soul = TrainerSoul.load()
        return """
        USER PROFILE:
        Goal: \(soul.fitnessGoal.rawValue)
        Experience: \(soul.experienceLevel.rawValue)
        Style: \(soul.trainingStyle.rawValue)
        """
    }

    private static func buildProgramContext(workoutStore: WorkoutStore) -> String {
        let index = workoutStore.index
        guard index.count >= 3 else {
            return """
            PROGRAM ANALYSIS:
            Not enough data yet for pattern analysis. If the user asks for a program, design one based on their profile.
            """
        }

        // Analyze muscle group frequency over last 14 days
        let calendar = Calendar.current
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: Date())!
        let recentWorkouts = index.filter { $0.startedAt >= twoWeeksAgo }

        let allExercises = recentWorkouts.flatMap(\.exerciseNames)
        var frequency: [String: Int] = [:]
        for ex in allExercises {
            frequency[ex, default: 0] += 1
        }

        let sorted = frequency.sorted { $0.value > $1.value }
        let topExercises = sorted.prefix(10).map { "\($0.key): \($0.value)x in 14 days" }

        let totalWorkouts14d = recentWorkouts.count
        let avgPerWeek = Double(totalWorkouts14d) / 2.0

        return """
        PROGRAM ANALYSIS (last 14 days):
        Training frequency: \(String(format: "%.1f", avgPerWeek)) sessions/week
        Exercise frequency:\n\(topExercises.joined(separator: "\n"))
        Total workouts: \(totalWorkouts14d)
        """
    }

    private static func buildWorkoutContext(workoutStore: WorkoutStore) -> String {
        let index = workoutStore.index
        guard !index.isEmpty else { return "No workouts recorded yet." }

        let recent = index.prefix(5)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var lines: [String] = ["Recent workouts (\(index.count) total):"]
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

        guard !thisWeek.isEmpty else { return "No workouts this week." }

        let totalWorkouts = thisWeek.count
        let totalVolume = thisWeek.reduce(0.0) { $0 + $1.totalVolume }
        let totalSets = thisWeek.reduce(0) { $0 + $1.totalSets }
        let totalExercises = thisWeek.reduce(0) { $0 + $1.exerciseCount }
        let uniqueExercises = Set(thisWeek.flatMap(\.exerciseNames))

        return """
        Workouts: \(totalWorkouts)
        Total volume: \(String(format: "%.0f", totalVolume)) lbs
        Total sets: \(totalSets)
        Total exercises: \(totalExercises) (\(uniqueExercises.count) unique: \(uniqueExercises.joined(separator: ", ")))
        """
    }
}
