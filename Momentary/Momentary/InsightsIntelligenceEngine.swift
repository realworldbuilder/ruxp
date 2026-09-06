import Foundation
import SwiftUI
import os

/// Intelligence layer for the Insights tab — generates AI-narrated summaries,
/// PR predictions, muscle balance analysis, and smart comparisons.
@Observable
@MainActor
final class InsightsIntelligenceEngine {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "InsightsIntelligenceEngine")
    
    // MARK: - Published State
    
    var aiProgressSummary: String = ""
    var prPredictions: [PRPrediction] = []
    var muscleBalance: MuscleBalanceData = MuscleBalanceData()
    var weeklyComparison: WeeklyComparisonData = WeeklyComparisonData()
    var smartInsights: [SmartInsightCard] = []
    var isGenerating = false
    
    // MARK: - Dependencies
    
    private let insightsStore: InsightsStore
    private let workoutStore: WorkoutStore
    
    init(insightsStore: InsightsStore, workoutStore: WorkoutStore) {
        self.insightsStore = insightsStore
        self.workoutStore = workoutStore
    }
    
    // MARK: - Main Entry Point
    
    func generateIntelligence() async {
        isGenerating = true
        defer { isGenerating = false }
        
        generateAIProgressSummary()
        generatePRPredictions()
        generateMuscleBalance()
        generateWeeklyComparison()
        generateSmartInsights()
        
        Self.logger.info("Intelligence generation complete")
    }
    
    // MARK: - AI-Narrated Progress Summary
    
    private func generateAIProgressSummary() {
        let sessions = loadRecentSessions(count: 10)
        let thisWeekStats = calculateWeekStats(sessions: sessions, weeksBack: 0)
        let lastWeekStats = calculateWeekStats(sessions: sessions, weeksBack: 1)
        let thisMonthStats = calculateMonthStats(sessions: sessions)
        
        // Calculate key changes
        var insights: [String] = []
        
        // Volume change
        if lastWeekStats.totalVolume > 0 {
            let volumeChange = ((thisWeekStats.totalVolume - lastWeekStats.totalVolume) / lastWeekStats.totalVolume) * 100
            if abs(volumeChange) >= 10 {
                let direction = volumeChange > 0 ? "up" : "down"
                insights.append("Your volume is \(direction) \(abs(Int(volumeChange)))% this week")
            }
        }
        
        // PR analysis
        if let recentPR = insightsStore.personalRecords.values.max(by: { $0.date < $1.date }) {
            let daysSincePR = Calendar.current.dateComponents([.day], from: recentPR.date, to: Date()).day ?? 0
            if daysSincePR < 7 {
                insights.append("Nice \(Int(recentPR.weight))lb \(recentPR.exercise) PR!")
            } else if daysSincePR > 21 {
                let topExercise = findStagnatingExercise()
                if !topExercise.isEmpty {
                    insights.append("\(topExercise) is plateauing — try adding pause reps or drop sets")
                }
            }
        }
        
        // Training frequency
        let avgSessionsPerWeek = Double(thisMonthStats.totalWorkouts) / 4.0
        if avgSessionsPerWeek >= 3.5 && avgSessionsPerWeek <= 5.0 {
            insights.append("You're averaging \(String(format: "%.1f", avgSessionsPerWeek)) sessions/week, which is ideal for most goals")
        } else if avgSessionsPerWeek < 3 {
            insights.append("Consider adding 1-2 more sessions per week for better progress")
        }
        
        // Fallback if no insights
        if insights.isEmpty {
            insights.append("Your training is consistent. Focus on progressive overload in your next sessions.")
        }
        
        // Combine into 2-3 sentences
        if insights.count >= 2 {
            aiProgressSummary = insights.prefix(2).joined(separator: ". ") + "."
        } else {
            aiProgressSummary = insights.first ?? "Keep up the great work with your training consistency."
        }
    }
    
    // MARK: - PR Predictions
    
    private func generatePRPredictions() {
        var predictions: [PRPrediction] = []
        
        for (exercise, pr) in insightsStore.personalRecords {
            guard let progressionRate = calculateProgressionRate(for: exercise) else { continue }
            guard progressionRate > 0 else { continue } // Skip stagnating exercises
            
            let nextMilestone = findNextMilestone(currentWeight: pr.weight)
            let weeksToMilestone = Int(ceil((nextMilestone - pr.weight) / progressionRate))
            
            if weeksToMilestone > 0 && weeksToMilestone <= 12 { // Only predict within 3 months
                predictions.append(PRPrediction(
                    exercise: exercise,
                    currentWeight: pr.weight,
                    targetWeight: nextMilestone,
                    weeksEstimate: weeksToMilestone,
                    confidence: calculateConfidence(progressionRate: progressionRate)
                ))
            }
        }
        
        // Sort by soonest predictions first, limit to top 5
        prPredictions = predictions
            .sorted { $0.weeksEstimate < $1.weeksEstimate }
            .prefix(5)
            .map { $0 }
    }
    
    private func calculateProgressionRate(for exercise: String) -> Double? {
        let sessions = loadRecentSessions(count: 20)
        var weights: [(date: Date, weight: Double)] = []
        
        for session in sessions {
            guard let log = session.structuredLog else { continue }
            for exerciseGroup in log.exercises {
                if exerciseGroup.exerciseName.lowercased() == exercise.lowercased() {
                    if let maxWeight = exerciseGroup.sets.compactMap(\.weight).max() {
                        weights.append((date: session.startedAt, weight: maxWeight))
                    }
                }
            }
        }
        
        guard weights.count >= 3 else { return nil }
        weights.sort { $0.date < $1.date }
        
        // Calculate linear regression slope (weight per week)
        let timespan = weights.last!.date.timeIntervalSince(weights.first!.date) / (7 * 24 * 60 * 60) // weeks
        let weightGain = weights.last!.weight - weights.first!.weight
        
        return timespan > 0 ? weightGain / timespan : nil
    }
    
    private func findNextMilestone(currentWeight: Double) -> Double {
        // Common milestone intervals
        let milestones = [5, 10, 25, 50, 100]
        
        for interval in milestones {
            let next = ceil(currentWeight / Double(interval)) * Double(interval)
            if next > currentWeight {
                return next
            }
        }
        
        return currentWeight + 25 // Default to +25lbs
    }
    
    private func calculateConfidence(progressionRate: Double) -> Double {
        // Higher progression rates = higher confidence, capped at 95%
        return min(0.95, 0.5 + (progressionRate * 0.1))
    }
    
    // MARK: - Muscle Group Balance
    
    private func generateMuscleBalance() {
        let sessions = loadRecentSessions(count: 30)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentSessions = sessions.filter { $0.startedAt >= cutoffDate }
        
        var muscleVolumes: [String: Double] = [:]
        
        for session in recentSessions {
            guard let log = session.structuredLog else { continue }
            for exercise in log.exercises {
                let volume = exercise.sets.reduce(0.0) { total, set in
                    total + (Double(set.reps ?? 0) * (set.weight ?? 0))
                }
                
                let muscleGroup = categorizeExercise(exercise.exerciseName)
                muscleVolumes[muscleGroup, default: 0] += volume
            }
        }
        
        // Calculate percentages
        let totalVolume = muscleVolumes.values.reduce(0, +)
        var balanceData: [MuscleBalancePoint] = []
        
        for (muscle, volume) in muscleVolumes {
            let percentage = totalVolume > 0 ? (volume / totalVolume) * 100 : 0
            balanceData.append(MuscleBalancePoint(
                muscleGroup: muscle,
                volume: volume,
                percentage: percentage
            ))
        }
        
        // Find imbalances (one group 3x another)
        let sorted = balanceData.sorted { $0.percentage > $1.percentage }
        var imbalances: [String] = []
        
        if sorted.count >= 2 {
            let highest = sorted[0]
            let lowest = sorted.last!
            if highest.percentage > lowest.percentage * 3 && lowest.percentage < 5 {
                imbalances.append("\(highest.muscleGroup) volume is much higher than \(lowest.muscleGroup)")
            }
            
            // Check push vs pull specifically
            let pushVolume = muscleVolumes["chest", default: 0] + muscleVolumes["shoulders", default: 0]
            let pullVolume = muscleVolumes["back", default: 0]
            if pushVolume > pullVolume * 2.5 {
                imbalances.append("Consider adding more back work to balance push volume")
            }
        }
        
        muscleBalance = MuscleBalanceData(
            muscleGroups: balanceData.sorted { $0.percentage > $1.percentage },
            imbalances: imbalances
        )
    }
    
    private func categorizeExercise(_ exerciseName: String) -> String {
        let muscleMap = WorkoutTitleGenerator.getPrivateMuscleMap()
        let lower = exerciseName.lowercased()
        
        for (group, keywords) in muscleMap {
            if keywords.contains(where: { lower.contains($0) }) {
                return group.capitalized
            }
        }
        
        return "Other"
    }
    
    // MARK: - Weekly Comparison
    
    private func generateWeeklyComparison() {
        let sessions = loadRecentSessions(count: 20)
        let thisWeekStats = calculateWeekStats(sessions: sessions, weeksBack: 0)
        let lastWeekStats = calculateWeekStats(sessions: sessions, weeksBack: 1)
        
        weeklyComparison = WeeklyComparisonData(
            volumeChange: calculateChange(current: thisWeekStats.totalVolume, previous: lastWeekStats.totalVolume),
            workoutChange: calculateChange(current: Double(thisWeekStats.totalWorkouts), previous: Double(lastWeekStats.totalWorkouts)),
            exerciseChange: calculateChange(current: Double(thisWeekStats.uniqueExercises.count), previous: Double(lastWeekStats.uniqueExercises.count)),
            setsChange: calculateChange(current: Double(thisWeekStats.totalSets), previous: Double(lastWeekStats.totalSets))
        )
    }
    
    private func calculateChange(current: Double, previous: Double) -> WeeklyChange {
        guard previous > 0 else {
            return WeeklyChange(
                direction: current > 0 ? .up : .same,
                percentage: 0,
                displayValue: current > 0 ? "+\(Int(current))" : "0"
            )
        }
        
        let percentChange = ((current - previous) / previous) * 100
        let direction: ChangeDirection
        
        if abs(percentChange) < 5 {
            direction = .same
        } else if percentChange > 0 {
            direction = .up
        } else {
            direction = .down
        }
        
        let displayValue: String
        if direction == .same {
            displayValue = "="
        } else {
            displayValue = "\(percentChange > 0 ? "↑" : "↓") \(abs(Int(percentChange)))%"
        }
        
        return WeeklyChange(
            direction: direction,
            percentage: abs(percentChange),
            displayValue: displayValue
        )
    }
    
    // MARK: - Smart Insights
    
    private func generateSmartInsights() {
        var insights: [SmartInsightCard] = []
        
        // Recovery insight
        if let recoveryInsight = generateRecoveryInsight() {
            insights.append(recoveryInsight)
        }
        
        // Consistency insight
        if let consistencyInsight = generateConsistencyInsight() {
            insights.append(consistencyInsight)
        }
        
        // Strength curve insight
        if let strengthInsight = generateStrengthCurveInsight() {
            insights.append(strengthInsight)
        }
        
        smartInsights = insights
    }
    
    private func generateRecoveryInsight() -> SmartInsightCard? {
        let sessions = loadRecentSessions(count: 10)
        guard sessions.count >= 5 else { return nil }
        
        var gaps: [TimeInterval] = []
        for i in 0..<(sessions.count - 1) {
            let gap = sessions[i].startedAt.timeIntervalSince(sessions[i + 1].startedAt)
            gaps.append(gap)
        }
        
        let avgGapDays = gaps.reduce(0, +) / Double(gaps.count) / (24 * 60 * 60)
        
        let insight: String
        let recommendation: String
        
        if avgGapDays > 3 {
            insight = "You're averaging \(String(format: "%.1f", avgGapDays)) days between workouts"
            recommendation = "Consider adding one more session per week for better momentum"
        } else if avgGapDays < 1 {
            insight = "You're training very frequently (\(String(format: "%.1f", avgGapDays)) days between sessions)"
            recommendation = "Make sure you're getting adequate recovery between sessions"
        } else {
            insight = "Your recovery timing looks optimal (\(String(format: "%.1f", avgGapDays)) days between sessions)"
            recommendation = "This frequency supports good progress and recovery balance"
        }
        
        return SmartInsightCard(
            title: "Recovery Analysis",
            insight: insight,
            recommendation: recommendation,
            type: .recovery
        )
    }
    
    private func generateConsistencyInsight() -> SmartInsightCard? {
        let sessions = loadRecentSessions(count: 20)
        let daysOfWeek = sessions.compactMap { Calendar.current.component(.weekday, from: $0.startedAt) }
        
        // Need at least 5 sessions across 2+ different days for this to be meaningful
        guard daysOfWeek.count >= 5 else { return nil }
        
        let frequency = Dictionary(daysOfWeek.map { ($0, 1) }, uniquingKeysWith: +)
        guard frequency.count >= 2 else { return nil } // Need variety to compare
        
        let mostConsistent = frequency.max { $0.value < $1.value }
        let leastConsistent = frequency.min { $0.value < $1.value }
        
        guard let most = mostConsistent, let least = leastConsistent, most.key != least.key else { return nil }
        
        let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        
        return SmartInsightCard(
            title: "Training Consistency",
            insight: "You train most on \(dayNames[most.key]) (\(most.value) times) and least on \(dayNames[least.key]) (\(least.value) times)",
            recommendation: "Consider balancing your weekly schedule if your \(dayNames[most.key]) sessions are too intense",
            type: .consistency
        )
    }
    
    private func generateStrengthCurveInsight() -> SmartInsightCard? {
        var exerciseProgression: [(exercise: String, rate: Double)] = []
        
        for exercise in insightsStore.personalRecords.keys {
            if let rate = calculateProgressionRate(for: exercise), rate != 0 {
                exerciseProgression.append((exercise: exercise, rate: rate))
            }
        }
        
        guard exerciseProgression.count >= 2 else { return nil }
        
        let fastest = exerciseProgression.max { $0.rate < $1.rate }
        let slowest = exerciseProgression.min { $0.rate < $1.rate }
        
        guard let fast = fastest, let slow = slowest else { return nil }
        
        return SmartInsightCard(
            title: "Strength Curve",
            insight: "\(fast.exercise) is progressing fastest (+\(String(format: "%.1f", fast.rate))lbs/week) while \(slow.exercise) is stalling",
            recommendation: "Try different rep ranges or accessory work for \(slow.exercise)",
            type: .strengthCurve
        )
    }
    
    // MARK: - Helper Functions
    
    private func loadRecentSessions(count: Int) -> [WorkoutSession] {
        workoutStore.index
            .prefix(count)
            .compactMap { workoutStore.loadSession(id: $0.id) }
            .sorted { $0.startedAt > $1.startedAt }
    }
    
    private func calculateWeekStats(sessions: [WorkoutSession], weeksBack: Int) -> WeekStats {
        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: now) ?? now
        let weekEnd = calendar.date(byAdding: .day, value: -7 * weeksBack, to: now) ?? now
        
        let weekSessions = sessions.filter { session in
            session.startedAt >= calendar.date(byAdding: .day, value: -7, to: weekEnd) ?? Date() &&
            session.startedAt < weekEnd
        }
        
        let totalVolume = weekSessions.reduce(0.0) { total, session in
            guard let log = session.structuredLog else { return total }
            return total + log.exercises.reduce(0.0) { exerciseTotal, exercise in
                exerciseTotal + exercise.sets.reduce(0.0) { setTotal, set in
                    setTotal + (Double(set.reps ?? 0) * (set.weight ?? 0))
                }
            }
        }
        
        let totalSets = weekSessions.reduce(0) { total, session in
            guard let log = session.structuredLog else { return total }
            return total + log.exercises.reduce(0) { $0 + $1.sets.count }
        }
        
        let uniqueExercises = Set(weekSessions.compactMap { session in
            session.structuredLog?.exercises.map(\.exerciseName)
        }.flatMap { $0 })
        
        return WeekStats(
            totalWorkouts: weekSessions.count,
            totalVolume: totalVolume,
            totalSets: totalSets,
            uniqueExercises: uniqueExercises
        )
    }
    
    private func calculateMonthStats(sessions: [WorkoutSession]) -> WeekStats {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let monthSessions = sessions.filter { $0.startedAt >= cutoffDate }
        
        let totalVolume = monthSessions.reduce(0.0) { total, session in
            guard let log = session.structuredLog else { return total }
            return total + log.exercises.reduce(0.0) { exerciseTotal, exercise in
                exerciseTotal + exercise.sets.reduce(0.0) { setTotal, set in
                    setTotal + (Double(set.reps ?? 0) * (set.weight ?? 0))
                }
            }
        }
        
        let totalSets = monthSessions.reduce(0) { total, session in
            guard let log = session.structuredLog else { return total }
            return total + log.exercises.reduce(0) { $0 + $1.sets.count }
        }
        
        let uniqueExercises = Set(monthSessions.compactMap { session in
            session.structuredLog?.exercises.map(\.exerciseName)
        }.flatMap { $0 })
        
        return WeekStats(
            totalWorkouts: monthSessions.count,
            totalVolume: totalVolume,
            totalSets: totalSets,
            uniqueExercises: uniqueExercises
        )
    }
    
    private func findStagnatingExercise() -> String {
        let topPRs = insightsStore.personalRecords.values
            .sorted { $0.weight > $1.weight }
            .prefix(3)
        
        for pr in topPRs {
            let daysSincePR = Calendar.current.dateComponents([.day], from: pr.date, to: Date()).day ?? 0
            if daysSincePR > 21 {
                return pr.exercise
            }
        }
        
        return topPRs.first?.exercise ?? ""
    }
}

