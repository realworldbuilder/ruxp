import Foundation

/// AI intelligence engine for the Home tab — computes smart greetings, workout suggestions, 
/// contextual nudges, and insights based on workout history and patterns.
@MainActor
final class HomeIntelligenceEngine {
    private let workoutStore: WorkoutStore
    private let calendar = Calendar.current
    
    init(workoutStore: WorkoutStore) {
        self.workoutStore = workoutStore
    }
    
    // MARK: - Smart Greeting
    
    var smartGreeting: String {
        let hour = calendar.component(.hour, from: Date())
        let timeGreeting = timeBasedGreeting(for: hour)
        
        let workoutContext = workoutAwareGreeting()
        
        if workoutContext.isEmpty {
            return timeGreeting
        } else {
            return "\(timeGreeting) \(workoutContext)"
        }
    }
    
    private func timeBasedGreeting(for hour: Int) -> String {
        switch hour {
        case 5..<12:
            return "Good morning."
        case 12..<17:
            return "Good afternoon."
        case 17..<22:
            return "Evening session?"
        default:
            return "Late night training?"
        }
    }
    
    private func workoutAwareGreeting() -> String {
        guard !workoutStore.index.isEmpty else { return "" }
        
        let now = Date()
        let lastWorkout = workoutStore.index.first
        let hour = calendar.component(.hour, from: now)
        
        // If they trained today already, acknowledge it
        if let lastWorkout = lastWorkout,
           calendar.isDate(lastWorkout.startedAt, inSameDayAs: now) {
            return hour < 17 ? "Great session today." : "Nice work today."
        }
        
        // Check days since last workout and muscle group
        if let daysSinceLast = daysSinceLastWorkout(),
           let lastMuscleGroup = lastWorkout?.muscleGroupFocus {
            
            if daysSinceLast >= 3 {
                let suggestedGroup = suggestNextMuscleGroup(lastGroup: lastMuscleGroup, daysSince: daysSinceLast)
                return "Last \(lastMuscleGroup.lowercased()) was \(daysSinceLast) days ago — \(suggestedGroup.lowercased())?"
            } else if daysSinceLast == 1 && hour >= 17 {
                return "Your best workouts happen around this time."
            }
        }
        
        return ""
    }
    
    private func daysSinceLastWorkout() -> Int? {
        guard let lastWorkout = workoutStore.index.first else { return nil }
        return calendar.dateComponents([.day], from: lastWorkout.startedAt, to: Date()).day
    }
    
    private func suggestNextMuscleGroup(lastGroup: String, daysSince: Int) -> String {
        // Simple push/pull/legs rotation logic
        switch lastGroup.lowercased() {
        case let x where x.contains("push"):
            return "Pull Day"
        case let x where x.contains("pull"):
            return "Leg Day"
        case let x where x.contains("leg"):
            return "Push Day"
        case let x where x.contains("chest"):
            return "Pull Day"
        case let x where x.contains("back"):
            return "Leg Day"
        default:
            return daysSince >= 5 ? "Push Day" : "Pull Day"
        }
    }
    
    // MARK: - Workout Suggestion
    
    struct WorkoutSuggestion {
        let title: String
        let reason: String
        let confidence: Double // 0.0 to 1.0
        let type: SuggestionType
        
        enum SuggestionType {
            case muscleGroupRotation
            case dayPattern
            case restDay
            case volumeTarget
        }
    }
    
    var workoutSuggestion: WorkoutSuggestion? {
        let now = Date()
        
        // If they already trained today, return summary instead
        if let todaysWorkout = workoutStore.index.first,
           calendar.isDate(todaysWorkout.startedAt, inSameDayAs: now) {
            return nil // Handled separately by todaysWorkoutSummary
        }
        
        // Check muscle group rotation
        let muscleGroupDays = daysSinceEachMuscleGroup()
        let mostOverdue = muscleGroupDays.max { $0.value < $1.value }
        
        if let overdue = mostOverdue, overdue.value >= 3 {
            return WorkoutSuggestion(
                title: "Suggested: \(friendlyMuscleGroupName(overdue.key))",
                reason: "\(overdue.value) days since last \(overdue.key.lowercased())",
                confidence: min(1.0, Double(overdue.value - 2) / 5.0),
                type: .muscleGroupRotation
            )
        }
        
        // Check day of week patterns
        let weekday = calendar.component(.weekday, from: now)
        if let dayPattern = mostCommonMuscleGroupForWeekday(weekday) {
            return WorkoutSuggestion(
                title: "Suggested: \(friendlyMuscleGroupName(dayPattern.muscleGroup))",
                reason: "You usually train \(dayPattern.muscleGroup.lowercased()) on \(weekdayName(weekday))",
                confidence: dayPattern.confidence,
                type: .dayPattern
            )
        }
        
        // Default suggestion based on simple rotation
        let lastGroup = workoutStore.index.first?.muscleGroupFocus ?? ""
        let suggested = suggestNextMuscleGroup(lastGroup: lastGroup, daysSince: daysSinceLastWorkout() ?? 1)
        
        return WorkoutSuggestion(
            title: "Suggested: \(suggested)",
            reason: "Based on your training split",
            confidence: 0.7,
            type: .muscleGroupRotation
        )
    }
    
