import Foundation
import os

/// Persistent insights that survive workout deletion.
/// This is the "ongoing study" — cumulative knowledge about the user's training.
@Observable
@MainActor
final class InsightsStore {
    private static let logger = Logger(subsystem: "com.williamhussey.mind2muscle", category: "InsightsStore")

    // MARK: - Published State

    var lifetimeStats: LifetimeStats
    var personalRecords: [String: PRRecord]  // exercise name → best
    var weeklySnapshots: [WeeklySnapshot]

    // MARK: - Storage

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("insights_store.json")
        lifetimeStats = LifetimeStats()
        personalRecords = [:]
        weeklySnapshots = []
        load()
    }

    // MARK: - Ingest a Workout (call on workout end or analysis complete)

    func ingest(_ session: WorkoutSession) {
        guard let log = session.structuredLog else { return }

        // Update lifetime stats
        lifetimeStats.totalWorkouts += 1
        let volume = log.exercises.reduce(0.0) { total, ex in
            total + ex.sets.reduce(0.0) { $0 + (($1.weight ?? 0) * Double($1.reps ?? 0)) }
        }
        let sets = log.exercises.reduce(0) { $0 + $1.sets.count }
        lifetimeStats.totalVolume += volume
        lifetimeStats.totalSets += sets
        lifetimeStats.totalExercises += log.exercises.count
        lifetimeStats.lastWorkoutDate = session.startedAt

        if lifetimeStats.firstWorkoutDate == nil {
            lifetimeStats.firstWorkoutDate = session.startedAt
        }

        // Add workout date to set and recompute streak
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: session.startedAt)
        lifetimeStats.workoutDates.insert(dateString)
        
        // Recompute current streak by counting consecutive days backwards from today
        recomputeStreak()

        // Update PRs
        for exercise in log.exercises {
            let maxWeight = exercise.sets.compactMap(\.weight).max() ?? 0
            guard maxWeight > 0 else { continue }

            let existing = personalRecords[exercise.exerciseName]
            if existing == nil || maxWeight > existing!.weight {
                personalRecords[exercise.exerciseName] = PRRecord(
                    exercise: exercise.exerciseName,
                    weight: maxWeight,
                    reps: exercise.sets.first(where: { $0.weight == maxWeight })?.reps,
                    date: session.startedAt,
                    previousWeight: existing?.weight
                )
            }
        }

        // Update weekly snapshot
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: session.startedAt)?.start ?? session.startedAt
        if let idx = weeklySnapshots.firstIndex(where: { calendar.isDate($0.weekStart, equalTo: weekStart, toGranularity: .weekOfYear) }) {
            weeklySnapshots[idx].workoutCount += 1
            weeklySnapshots[idx].totalVolume += volume
            weeklySnapshots[idx].totalSets += sets
            weeklySnapshots[idx].exerciseNames.formUnion(log.exercises.map(\.exerciseName))
        } else {
            weeklySnapshots.append(WeeklySnapshot(
                weekStart: weekStart,
                workoutCount: 1,
                totalVolume: volume,
                totalSets: sets,
                exerciseNames: Set(log.exercises.map(\.exerciseName))
            ))
            // Keep last 52 weeks
            if weeklySnapshots.count > 52 {
                weeklySnapshots = Array(weeklySnapshots.suffix(52))
            }
        }

        save()
        Self.logger.info("Ingested workout: \(log.exercises.count) exercises, \(Int(volume)) volume")
    }

    // MARK: - Reset all data

    func resetAll() {
        lifetimeStats = LifetimeStats()
        personalRecords = [:]
        weeklySnapshots = []
        save()
        Self.logger.info("All insights data reset")
    }

    // MARK: - Rebuild from all workouts (migration / reset)

    func rebuild(from store: WorkoutStore) {
        lifetimeStats = LifetimeStats()
        personalRecords = [:]
        weeklySnapshots = []

        let sessions = store.index.compactMap { store.loadSession(id: $0.id) }
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        for session in sorted {
            ingest(session)
        }
        Self.logger.info("Rebuilt insights from \(sorted.count) workouts")
    }

    // MARK: - Streak Calculation

    private func recomputeStreak() {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        var currentStreak = 0
        var longestStreak = 0
        var tempStreak = 0
        
        // Start from today and work backwards
        var checkDate = calendar.startOfDay(for: Date())
        
        // Count current streak backwards from today
        while true {
            let dateString = dateFormatter.string(from: checkDate)
            if lifetimeStats.workoutDates.contains(dateString) {
                currentStreak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }
        
        // Find longest streak by checking all dates in chronological order
        let sortedDates = lifetimeStats.workoutDates.compactMap { dateFormatter.date(from: $0) }.sorted()
        
        for (index, date) in sortedDates.enumerated() {
            if index == 0 {
                tempStreak = 1
            } else {
                let previousDate = sortedDates[index - 1]
                let daysBetween = calendar.dateComponents([.day], from: previousDate, to: date).day ?? 0
                
                if daysBetween == 1 {
                    tempStreak += 1
                } else {
                    longestStreak = max(longestStreak, tempStreak)
                    tempStreak = 1
                }
            }
        }
        longestStreak = max(longestStreak, tempStreak)
        
        lifetimeStats.currentStreak = currentStreak
        lifetimeStats.longestStreak = longestStreak
    }

    // MARK: - Persistence

    private func save() {
        let data = PersistentInsights(
            lifetimeStats: lifetimeStats,
            personalRecords: personalRecords,
            weeklySnapshots: weeklySnapshots
        )
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save insights: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(PersistentInsights.self, from: data)
            lifetimeStats = decoded.lifetimeStats
            personalRecords = decoded.personalRecords
            weeklySnapshots = decoded.weeklySnapshots
            Self.logger.info("Loaded persistent insights: \(self.personalRecords.count) PRs, \(self.weeklySnapshots.count) weeks")
        } catch {
            Self.logger.error("Failed to load insights: \(error)")
        }
    }
}

