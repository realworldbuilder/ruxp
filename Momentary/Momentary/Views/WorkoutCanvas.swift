import SwiftUI

// MARK: - Canvas Insight Bubble

struct CanvasInsightBubble: View {
    let text: String
    let icon: String
    let color: Color
    @State private var isVisible = false
    
    var body: some View {
        if isVisible {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(text)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 0.5))
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }
    
    func show() {
        withAnimation(.spring(response: 0.5)) {
            isVisible = true
        }
    }
    
    func hide() {
        withAnimation(.opacity.delay(0.1)) {
            isVisible = false
        }
    }
}

// MARK: - Workout Canvas

struct WorkoutCanvas: View {
    let tags: [ExerciseTag]
    var reason: String = ""
    @Binding var selectedTag: String?
    let momentsCount: Int
    let workoutElapsed: TimeInterval
    let workoutStore: WorkoutStore
    let suggestionEngine: ExerciseSuggestionEngine
    let currentSession: WorkoutSession?
    @State private var showInsight = false
    @State private var currentInsight: (text: String, icon: String, color: Color)?
    @State private var showOverloadHint = false
    @State private var overloadHint: String?
    
    init(
        tags: [ExerciseTag], 
        reason: String = "", 
        selectedTag: Binding<String?>, 
        momentsCount: Int = 0,
        workoutElapsed: TimeInterval = 0,
        workoutStore: WorkoutStore,
        suggestionEngine: ExerciseSuggestionEngine,
        currentSession: WorkoutSession? = nil
    ) {
        self.tags = tags
        self.reason = reason
        self._selectedTag = selectedTag
        self.momentsCount = momentsCount
        self.workoutElapsed = workoutElapsed
        self.workoutStore = workoutStore
        self.suggestionEngine = suggestionEngine
        self.currentSession = currentSession
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Phase-aware header
            workoutPhaseHeader
            
            ExerciseTagCloud(
                tags: tags, 
                reason: reason,
                selectedTag: $selectedTag
            )
            
            // Progressive overload hint (when tag selected)
            if let hint = overloadHint, showOverloadHint {
                CanvasInsightBubble(
                    text: hint,
                    icon: "arrow.up.right",
                    color: Theme.accent
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            
            // General insights
            if let insight = currentInsight, showInsight {
                CanvasInsightBubble(
                    text: insight.text,
                    icon: insight.icon,
                    color: insight.color
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            
            Spacer(minLength: 16)
            
            // Volume tracker at bottom
            volumeTracker
        }
        .onAppear {
            showWorkoutStartInsight()
        }
        .onChange(of: momentsCount) { oldValue, newValue in
            showInsightForMoments(newValue, oldValue: oldValue)
            showPhaseAwareness()
        }
        .onChange(of: selectedTag) { oldValue, newValue in
            showProgressiveOverloadHint(for: newValue)
        }
        .onChange(of: workoutElapsed) { _, _ in
            showPhaseAwareness()
        }
    }
    
    private var workoutPhaseHeader: some View {
        Group {
            if workoutElapsed < 300 { // 0-5 min
                Text("WARM UP")
                    .font(.caption2)
                    .foregroundColor(Theme.warning)
                    .textCase(.uppercase)
                    .tracking(1.5)
            } else if workoutElapsed > 3600 { // 60+ min
                Text("FINISHING UP")
                    .font(.caption2)
                    .foregroundColor(Theme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(1.5)
            } else if workoutElapsed > 2400 { // 40+ min
                Text("FINISHING UP")
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(1.5)
            }
        }
    }
    
    private var volumeTracker: some View {
        Group {
            if let volume = calculateTotalVolume() {
                let volumeLevel = min(volume / 5000, 1.0) // Scale 0-1 based on 5000 lbs max
                let opacity = 0.3 + (volumeLevel * 0.5) // More visible as volume grows
                
                Text("~\(Int(volume).formatted()) lbs total volume")
                    .font(.caption2)
                    .foregroundColor(Theme.accent.opacity(opacity))
                    .tracking(0.5)
                    .scaleEffect(1.0 + (volumeLevel * 0.1)) // Subtle scale increase
                    .animation(.easeOut(duration: 0.3), value: volume)
            } else if momentsCount > 0 {
                Text("Volume tracking...")
                    .font(.caption2)
                    .foregroundColor(Theme.textTertiary.opacity(0.4))
                    .tracking(0.5)
            }
        }
    }
    
    private func calculateTotalVolume() -> Double? {
        guard let session = currentSession,
              let structuredLog = session.structuredLog else { return nil }
        
        var totalVolume: Double = 0
        
        for exercise in structuredLog.exercises {
            for set in exercise.sets {
                if let weight = set.weight, let reps = set.reps {
                    totalVolume += weight * Double(reps)
                }
            }
        }
        
        return totalVolume > 0 ? totalVolume : nil
    }
    
    private func showProgressiveOverloadHint(for exercise: String?) {
        guard let exercise = exercise else {
            withAnimation(.opacity) {
                showOverloadHint = false
            }
            return
        }
        
        if let performance = suggestionEngine.getLastPerformance(exercise: exercise, workoutStore: workoutStore) {
            // Smart progression based on rep range
            let (suggestedWeight, suggestedReps) = calculateProgression(weight: performance.weight, reps: performance.reps)
            
            let formattedWeight = suggestedWeight.truncatingRemainder(dividingBy: 1) == 0 
                ? String(format: "%.0f", suggestedWeight) 
                : String(format: "%.1f", suggestedWeight)
            
            overloadHint = "Last time: \(Int(performance.weight)) × \(performance.reps) → Try \(formattedWeight) × \(suggestedReps)"
            
            withAnimation(.spring(response: 0.5)) {
                showOverloadHint = true
            }
        } else {
            withAnimation(.opacity) {
                showOverloadHint = false
            }
        }
    }
    
    private func calculateProgression(weight: Double, reps: Int) -> (weight: Double, reps: Int) {
        switch reps {
        case 1...3: // Strength range - increase weight
            return (weight * 1.025, reps) // 2.5% weight increase
        case 4...6: // Power range - small weight increase
            return (weight * 1.02, reps) // 2% weight increase  
        case 7...12: // Hypertrophy - increase reps first, then weight
            if reps < 10 {
                return (weight, reps + 1) // Add a rep
            } else {
                return (weight * 1.02, max(reps - 2, 8)) // Increase weight, drop reps
            }
        default: // High rep endurance - add reps
            return (weight, reps + 1)
        }
    }
    }
    
    private func showPhaseAwareness() {
        let elapsedMinutes = workoutElapsed / 60
        
        // Only show phase insights when crossing major thresholds
        if elapsedMinutes >= 60 && momentsCount > 8 {
            currentInsight = ("Great session, consider wrapping up", "checkmark.circle", Theme.success)
            showTimedInsight()
        }
    }
    
    private func showWorkoutStartInsight() {
        guard momentsCount == 0 else { return }
        currentInsight = ("Let's get it 💪", "flame.fill", Theme.accent)
        withAnimation(.spring(response: 0.5)) {
            showInsight = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.opacity) {
                showInsight = false
            }
        }
    }
    
    private func showInsightForMoments(_ newCount: Int, oldValue: Int) {
        guard newCount > oldValue else { return }
        
        let insight: (String, String, Color) = {
            switch newCount {
            case 1:
                return ("First set logged ✓", "checkmark.circle.fill", Theme.success)
            case 3...5:
                return ("Building volume 📈", "chart.line.uptrend.xyaxis", Theme.accent)
            case 6...10:
                return ("Strong session 💪", "bolt.fill", Theme.accent)
            default:
                return ("Volume on track", "target", Theme.textSecondary)
            }
        }()
        
        currentInsight = insight
        showTimedInsight()
    }
    
    private func showTimedInsight(duration: Double = 2.5) {
        withAnimation(.spring(response: 0.5)) {
            showInsight = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.opacity) {
                showInsight = false
            }
        }
    }
}

// Future component types that will live in the canvas:
// - SetTracker (current exercise tracking)
// - RestTimer (countdown between sets)
// - PRCelebration (when you hit a new record)
// - WorkoutProgress (visual completion status)
// - EnvironmentalCues (music suggestions, lighting hints)
// - SocialElements (workout buddy status, shared goals)