    var todaysWorkoutSummary: String? {
        guard let todaysWorkout = workoutStore.index.first,
              calendar.isDate(todaysWorkout.startedAt, inSameDayAs: Date()) else {
            return nil
        }
        
        let volume = formatVolume(todaysWorkout.totalVolume)
        let duration = todaysWorkout.duration.map { formatDuration($0) } ?? ""
        
        if !duration.isEmpty {
            return "Great session today — \(volume) volume in \(duration)"
        } else {
            return "Great session today — \(volume) volume"
        }
    }
    
    // MARK: - Weekly Streak
    
    struct WeeklyStreak {
        let workoutDays: [Bool] // Mon-Sun, true = worked out
        let currentDayIndex: Int // 0 = Mon, 6 = Sun
        let workoutsThisWeek: Int
        let targetDays: Int = 5 // Could be user configurable
        
        var streakText: String {
            "\(workoutsThisWeek) of \(targetDays) days this week"
        }
    }
    
    var weeklyStreak: WeeklyStreak {
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let currentDayIndex = weekday == 1 ? 6 : weekday - 2 // Convert Sunday=1 to Mon=0 indexing
        
        guard let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return WeeklyStreak(workoutDays: Array(repeating: false, count: 7), currentDayIndex: currentDayIndex, workoutsThisWeek: 0)
        }
        
        var workoutDays = Array(repeating: false, count: 7)
        var workoutsThisWeek = 0
        
        let thisWeekWorkouts = workoutStore.index.filter { 
            $0.startedAt >= startOfWeek && $0.startedAt <= now 
        }
        
        for workout in thisWeekWorkouts {
            let workoutWeekday = calendar.component(.weekday, from: workout.startedAt)
            let dayIndex = workoutWeekday == 1 ? 6 : workoutWeekday - 2 // Convert to Mon=0 indexing
            
            if !workoutDays[dayIndex] {
                workoutDays[dayIndex] = true
                workoutsThisWeek += 1
            }
        }
        
