import Foundation

@Observable
@MainActor
final class PlannedWorkoutStore {
    var plannedExercises: [String] = []
    var planSource: String = "" // e.g. "Trainer planned: Push Day"
    
    private static let key = "plannedWorkoutExercises"
    private static let sourceKey = "plannedWorkoutSource"
    
    init() {
        load()
    }
    
    func setPlan(exercises: [String], source: String) {
        plannedExercises = exercises
        planSource = source
        save()
    }
    
    func clearPlan() {
        plannedExercises = []
        planSource = ""
        save()
    }
    
    private func save() {
        UserDefaults.standard.set(plannedExercises, forKey: Self.key)
        UserDefaults.standard.set(planSource, forKey: Self.sourceKey)
    }
    
    private func load() {
        plannedExercises = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        planSource = UserDefaults.standard.string(forKey: Self.sourceKey) ?? ""
    }
}