// MARK: - Extension for WorkoutTitleGenerator

extension WorkoutTitleGenerator {
    static func getPrivateMuscleMap() -> [String: Set<String>] {
        return [
            "chest": ["bench", "chest", "fly", "flye", "pec", "dumbbell press", "incline press", "decline press", "push up", "pushup", "dip"],
            "back": ["row", "pull up", "pullup", "chin up", "chinup", "lat", "deadlift", "pulldown", "pull-down", "back extension", "barbell row", "cable row", "t-bar"],
            "shoulders": ["shoulder", "overhead press", "ohp", "military press", "lateral raise", "front raise", "rear delt", "face pull", "shrug", "delt"],
            "legs": ["squat", "leg press", "lunge", "hamstring", "quad", "calf", "calves", "leg curl", "leg extension", "hip thrust", "glute", "rdl", "romanian", "goblet"],
            "arms": ["bicep", "curl", "tricep", "triceps", "hammer curl", "preacher", "skull crusher", "pushdown", "extension"],
            "core": ["ab", "abs", "crunch", "plank", "sit up", "situp", "cable crunch", "leg raise", "oblique", "core"]
        ]
    }
}

// MARK: - Data Models

struct PRPrediction: Identifiable {
    let id = UUID()
    let exercise: String
    let currentWeight: Double
    let targetWeight: Double
    let weeksEstimate: Int
    let confidence: Double
    
