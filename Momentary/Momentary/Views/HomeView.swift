import SwiftUI

struct HomeView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(InsightsStore.self) private var insightsStore
    @State private var editMode: EditMode = .inactive
    @State private var showDeleteConfirmation = false
    @State private var selectedWorkouts = Set<UUID>()
    @State private var showMicPermissionDenied = false
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue
    
    private var intelligenceEngine: HomeIntelligenceEngine {
        HomeIntelligenceEngine(workoutStore: workoutManager.workoutStore)
    }

    var body: some View {
        NavigationStack {
            Group { mainContent }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.background, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Mind2Muscle")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if !workoutManager.workoutStore.index.isEmpty {
                            Button {
                                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            } label: {
                                Text(editMode.isEditing ? "Done" : "Select")
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if editMode.isEditing && !selectedWorkouts.isEmpty {
                        Button(role: .destructive) { showDeleteConfirmation = true } label: {
                            Label("Delete \(selectedWorkouts.count) Workout\(selectedWorkouts.count == 1 ? "" : "s")", systemImage: "trash")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .background(Theme.background)
                    }
                }
                .environment(\.editMode, $editMode)
                .onChange(of: editMode) {
                    if !editMode.isEditing { selectedWorkouts.removeAll() }
                }
                .alert("Delete Workouts", isPresented: $showDeleteConfirmation) {
                    Button("Delete", role: .destructive) { deleteSelected() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to delete \(selectedWorkouts.count) workout\(selectedWorkouts.count == 1 ? "" : "s")?")
                }
                .alert("Microphone Access Required", isPresented: $showMicPermissionDenied) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Please enable microphone access in Settings to record voice moments.")
                }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        Group {
            if workoutManager.workoutStore.index.isEmpty && workoutManager.activeSession == nil {
                emptyStateView
            } else {
                workoutListView
            }
        }
        .navigationDestination(for: UUID.self) { workoutID in
            WorkoutDetailView(workoutID: workoutID)
        }
        .fullScreenCover(isPresented: isWorkoutActive) {
            ActiveWorkoutTab()
                .environment(workoutManager)
        }
    }
    
    private var isWorkoutActive: Binding<Bool> {
        Binding(
            get: { workoutManager.activeSession != nil },
            set: { if !$0 { /* dismiss handled by end/discard */ } }
        )
    }

    // MARK: - Empty State (ChatGPT-inspired onboarding)

    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 32)

                // Welcome greeting
                Text("ready when you are")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.bottom, 4)
                Text("tap to start tracking with your voice")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 24)

                // Start Workout button
                Button { workoutManager.startWorkout() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.body.weight(.semibold))
                        Text("Start Workout")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)

                // How it works — 3 steps
                VStack(spacing: 16) {
                    featureRow(icon: "mic.fill", title: "1. Talk between sets", subtitle: "\"Bench 4 sets of 8 at 185\" — natural language, no forms")
                    featureRow(icon: "cpu", title: "2. AI builds your log", subtitle: "Exercises, sets, reps, weight — structured automatically")
                    featureRow(icon: "chart.line.uptrend.xyaxis", title: "3. Track everything", subtitle: "Volume, PRs, trends — see your progress over time")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                // Apple Health + Watch badges
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text("Apple Health sync")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.surface, in: Capsule())

                    HStack(spacing: 6) {
                        Image(systemName: "applewatch")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                        Text("Apple Watch")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.surface, in: Capsule())
                }
                .padding(.bottom, 32)

                // Example prompt card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "quote.opening")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                        Text("Try saying")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    VStack(spacing: 8) {
                        exampleChip("Bench press, 4 sets, went 135, 155, 175, 185")
                        exampleChip("Squat day — worked up to 225 for 3")
                        exampleChip("3 sets of pull-ups to failure, then some curls")
                    }
                }
                .padding(20)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium).stroke(Theme.border, lineWidth: 1))
                .padding(.horizontal, 24)

                Spacer().frame(height: 40)
            }
        }
        .background(Theme.background)
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()
        }
    }

    private func exampleChip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    // MARK: - Workout List (has data)

    private var workoutListView: some View {
        List(selection: editMode.isEditing ? $selectedWorkouts : nil) {
            // Smart greeting section
            smartGreetingSection
            
            if workoutManager.activeSession != nil {
                activeWorkoutBanner
            } else {
                // Workout suggestion or today's summary
                workoutSuggestionCard
            }

            // Smart nudges
            smartNudgesSection

            // Recent workouts with AI summaries
            if !intelligenceEngine.recentWorkoutCards.isEmpty {
                recentWorkoutsSection
            }
            
            // Full workout history (if more than 3 workouts)
            if workoutManager.workoutStore.index.count > 3 {
                Section("All Workouts") {
                    ForEach(Array(workoutManager.workoutStore.index.dropFirst(3))) { entry in
                        NavigationLink(value: entry.id) {
                            workoutRow(entry)
                        }
                        .listRowBackground(Theme.cardBackground)
                        .listRowSeparatorTint(Theme.divider)
                    }
                    .onDelete { offsets in
                        let adjustedOffsets = IndexSet(offsets.map { $0 + 3 })
                        let ids = adjustedOffsets.map { workoutManager.workoutStore.index[$0].id }
                        for id in ids { workoutManager.workoutStore.deleteSession(id: id) }
                        NotificationCenter.default.post(name: .workoutsDidChange, object: nil)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .listRowSeparator(.hidden)
    }

    // MARK: - Compact Start Card (when there's workout history)

    private var startWorkoutCompactCard: some View {
        Section {
            Button { workoutManager.startWorkout() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start Workout")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Tap to begin voice tracking")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .listRowBackground(Theme.cardBackground)
        }
    }

    // MARK: - Active Workout Banner

    private var activeWorkoutBanner: some View {
        Section {
            Button {
                NotificationCenter.default.post(name: .switchToWorkoutTab, object: nil)
            } label: {
                HStack(spacing: 12) {
                    // Pulsing indicator
                    ZStack {
                        Circle()
                            .fill(Theme.accent.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 12, height: 12)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workout Active")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(workoutManager.activeSession?.moments.count ?? 0) \((workoutManager.activeSession?.moments.count ?? 0) == 1 ? "moment" : "moments") recorded")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.accent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Smart Intelligence Components
    
    private var smartGreetingSection: some View {
        Section {
            Text(intelligenceEngine.smartGreeting)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }
    
    private var workoutSuggestionCard: some View {
        Section {
            Group {
                if let summary = intelligenceEngine.todaysWorkoutSummary {
                    // Today's workout summary
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Workout Complete")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else if let suggestion = intelligenceEngine.workoutSuggestion {
                    // Workout suggestion
                    Button { workoutManager.startWorkout() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "brain.head.profile")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 32)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title)
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(suggestion.reason)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            
                            Spacer()
                            
                            Text("Start")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Theme.accent, in: Capsule())
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } else {
                    startWorkoutCompactCard
                }
            }
            .listRowBackground(Theme.cardBackground)
        }
    }
    
    private var weeklyStreakCard: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("This Week")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                
                let streak = intelligenceEngine.weeklyStreak
                
                // Day dots (Mon-Sun)
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { dayIndex in
                        let isToday = dayIndex == streak.currentDayIndex
                        let hasWorkout = streak.workoutDays[dayIndex]
                        
                        Circle()
                            .fill(hasWorkout ? Theme.accent : Theme.surface)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(isToday ? Theme.accent : Color.clear, lineWidth: 2)
                            )
                            .overlay(
                                Text(dayAbbreviation(for: dayIndex))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(hasWorkout ? .white : Theme.textSecondary)
                            )
                    }
                    
                    Spacer()
                }
                
                Text(streak.streakText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 4)
            .listRowBackground(Theme.cardBackground)
        }
    }
    
    private var smartNudgesSection: some View {
        let nudges = intelligenceEngine.smartNudges
        
        return Group {
            if !nudges.isEmpty {
                Section {
                    ForEach(Array(nudges.enumerated()), id: \.offset) { _, nudge in
                        HStack(spacing: 12) {
                            Image(systemName: nudgeIcon(for: nudge.type))
                                .font(.body)
                                .foregroundStyle(nudgeColor(for: nudge.type))
                                .frame(width: 24)
                            
                            Text(nudge.message)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                            
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(Theme.cardBackground)
                    .listRowSeparator(.hidden)
                }
            }
        }
    }
    
    private var recentWorkoutsSection: some View {
        Section("Recent") {
            ForEach(intelligenceEngine.recentWorkoutCards, id: \.workoutIndex.id) { card in
                NavigationLink(value: card.workoutIndex.id) {
                    enhancedWorkoutRow(card.workoutIndex, summary: card.aiSummary)
                }
                .listRowBackground(Theme.cardBackground)
                .listRowSeparatorTint(Theme.divider)
            }
        }
    }
    
    // MARK: - Weekly Summary

    private var weeklySummaryCard: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("This Week").font(.headline)
                let stats = weeklyStats
                HStack(spacing: 16) {
                    weeklyStat(value: "\(stats.workoutCount)", label: "Workouts", icon: "flame.fill", color: .orange)
                    weeklyStat(value: formatVolume(stats.totalVolume), label: "Volume (\(weightUnit))", icon: "scalemass.fill", color: .green)
                    weeklyStat(value: "\(stats.streak)", label: "Day Streak", icon: "flame", color: .red)
                }
                if !stats.topExercises.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "trophy.fill").font(.caption).foregroundStyle(.yellow)
                        Text(stats.topExercises.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Theme.cardBackground)
        }
    }

    private func weeklyStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Workout Row

    private func workoutRow(_ entry: WorkoutSessionIndex) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    Text(entry.startedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if let duration = entry.duration {
                        Text(formatDuration(duration))
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                if !entry.exerciseNames.isEmpty {
                    Text(entry.exerciseNames.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                // Health data badges
                let hasHealth = entry.averageHeartRate != nil || entry.activeCalories != nil
                if hasHealth {
                    HStack(spacing: 10) {
                        if let hr = entry.averageHeartRate, hr > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                Text("\(Int(hr)) bpm")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if let cal = entry.activeCalories, cal > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text("\(Int(cal)) cal")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
            Spacer()
            if entry.totalVolume > 0 {
                Text("\(formatVolume(entry.totalVolume))")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Weekly Stats

    private struct WeeklyStatsResult {
        var workoutCount = 0
        var totalVolume: Double = 0
        var topExercises: [String] = []
        var streak = 0
    }

    private var weeklyStats: WeeklyStatsResult {
        let calendar = Calendar.current
        let now = Date()
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return WeeklyStatsResult() }

        let thisWeek = workoutManager.workoutStore.index.filter { $0.startedAt >= weekAgo }
        var exerciseFrequency: [String: Int] = [:]
        var totalVolume: Double = 0

        for entry in thisWeek {
            totalVolume += entry.totalVolume
            for name in entry.exerciseNames { exerciseFrequency[name, default: 0] += 1 }
        }

        let top3 = exerciseFrequency.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        // Use persistent streak from insights store
        let streak = insightsStore.lifetimeStats.currentStreak

        return WeeklyStatsResult(workoutCount: thisWeek.count, totalVolume: totalVolume, topExercises: top3, streak: streak)
    }

    // MARK: - Enhanced Workout Row

    private func enhancedWorkoutRow(_ entry: WorkoutSessionIndex, summary: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    Text(entry.startedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if let duration = entry.duration {
                        Text(formatDuration(duration))
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                
                // AI-generated summary
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Theme.accent.opacity(0.8))
                    .lineLimit(1)
                
                // Health data badges
                let hasHealth = entry.averageHeartRate != nil || entry.activeCalories != nil
                if hasHealth {
                    HStack(spacing: 10) {
                        if let hr = entry.averageHeartRate, hr > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                Text("\(Int(hr)) bpm")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        if let cal = entry.activeCalories, cal > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text("\(Int(cal)) cal")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
            Spacer()
            if entry.totalVolume > 0 {
                Text("\(formatVolume(entry.totalVolume))")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Helper Functions for Intelligence Components
    
    private func dayAbbreviation(for dayIndex: Int) -> String {
        let days = ["M", "T", "W", "T", "F", "S", "S"] // Mon-Sun
        return days[dayIndex]
    }
    
    private func nudgeIcon(for type: HomeIntelligenceEngine.NudgeType) -> String {
        switch type {
        case .missedMuscleGroup:
            return "exclamationmark.triangle"
        case .streak:
            return "flame.fill"
        case .volumeTrend:
            return "chart.line.uptrend.xyaxis"
        case .restDay:
            return "bed.double"
        }
    }
    
    private func nudgeColor(for type: HomeIntelligenceEngine.NudgeType) -> Color {
        switch type {
        case .missedMuscleGroup:
            return .orange
        case .streak:
            return .red
        case .volumeTrend:
            return Theme.accent
        case .restDay:
            return .blue
        }
    }

    // MARK: - Helpers

    private func deleteSelected() {
        for id in selectedWorkouts { workoutManager.workoutStore.deleteSession(id: id) }
        selectedWorkouts.removeAll()
        // Post notification so insights refresh after deletion
        NotificationCenter.default.post(name: .workoutsDidChange, object: nil)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }

    private func formatVolume(_ volume: Double) -> String {
        volume >= 1000 ? String(format: "%.1fk", volume / 1000) : String(format: "%.0f", volume)
    }
}
