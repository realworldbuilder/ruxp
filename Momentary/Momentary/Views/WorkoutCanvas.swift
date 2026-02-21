import SwiftUI

// MARK: - Workout Canvas

struct WorkoutCanvas: View {
    let tags: [ExerciseTag]
    var reason: String = ""
    
    var body: some View {
        // For now, just the tag cloud. Future: multiple layered components
        ExerciseTagCloud(tags: tags, reason: reason)
    }
}

// Future component types that will live in the canvas:
// - SetTracker (current exercise tracking)
// - RestTimer (countdown between sets)
// - PRCelebration (when you hit a new record)
// - WorkoutProgress (visual completion status)
// - EnvironmentalCues (music suggestions, lighting hints)
// - SocialElements (workout buddy status, shared goals)