    var displayText: String {
        "\(Int(targetWeight))lb \(exercise) in ~\(weeksEstimate) weeks"
    }
}

struct MuscleBalanceData {
    var muscleGroups: [MuscleBalancePoint] = []
    var imbalances: [String] = []
}

struct MuscleBalancePoint: Identifiable {
    let id = UUID()
    let muscleGroup: String
    let volume: Double
    let percentage: Double
}

struct WeeklyComparisonData {
    var volumeChange: WeeklyChange = WeeklyChange(direction: .same, percentage: 0, displayValue: "=")
    var workoutChange: WeeklyChange = WeeklyChange(direction: .same, percentage: 0, displayValue: "=")
    var exerciseChange: WeeklyChange = WeeklyChange(direction: .same, percentage: 0, displayValue: "=")
    var setsChange: WeeklyChange = WeeklyChange(direction: .same, percentage: 0, displayValue: "=")
}

struct WeeklyChange {
    let direction: ChangeDirection
    let percentage: Double
    let displayValue: String
    
    var color: Color {
        switch direction {
        case .up: return .green
        case .down: return .red
        case .same: return .secondary
        }
    }
}

enum ChangeDirection {
    case up, down, same
}

struct SmartInsightCard: Identifiable {
    let id = UUID()
    let title: String
    let insight: String
    let recommendation: String
    let type: SmartInsightType
}

enum SmartInsightType {
    case recovery, consistency, strengthCurve
    
    var icon: String {
        switch self {
        case .recovery: return "bed.double.fill"
        case .consistency: return "calendar"
        case .strengthCurve: return "chart.line.uptrend.xyaxis"
        }
    }
    
    var color: Color {
        switch self {
        case .recovery: return .blue
        case .consistency: return .orange
        case .strengthCurve: return .green
        }
    }
}

// Helper struct for week calculations
private struct WeekStats {
    let totalWorkouts: Int
    let totalVolume: Double
    let totalSets: Int
    let uniqueExercises: Set<String>
}