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
    @State private var showInsight = false
    @State private var currentInsight: (text: String, icon: String, color: Color)?
    
    init(tags: [ExerciseTag], reason: String = "", selectedTag: Binding<String?>, momentsCount: Int = 0) {
        self.tags = tags
        self.reason = reason
        self._selectedTag = selectedTag
        self.momentsCount = momentsCount
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ExerciseTagCloud(
                tags: tags, 
                reason: reason,
                selectedTag: $selectedTag
            )
            
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
        }
        .onAppear {
            showWorkoutStartInsight()
        }
        .onChange(of: momentsCount) { oldValue, newValue in
            showInsightForMoments(newValue, oldValue: oldValue)
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
        withAnimation(.spring(response: 0.5)) {
            showInsight = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
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