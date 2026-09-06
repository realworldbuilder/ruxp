import Foundation
import os

@Observable
@MainActor
final class PlannedWorkoutStore {
    private static let logger = Logger(subsystem: "com.williamhussey.mind2muscle", category: "PlannedWorkoutStore")

    private(set) var currentPlan: PlannedWorkout?

    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = docs.appendingPathComponent("planned_workout.json")

        // Remove legacy UserDefaults-based plan storage
        UserDefaults.standard.removeObject(forKey: "plannedWorkoutExercises")
        UserDefaults.standard.removeObject(forKey: "plannedWorkoutSource")

        load()
    }

    func setPlan(_ plan: PlannedWorkout) {
        currentPlan = plan
        save()
    }

    func clearPlan() {
        currentPlan = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func save() {
        guard let plan = currentPlan else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(plan)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save planned workout: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        currentPlan = try? decoder.decode(PlannedWorkout.self, from: data)
    }
}
