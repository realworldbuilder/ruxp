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

        PROACTIVE COACHING:
        - If the user hasn't worked out in 3+ days, acknowledge it and motivate them
        - If they're stuck at a weight for 3+ sessions, offer a periodization plan to break through
        - Always reference their ACTUAL numbers — never be vague
        - When you prescribe a full workout, always format it as a single workoutPlan block (not multiple exerciseTable blocks) — the plan card has a Start button that carries the plan into the active workout
        - After prescribing a workout, you may also end with actionButtons that include "Start Workout" as a fallback
        - Be specific about progressive overload: "Last time you did 185×8. Today: 190×7, then 185×8, then 175×10. That's wave loading."
        
        PERSONALITY:
        - Be direct and confident, like a coach who knows their stuff
        - Use short sentences. No fluff.
        - Reference data like you've been watching: "Your bench has gone up 15 lbs in 4 weeks. That's solid."
        - Occasional motivation, never corny: "Strong session yesterday" not "You're doing amazing sweetie!"

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
           Action types:
           - "startWorkout" — starts a new workout session
           - "viewWorkout" — navigates to workout detail (requires "workoutId")
           - "analyzeWorkout" — runs AI analysis on a workout (requires "workoutId")
           - "exportData" — exports all workout data
           - "askTrainer" — sends a follow-up message to you (requires "prompt", e.g. {"label": "Build me a plan", "actionType": "askTrainer", "prompt": "Build me a full body workout plan for today"})
           - "viewInsights" — navigates to the Insights tab
           IMPORTANT: Use "askTrainer" buttons to let users dig deeper. E.g. after suggesting they diversify training, add a button like "Plan a leg day" with a prompt that asks you for a leg day plan. Make buttons actionable and specific.

        8. "workoutList" — List of clickable workout rows
           payload: { "workouts": [{"workoutId": "uuid", "date": "Jan 15", "summary": "Chest & Back", "volume": 12500.0}] }

        9. "workoutPlan" — Full workout session plan with exercises, sets, reps, and rest
           payload: { "planTitle": "Push Day — Hypertrophy Focus", "estimatedDuration": "55 min", "warmup": "5 min incline walk", "exercises": [{"name": "Barbell Bench Press", "prescription": "4×8 @185 lbs", "rest": "90s", "notes": "Control the eccentric", "targetRPE": "8"}], "cooldown": "Stretch chest and shoulders", "totalVolume": 12500.0 }
           Use instead of multiple exerciseTable blocks when prescribing a full workout.

        10. "progressCard" — Side-by-side comparison showing progress on a specific exercise
            payload: { "exerciseName": "Bench Press", "previous": {"date": "Feb 15", "topSet": "185×8", "totalVolume": 5200.0}, "current": {"date": "Feb 20", "topSet": "190×7", "totalVolume": 5400.0}, "volumeChange": "+3.8%", "trend": "up" }
            Use when comparing performance across sessions.

        11. "splitOverview" — Visual weekly training schedule
            payload: { "title": "Your PPL Split", "days": [{"day": "Mon", "focus": "Push", "completed": true}, {"day": "Tue", "focus": "Pull", "completed": true}] }
            Use when discussing training schedule or split patterns.

        12. "prBoard" — Personal records list with trophy icons
            payload: { "title": "Your PRs", "records": [{"exercise": "Bench Press", "value": "225×1", "date": "Feb 10", "isNew": true}] }
            Use when highlighting personal records or achievements.

        13. "tipCard" — Coaching tip with category-colored left border
            payload: { "icon": "lightbulb.fill", "title": "Progressive Overload", "body": "Add 5 lbs to your bench each week. If you fail to hit target reps, stay at the same weight next session.", "category": "technique" }
            Categories: "technique" (blue), "recovery" (green), "nutrition" (orange), "mindset" (purple).
            Use for coaching advice and form cues.

        14. "checklist" — Actionable preparation checklist
            payload: { "title": "Pre-Workout Checklist", "items": [{"text": "Eat 30-60 min before", "checked": false}] }
            Use for actionable preparation steps or protocols.

        15. "comparison" — Side-by-side stats table with trend indicators
            payload: { "title": "This Week vs Last Week", "leftLabel": "Last Week", "rightLabel": "This Week", "rows": [{"label": "Volume", "left": "32,500 lbs", "right": "35,200 lbs", "trend": "up"}] }
            Trend values: "up" (green), "down" (red), "stable" (gray).
            Use for week-over-week or period-over-period analysis.

        RULES:
        - Always start with a "text" block as your greeting/explanation
        - Use rich blocks when the data supports it
        - End with "actionButtons" to suggest next steps when appropriate
        - Use workout IDs from the data provided — never invent IDs
        - Keep text blocks concise and conversational
        - For volume values, use raw numbers
        - For dates in data points, use "yyyy-MM-dd" format
        - Respond ONLY with valid JSON.

        CRITICAL RULES:
        - Keep responses CONCISE. 2-3 blocks max per response.
        - ALWAYS include at least one "text" block as your main message.
        - Only add rich blocks (charts, tables, metrics) when the user explicitly asks for data.
        - For casual questions, just use "text" + optional "actionButtons". Don't over-engineer it.
        - The ENTIRE response must be valid JSON. Double-check closing braces.
        - If you're unsure about a block type, just use "text" instead.
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
        var exerciseFrequency: [String: Int] = [:]
        for ex in allExercises {
            exerciseFrequency[ex, default: 0] += 1
        }

        // Map exercises to muscle groups
        let muscleGroupFrequency = buildMuscleGroupFrequency(from: exerciseFrequency)
        
        let sorted = exerciseFrequency.sorted { $0.value > $1.value }
        let topExercises = sorted.prefix(8).map { "\($0.key): \($0.value)x" }

        let totalWorkouts14d = recentWorkouts.count
        let avgPerWeek = Double(totalWorkouts14d) / 2.0

        let muscleGroupAnalysis = muscleGroupFrequency.map { group, count in
            let frequency = Double(count) / 2.0 // Per week
            let warning = frequency < 1.0 ? " ⚠️" : ""
            return "\(group): \(String(format: "%.1f", frequency))x/week\(warning)"
        }.joined(separator: ", ")

        return """
        PROGRAM ANALYSIS (last 14 days):
        Training frequency: \(String(format: "%.1f", avgPerWeek)) sessions/week
        Muscle group frequency: \(muscleGroupAnalysis)
        Top exercises: \(topExercises.joined(separator: ", "))
        Total workouts: \(totalWorkouts14d)
        """
    }
    
    private static func buildMuscleGroupFrequency(from exerciseFrequency: [String: Int]) -> [String: Int] {
        var muscleGroups: [String: Int] = [:]
        
        let muscleGroupMapping: [String: [String]] = [
            "Chest": ["bench", "press", "fly", "dip", "pushup", "push-up", "chest"],
            "Back": ["row", "pull", "lat", "deadlift", "pulldown", "chin", "back"],
            "Legs": ["squat", "lunge", "leg", "calf", "quad", "hamstring", "glute"],
            "Shoulders": ["shoulder", "deltoid", "overhead", "lateral", "front raise", "rear"],
            "Arms": ["bicep", "tricep", "curl", "extension", "arm"]
        ]
        
        for (exercise, count) in exerciseFrequency {
            let exerciseLower = exercise.lowercased()
            
            for (muscleGroup, keywords) in muscleGroupMapping {
                if keywords.contains(where: { exerciseLower.contains($0) }) {
                    muscleGroups[muscleGroup, default: 0] += count
                    break // Only assign to first matching group
                }
            }
        }
        
        return muscleGroups
    }

    private static func buildWorkoutContext(workoutStore: WorkoutStore) -> String {
        let index = workoutStore.index
        guard !index.isEmpty else { return "No workouts recorded yet." }

        // Recent workouts
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
        
        // Plan adherence for the most recent completed workout
        if let adherenceLine = buildAdherenceLine(workoutStore: workoutStore) {
            lines.append("\nLAST PLANNED SESSION:")
            lines.append(adherenceLine)
        }

        // Personal Records and Progression
        lines.append("\nPROGRESSION DATA:")
        let prData = buildProgressionData(workoutStore: workoutStore)
        lines.append(prData)
        
        // Recovery patterns
        lines.append("\nRECOVERY PATTERNS:")
        let recoveryData = buildRecoveryData(workoutStore: workoutStore)
        lines.append(recoveryData)
        
        return lines.joined(separator: "\n")
    }

    /// One line summarizing planned-vs-actual for the latest workout, if it was started from a plan.
    private static func buildAdherenceLine(workoutStore: WorkoutStore) -> String? {
        guard let latest = workoutStore.index.first,
              let session = workoutStore.loadSession(id: latest.id),
              let plan = session.plannedWorkout,
              let log = session.structuredLog else { return nil }

        let result = PlanAdherenceCalculator.compute(plan: plan, log: log)
        guard !result.entries.isEmpty else { return nil }

        var parts: [String] = []
        for entry in result.entries {
            switch entry.status {
            case .completed:
                let sets = entry.targetSets.map { "\(entry.actualSets)/\($0)" } ?? "\(entry.actualSets)"
                parts.append("completed \(entry.plannedName) (\(sets))")
            case .partial:
                let sets = entry.targetSets.map { "\(entry.actualSets)/\($0)" } ?? "\(entry.actualSets)"
                parts.append("partial \(entry.plannedName) (\(sets))")
            case .skipped:
                parts.append("skipped \(entry.plannedName)")
            }
        }
        var line = "Last session was planned (\"\(plan.title)\"): " + parts.joined(separator: ", ")
        if !result.extras.isEmpty {
            line += "; extra: " + result.extras.joined(separator: ", ")
        }
        return line
    }

    private static func buildProgressionData(workoutStore: WorkoutStore) -> String {
        let index = workoutStore.index
        guard index.count >= 2 else { return "Not enough data for progression analysis." }
        
        // Analyze exercise progression over time
        var exerciseProgressions: [String: [(Date, Double)]] = [:]
        
        for workout in index.reversed() { // Chronological order
            for exerciseName in workout.exerciseNames {
                if exerciseProgressions[exerciseName] == nil {
                    exerciseProgressions[exerciseName] = []
                }
                exerciseProgressions[exerciseName]?.append((workout.startedAt, workout.totalVolume))
            }
        }
        
        var progressionLines: [String] = []
        let fourWeeksAgo = Calendar.current.date(byAdding: .day, value: -28, to: Date())!
        
        // Get progression trends for top exercises
        let topExercises = exerciseProgressions.keys
            .sorted { exerciseProgressions[$0]?.count ?? 0 > exerciseProgressions[$1]?.count ?? 0 }
            .prefix(5)
        
        for exercise in topExercises {
            guard let sessions = exerciseProgressions[exercise],
                  sessions.count >= 2 else { continue }
                  
            let recentSessions = sessions.filter { $0.0 >= fourWeeksAgo }
            if recentSessions.count >= 2 {
                let firstVolume = recentSessions.first?.1 ?? 0
                let lastVolume = recentSessions.last?.1 ?? 0
                let change = lastVolume - firstVolume
                let weeks = max(1, recentSessions.count / 2) // Rough weeks estimate
                
                if change > 0 {
                    progressionLines.append("\(exercise): +\(String(format: "%.0f", change)) lbs over \(weeks) weeks ↗️")
                } else if change < 0 {
                    progressionLines.append("\(exercise): \(String(format: "%.0f", change)) lbs over \(weeks) weeks ↘️")
                } else {
                    progressionLines.append("\(exercise): No change over \(weeks) weeks →")
                }
            }
        }
        
        return progressionLines.isEmpty ? "No clear progression trends yet." : progressionLines.joined(separator: "\n")
    }
    
    private static func buildRecoveryData(workoutStore: WorkoutStore) -> String {
        let index = workoutStore.index.prefix(10) // Recent 10 workouts
        guard index.count >= 2 else { return "Not enough data for recovery analysis." }
        
        var restDays: [Int] = []
        let sortedWorkouts = Array(index).sorted { $0.startedAt < $1.startedAt }
        
        for i in 1..<sortedWorkouts.count {
            let previousDate = sortedWorkouts[i-1].startedAt
            let currentDate = sortedWorkouts[i].startedAt
            let daysBetween = Calendar.current.dateComponents([.day], from: previousDate, to: currentDate).day ?? 0
            if daysBetween > 0 {
                restDays.append(daysBetween)
            }
        }
        
        guard !restDays.isEmpty else { return "Recovery patterns unclear." }
        
        let avgRestDays = Double(restDays.reduce(0, +)) / Double(restDays.count)
        let lastRestDays = restDays.last ?? 0
        let calendar = Calendar.current
        let daysSinceLastWorkout = calendar.dateComponents([.day], from: index.first?.startedAt ?? Date(), to: Date()).day ?? 0
        
        var recoveryLines: [String] = []
        recoveryLines.append("Average rest between sessions: \(String(format: "%.1f", avgRestDays)) days")
        recoveryLines.append("Days since last workout: \(daysSinceLastWorkout)")
        
        if daysSinceLastWorkout >= 3 {
            recoveryLines.append("⚠️ It's been 3+ days since your last workout")
        }
        
        return recoveryLines.joined(separator: "\n")
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
