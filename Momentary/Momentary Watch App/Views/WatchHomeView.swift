import SwiftUI

struct WatchHomeView: View {
    @Environment(WatchWorkoutManager.self) private var workoutManager

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Days since last workout
            if let daysSince = daysSinceLastWorkout, daysSince > 0 {
                Text("\(daysSince) day\(daysSince == 1 ? "" : "s") rest")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
            
            // Quick workout suggestion
            if let suggestion = workoutSuggestion {
                Text(suggestion)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WatchTheme.accent)
                    .padding(.top, -8)
            }
            
            Spacer()
            
            Button {
                workoutManager.startWorkout()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Start Workout")
                        .font(.system(.headline, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(WatchTheme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.horizontal, 8)
    }
    
    // MARK: - AI Intelligence Features
    
    private var daysSinceLastWorkout: Int? {
        // Simple UserDefaults check - in a real app you'd sync with HealthKit
        if let lastWorkout = UserDefaults.standard.object(forKey: "lastWorkoutDate") as? Date {
            let days = Calendar.current.dateComponents([.day], from: lastWorkout, to: Date()).day ?? 0
            return days
        }
        return nil
    }
    
    private var workoutSuggestion: String? {
        guard let days = daysSinceLastWorkout else { return nil }
        
        switch days {
        case 0: return nil // Same day, no suggestion
        case 1: return "Active recovery?"
        case 2: return "Push day?"
        case 3: return "Pull day?"
        case 4...: return "Time to lift?"
        default: return nil
        }
    }
}