// MARK: - Models

struct LifetimeStats: Codable {
    var totalWorkouts: Int = 0
    var totalVolume: Double = 0
    var totalSets: Int = 0
    var totalExercises: Int = 0
    var firstWorkoutDate: Date?
    var lastWorkoutDate: Date?
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var workoutDates: Set<String> = []

    var daysSinceFirst: Int? {
        guard let first = firstWorkoutDate else { return nil }
        return Calendar.current.dateComponents([.day], from: first, to: Date()).day
    }

    var averageVolumePerWorkout: Double {
        totalWorkouts > 0 ? totalVolume / Double(totalWorkouts) : 0
    }

    var averageSetsPerWorkout: Double {
        totalWorkouts > 0 ? Double(totalSets) / Double(totalWorkouts) : 0
    }
}

struct PRRecord: Codable, Identifiable {
    var id: String { exercise }
    var exercise: String
    var weight: Double
    var reps: Int?
    var date: Date
    var previousWeight: Double?

    var improvement: Double? {
        guard let prev = previousWeight else { return nil }
        return weight - prev
    }
    
    var isCompound: Bool {
        let lower = exercise.lowercased()
        let compoundKeywords = [
            "bench", "squat", "deadlift", "overhead press", "ohp", "military press",
            "barbell row", "bent over row", "row", "pull up", "pullup", "pull-up",
            "chin up", "chinup", "chin-up", "dip", "hip thrust",
            "clean", "snatch", "jerk", "front squat", "romanian", "rdl",
            "pendlay", "t-bar", "incline press", "decline press", "leg press",
            "hack squat", "lunge", "step up", "good morning", "floor press"
        ]
        return compoundKeywords.contains(where: { lower.contains($0) })
    }
}

struct WeeklySnapshot: Codable, Identifiable {
    var id: Date { weekStart }
    var weekStart: Date
    var workoutCount: Int
    var totalVolume: Double
    var totalSets: Int
    var exerciseNames: Set<String>
}

private struct PersistentInsights: Codable {
    var lifetimeStats: LifetimeStats
    var personalRecords: [String: PRRecord]
    var weeklySnapshots: [WeeklySnapshot]
}