        return WeeklyStreak(
            workoutDays: workoutDays,
            currentDayIndex: currentDayIndex,
            workoutsThisWeek: workoutsThisWeek
        )
    }
    
    // MARK: - Smart Nudges
    
    enum NudgeType {
        case missedMuscleGroup
        case streak
        case volumeTrend
        case restDay
    }
    
    struct SmartNudge {
        let message: String
        let type: NudgeType
        let priority: Int // Higher = more important
    }
    
    var smartNudges: [SmartNudge] {
        var nudges: [SmartNudge] = []
        
        // Check for missed muscle groups (8+ days)
        let muscleGroupDays = daysSinceEachMuscleGroup()
        for (group, days) in muscleGroupDays {
            if days >= 8 {
                nudges.append(SmartNudge(
                    message: "You haven't trained \(group.lowercased()) in \(days) days",
                    type: .missedMuscleGroup,
                    priority: days
                ))
            }
        }
        
        // Check streak
        let streak = consecutiveDayStreak()
        if streak >= 3 {
            nudges.append(SmartNudge(
                message: "\(streak)-day streak 🔥 Keep it going",
                type: .streak,
                priority: streak
            ))
        }
        
        // Check for rest day recommendation
        if shouldSuggestRestDay() {
            nudges.append(SmartNudge(
                message: "Rest day? Recovery is gains too.",
                type: .restDay,
                priority: 5
            ))
        }
        
        // Volume trend
        if let volumeTrend = weeklyVolumeTrend() {
            nudges.append(SmartNudge(
                message: volumeTrend,
                type: .volumeTrend,
                priority: 3
            ))
        }
        
        // Return top 2 most relevant nudges
        return Array(nudges.sorted { $0.priority > $1.priority }.prefix(2))
    }
    
    // MARK: - Recent Workout Cards
    
    struct RecentWorkoutCard {
        let workoutIndex: WorkoutSessionIndex
        let aiSummary: String
    }
    
    var recentWorkoutCards: [RecentWorkoutCard] {
        let recent = Array(workoutStore.index.prefix(3))
        
        return recent.map { workout in
            RecentWorkoutCard(
                workoutIndex: workout,
                aiSummary: generateWorkoutSummary(for: workout)
            )
        }
    }
    
    // MARK: - Private Helpers
    
    private func daysSinceEachMuscleGroup() -> [String: Int] {
        var lastSeen: [String: Date] = [:]
        let muscleGroups = ["Push", "Pull", "Legs", "Chest", "Back", "Shoulders", "Arms"]
        
        for workout in workoutStore.index {
            let focus = workout.muscleGroupFocus
            for group in muscleGroups {
                if focus.localizedCaseInsensitiveContains(group) && lastSeen[group] == nil {
                    lastSeen[group] = workout.startedAt
                }
            }
        }
        
        let now = Date()
        var result: [String: Int] = [:]
        
        for group in muscleGroups {
            if let lastDate = lastSeen[group] {
                result[group] = calendar.dateComponents([.day], from: lastDate, to: now).day ?? 0
            }
        }
        
        return result
    }
    
    private func mostCommonMuscleGroupForWeekday(_ weekday: Int) -> (muscleGroup: String, confidence: Double)? {
        var patterns: [String: Int] = [:]
        
        for workout in workoutStore.index {
            let workoutWeekday = calendar.component(.weekday, from: workout.startedAt)
            if workoutWeekday == weekday {
                patterns[workout.muscleGroupFocus, default: 0] += 1
            }
        }
        
        guard let mostCommon = patterns.max(by: { $0.value < $1.value }),
              mostCommon.value >= 2 else { return nil }
        
        let total = patterns.values.reduce(0, +)
        let confidence = Double(mostCommon.value) / Double(total)
        
        return (mostCommon.key, confidence)
    }
    
    private func consecutiveDayStreak() -> Int {
        guard !workoutStore.index.isEmpty else { return 0 }
        
        let now = Date()
        var streak = 0
        var currentDate = now
        
        for i in 0..<14 { // Check last 14 days max
            let hasWorkout = workoutStore.index.contains { 
                calendar.isDate($0.startedAt, inSameDayAs: currentDate) 
            }
            
            if hasWorkout {
                streak += 1
            } else if i > 0 { // Don't break streak on first day if today has no workout yet
                break
            }
            
            currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
        }
        
        return streak
    }
    
    private func shouldSuggestRestDay() -> Bool {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let dayBefore = calendar.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        
        let trainedYesterday = workoutStore.index.contains { calendar.isDate($0.startedAt, inSameDayAs: yesterday) }
        let trainedDayBefore = workoutStore.index.contains { calendar.isDate($0.startedAt, inSameDayAs: dayBefore) }
        
        return trainedYesterday && trainedDayBefore
    }
    
    private func weeklyVolumeTrend() -> String? {
        let now = Date()
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart),
              let lastWeekEnd = calendar.date(byAdding: .day, value: 6, to: lastWeekStart) else { return nil }
        
        let thisWeekVolume = workoutStore.index
            .filter { $0.startedAt >= thisWeekStart }
            .reduce(0) { $0 + $1.totalVolume }
        
        let lastWeekVolume = workoutStore.index
            .filter { $0.startedAt >= lastWeekStart && $0.startedAt <= lastWeekEnd }
            .reduce(0) { $0 + $1.totalVolume }
        
        guard lastWeekVolume > 0 else { return nil }
        
        let percentChange = ((thisWeekVolume - lastWeekVolume) / lastWeekVolume) * 100
        
        if percentChange >= 15 {
            return "Volume up \(Int(percentChange))% this week vs last"
        } else if percentChange <= -15 {
            return "Volume down \(Int(abs(percentChange)))% this week"
        }
        
        return nil
    }
    
    private func generateWorkoutSummary(for workout: WorkoutSessionIndex) -> String {
        let volume = formatVolume(workout.totalVolume)
        let exerciseCount = workout.exerciseNames.count
        
        if exerciseCount <= 2 {
            return "\(volume) volume • \(workout.exerciseNames.joined(separator: ", "))"
        } else {
            return "\(volume) volume • \(exerciseCount) exercises"
        }
    }
    
    private func friendlyMuscleGroupName(_ group: String) -> String {
        switch group.lowercased() {
        case "push": return "Push Day"
        case "pull": return "Pull Day" 
        case "legs": return "Leg Day"
        case "chest": return "Chest Day"
        case "back": return "Back Day"
        case "shoulders": return "Shoulder Day"
        case "arms": return "Arms Day"
        default: return "\(group) Day"
        }
    }
    
    private func weekdayName(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let date = calendar.date(bySetting: .weekday, value: weekday, of: Date()) ?? Date()
        return formatter.string(from: date)
    }
    
    private func formatVolume(_ volume: Double) -> String {
        volume >= 1000 ? String(format: "%.1fk", volume / 1000) : String(format: "%.0f", volume)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }
}

extension WorkoutSessionIndex {
    var muscleGroupFocus: String {
        return title // The title already uses WorkoutTitleGenerator logic
    }
}