import Foundation
import SwiftUI
import os

@Observable
@MainActor
final class InsightsEngine {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "InsightsEngine")

    var stories: [InsightStory] = []
    var dashboardMetrics: [DashboardMetric] = []
    var isGenerating = false

    private let workoutStore: WorkoutStore
    private let aiService: AIService
    private var lastDataHash: Int?

    init(workoutStore: WorkoutStore, aiService: AIService) {
        self.workoutStore = workoutStore
        self.aiService = aiService
    }

    // MARK: - Main Entry Point

    func generateInsights() async {
        let currentHash = computeDataHash()
        guard currentHash != lastDataHash else { return }

        isGenerating = true
        defer {
            isGenerating = false
            lastDataHash = currentHash
        }

        let index = workoutStore.index
        guard !index.isEmpty else {
            stories = []
            dashboardMetrics = []
            return
        }

        generateDashboardMetrics(from: index)

        var newStories: [InsightStory] = []
        let recentSessions = loadRecentSessions(count: 10)

        if let weeklyStory = buildWeeklyReviewStory(from: index, sessions: recentSessions) {
            newStories.append(weeklyStory)
        }
        if let prStory = buildPRStory(from: recentSessions) {
            newStories.append(prStory)
        }
        if let trendStory = buildTrendStory(from: index, sessions: recentSessions) {
            newStories.append(trendStory)
        }
        if let goalStory = buildGoalStory(from: recentSessions) {
            newStories.append(goalStory)
        }

        stories = newStories
        await enhanceStoriesWithAI(index: index, sessions: recentSessions)
    }

    // MARK: - Dashboard Metrics

    private func generateDashboardMetrics(from index: [WorkoutSessionIndex]) {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now)!

        let thisWeek = index.filter { $0.startedAt >= weekAgo }
        let lastWeek = index.filter { $0.startedAt >= twoWeeksAgo && $0.startedAt < weekAgo }

        let thisWeekWorkouts = thisWeek.count
        let lastWeekWorkouts = lastWeek.count
        let thisWeekVolume = thisWeek.reduce(0.0) { $0 + $1.totalVolume }
        let lastWeekVolume = lastWeek.reduce(0.0) { $0 + $1.totalVolume }
        let thisWeekExercises = thisWeek.reduce(0) { $0 + $1.exerciseCount }
        let lastWeekExercises = lastWeek.reduce(0) { $0 + $1.exerciseCount }
        let thisWeekSets = thisWeek.reduce(0) { $0 + $1.totalSets }
        let lastWeekSets = lastWeek.reduce(0) { $0 + $1.totalSets }

        dashboardMetrics = [
            DashboardMetric(
                title: "Workouts", value: "\(thisWeekWorkouts)", subtitle: "this week",
                icon: "figure.strengthtraining.traditional", color: .green,
                trend: trend(current: Double(thisWeekWorkouts), previous: Double(lastWeekWorkouts)),
                trendValue: trendString(current: Double(thisWeekWorkouts), previous: Double(lastWeekWorkouts))
            ),
            DashboardMetric(
                title: "Volume", value: formatVolume(thisWeekVolume), subtitle: "total lbs",
                icon: "scalemass.fill", color: .blue,
                trend: trend(current: thisWeekVolume, previous: lastWeekVolume),
                trendValue: trendString(current: thisWeekVolume, previous: lastWeekVolume)
            ),
            DashboardMetric(
                title: "Exercises", value: "\(thisWeekExercises)", subtitle: "unique movements",
                icon: "dumbbell.fill", color: .orange,
                trend: trend(current: Double(thisWeekExercises), previous: Double(lastWeekExercises)),
                trendValue: trendString(current: Double(thisWeekExercises), previous: Double(lastWeekExercises))
            ),
            DashboardMetric(
                title: "Sets", value: "\(thisWeekSets)", subtitle: "total sets",
                icon: "repeat", color: .purple,
                trend: trend(current: Double(thisWeekSets), previous: Double(lastWeekSets)),
                trendValue: trendString(current: Double(thisWeekSets), previous: Double(lastWeekSets))
            ),
        ]
    }

    // MARK: - Story Builders

    private func buildWeeklyReviewStory(from index: [WorkoutSessionIndex], sessions: [WorkoutSession]) -> InsightStory? {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let thisWeek = index.filter { $0.startedAt >= weekAgo }
        guard !thisWeek.isEmpty else { return nil }

        let totalVolume = thisWeek.reduce(0.0) { $0 + $1.totalVolume }
        let totalSets = thisWeek.reduce(0) { $0 + $1.totalSets }
        let volumePoints = calculateDailyVolume(from: thisWeek)

        var pages: [InsightPage] = []
        pages.append(InsightPage(
            title: "This Week's Summary",
            content: "You completed \(thisWeek.count) workout\(thisWeek.count == 1 ? "" : "s") this week with \(totalSets) total sets and \(formatVolume(totalVolume)) total volume.",
            chartData: volumePoints.isEmpty ? nil : InsightChartData(chartType: .volumeOverTime, dataPoints: volumePoints)
        ))

        let exerciseNames = thisWeek.flatMap(\.exerciseNames)
        let freq = Dictionary(exerciseNames.map { ($0, 1) }, uniquingKeysWith: +)
        let topExercises = freq.sorted { $0.value > $1.value }.prefix(3)
        if !topExercises.isEmpty {
            let exerciseList = topExercises.map { "\($0.key) (\($0.value)x)" }.joined(separator: ", ")
            pages.append(InsightPage(
                title: "Most Trained",
                content: "Your most frequently trained exercises: \(exerciseList).",
                actionable: "Consider adding variety to balance your training."
            ))
        }

        return InsightStory(
            title: "Weekly Review",
            body: "\(thisWeek.count) workouts, \(formatVolume(totalVolume)) volume",
            type: .weeklyReview, pages: pages,
            preview: "\(thisWeek.count) workouts", generatedAt: Date()
        )
    }

    private func buildPRStory(from sessions: [WorkoutSession]) -> InsightStory? {
        let prs = getPRsWithComparison(from: sessions)
        guard !prs.isEmpty else { return nil }

        let prDataPoints = prs.map { pr in
            ChartDataPoint(label: pr.exercise, value: pr.newWeight, secondaryValue: pr.oldWeight, isPR: true)
        }
        let prList = prs.prefix(3).map { "\($0.exercise): \(Int($0.newWeight)) lbs" }.joined(separator: "\n")

        return InsightStory(
            title: "New PRs",
            body: "\(prs.count) new personal record\(prs.count == 1 ? "" : "s")",
            type: .newPRs,
            pages: [InsightPage(
                title: "New Personal Records",
                content: "You hit \(prs.count) new PR\(prs.count == 1 ? "" : "s")!\n\n\(prList)",
                chartData: InsightChartData(chartType: .prComparison, dataPoints: prDataPoints),
                actionable: "Great progress! Try to maintain this weight for 3+ sets before increasing again."
            )],
            preview: "\(prs.count) PR\(prs.count == 1 ? "" : "s")", generatedAt: Date()
        )
    }

    private func buildTrendStory(from index: [WorkoutSessionIndex], sessions: [WorkoutSession]) -> InsightStory? {
        guard sessions.count >= 2 else { return nil }

        var exerciseHistory: [String: [(date: Date, maxWeight: Double)]] = [:]
        for session in sessions {
            guard let log = session.structuredLog else { continue }
            for exercise in log.exercises {
                let maxWeight = exercise.sets.compactMap(\.weight).max() ?? 0
                if maxWeight > 0 {
                    exerciseHistory[exercise.exerciseName, default: []].append((date: session.startedAt, maxWeight: maxWeight))
                }
            }
        }

        var bestExercise: String?
        var bestIncrease: Double = 0
        var bestPoints: [ChartDataPoint] = []

        for (name, history) in exerciseHistory where history.count >= 2 {
            let sorted = history.sorted { $0.date < $1.date }
            let increase = sorted.last!.maxWeight - sorted.first!.maxWeight
            if increase > bestIncrease {
                bestIncrease = increase
                bestExercise = name
                bestPoints = sorted.map { ChartDataPoint(label: name, value: $0.maxWeight, date: $0.date, isPR: $0.maxWeight == sorted.last!.maxWeight && increase > 0) }
            }
        }

        guard let exercise = bestExercise, bestIncrease > 0 else { return nil }

        return InsightStory(
            title: "Trending Up",
            body: "\(exercise) +\(Int(bestIncrease)) lbs",
            type: .trendingUp,
            pages: [InsightPage(
                title: "\(exercise) is Trending Up",
                content: "Your \(exercise) has increased by \(Int(bestIncrease)) lbs across your recent sessions. Keep up the progressive overload!",
                chartData: InsightChartData(chartType: .progressTrend, dataPoints: bestPoints),
                actionable: "Add 5 lbs next session to keep the momentum going."
            )],
            preview: "+\(Int(bestIncrease)) lbs", generatedAt: Date()
        )
    }

    private func buildGoalStory(from sessions: [WorkoutSession]) -> InsightStory? {
        var maxes: [String: Double] = [:]
        for session in sessions {
            guard let log = session.structuredLog else { continue }
            for exercise in log.exercises {
                let maxWeight = exercise.sets.compactMap(\.weight).max() ?? 0
                if maxWeight > maxes[exercise.exerciseName, default: 0] {
                    maxes[exercise.exerciseName] = maxWeight
                }
            }
        }
        guard !maxes.isEmpty else { return nil }

        let topExercises = maxes.sorted { $0.value > $1.value }.prefix(4)
        let goalList = topExercises.map { "\($0.key): \(Int($0.value)) → \(Int($0.value + 5)) lbs" }.joined(separator: "\n")

        return InsightStory(
            title: "Next Goals",
            body: "\(topExercises.count) exercises to level up",
            type: .nextGoals,
            pages: [InsightPage(
                title: "Next Targets",
                content: "Based on your current maxes, here are your next goals:\n\n\(goalList)",
                actionable: "Focus on hitting these targets in your next session."
            )],
            preview: "\(topExercises.count) goals", generatedAt: Date()
        )
    }

    // MARK: - AI Enhancement

    private func enhanceStoriesWithAI(index: [WorkoutSessionIndex], sessions: [WorkoutSession]) async {
        guard APIKeyProvider.hasKey else { return }

        let weekSessions = index.filter {
            $0.startedAt >= Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        }
        let summary = buildWorkoutSummary(from: weekSessions, sessions: sessions)

        for i in stories.indices {
            let story = stories[i]
            let prompt = AIPromptBuilder.buildInsightPrompt(
                storyType: story.type, workoutSummary: summary, timePeriod: "last 7 days"
            )

            do {
                let response = try await aiService.complete(
                    systemPrompt: "You are a concise fitness insights writer. Write 2-3 sentences of personalized training insight. Be specific, not generic. No emojis. Respond with plain text only.",
                    userPrompt: prompt,
                    jsonMode: false,
                    model: AIService.lightModel
                )

                let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\"", with: "")

                if !cleaned.isEmpty, var firstPage = stories[i].pages?.first ?? stories[i].resolvedPages.first {
                    firstPage = InsightPage(
                        id: firstPage.id, title: firstPage.title, content: cleaned,
                        chartData: firstPage.chartData, actionable: firstPage.actionable
                    )
                    stories[i].pages = [firstPage] + Array(stories[i].resolvedPages.dropFirst())
                }
            } catch {
                Self.logger.warning("AI enhancement failed for \(story.type.rawValue): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private func loadRecentSessions(count: Int) -> [WorkoutSession] {
        workoutStore.index.prefix(count).compactMap { workoutStore.loadSession(id: $0.id) }
    }

    private func computeDataHash() -> Int {
        var hasher = Hasher()
        for entry in workoutStore.index {
            hasher.combine(entry.id)
            hasher.combine(entry.totalVolume)
            hasher.combine(entry.totalSets)
        }
        return hasher.finalize()
    }

    private func calculateDailyVolume(from entries: [WorkoutSessionIndex]) -> [ChartDataPoint] {
        let calendar = Calendar.current
        var dailyVolume: [Date: Double] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.startedAt)
            dailyVolume[day, default: 0] += entry.totalVolume
        }
        return dailyVolume.sorted { $0.key < $1.key }.map {
            ChartDataPoint(label: dayLabel($0.key), value: $0.value, date: $0.key)
        }
    }

    private func getPRsWithComparison(from sessions: [WorkoutSession]) -> [(exercise: String, oldWeight: Double, newWeight: Double)] {
        guard sessions.count >= 2 else { return [] }
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        var allTimeMaxes: [String: Double] = [:]
        var newPRs: [(exercise: String, oldWeight: Double, newWeight: Double)] = []

        for session in sorted {
            guard let log = session.structuredLog else { continue }
            for exercise in log.exercises {
                let maxWeight = exercise.sets.compactMap(\.weight).max() ?? 0
                guard maxWeight > 0 else { continue }
                let previousMax = allTimeMaxes[exercise.exerciseName] ?? 0
                if maxWeight > previousMax && previousMax > 0 && session.id == sorted.last?.id {
                    newPRs.append((exercise: exercise.exerciseName, oldWeight: previousMax, newWeight: maxWeight))
                }
                allTimeMaxes[exercise.exerciseName] = max(maxWeight, previousMax)
            }
        }
        return newPRs
    }

    private func buildWorkoutSummary(from weekEntries: [WorkoutSessionIndex], sessions: [WorkoutSession]) -> String {
        let totalVolume = weekEntries.reduce(0.0) { $0 + $1.totalVolume }
        let totalSets = weekEntries.reduce(0) { $0 + $1.totalSets }
        let uniqueExercises = Set(weekEntries.flatMap(\.exerciseNames))
        return """
        Workouts: \(weekEntries.count)
        Total volume: \(formatVolume(totalVolume))
        Total sets: \(totalSets)
        Exercises: \(uniqueExercises.joined(separator: ", "))
        """
    }

    private func trend(current: Double, previous: Double) -> TrendDirection? {
        guard previous > 0 else { return current > 0 ? .up : nil }
        if current > previous { return .up }
        if current < previous { return .down }
        return .stable
    }

    private func trendString(current: Double, previous: Double) -> String? {
        guard previous > 0 else { return nil }
        let pct = ((current - previous) / previous) * 100
        if abs(pct) < 1 { return nil }
        return "\(pct > 0 ? "+" : "")\(Int(pct))%"
    }

    private func formatVolume(_ volume: Double) -> String {
        volume >= 1000 ? String(format: "%.1fK", volume / 1000) : String(format: "%.0f", volume)
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}
