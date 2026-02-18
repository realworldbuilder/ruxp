import SwiftUI

struct HomeView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @State private var editMode: EditMode = .inactive
    @State private var showDeleteConfirmation = false
    @State private var selectedWorkouts = Set<UUID>()
    @State private var showMicPermissionDenied = false
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue

    var body: some View {
        NavigationStack {
            Group { mainContent }
                .navigationTitle("Mind2Muscle")
                .toolbarBackground(Theme.background, for: .navigationBar)
                .toolbar {
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
                .toolbar {
                    if editMode.isEditing && !selectedWorkouts.isEmpty {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Spacer()
                            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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
    }

    // MARK: - Empty State (ChatGPT-inspired onboarding)

    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 40)

                // Hero — voice waveform icon
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.1))
                        .frame(width: 100, height: 100)
                    Circle()
                        .fill(Theme.accent.opacity(0.06))
                        .frame(width: 140, height: 140)
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.bottom, 24)

                // Tagline
                Text("Your voice.\nYour workout log.")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 8)

                Text("Just talk during your workout — AI turns it into a structured training log.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 32)

                // Start Workout button — pill style
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
                .padding(.bottom, 40)

                // Feature highlights
                VStack(spacing: 16) {
                    featureRow(icon: "mic.fill", title: "Speak your sets", subtitle: "\"Bench press, 3 sets of 10 at 135\"")
                    featureRow(icon: "cpu", title: "AI structures your log", subtitle: "Exercises, sets, reps, weight — organized automatically")
                    featureRow(icon: "chart.line.uptrend.xyaxis", title: "Track your progress", subtitle: "Volume trends, PRs, weekly insights")
                    featureRow(icon: "applewatch", title: "Works on Apple Watch", subtitle: "Record from your wrist, mid-set")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)

                // Example prompt card (ChatGPT-style)
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
                        exampleChip("Just finished bench press, 4 sets, went 135, 155, 175, 185")
                        exampleChip("Squat day — worked up to 225 for 3")
                        exampleChip("Did 3 sets of pull-ups to failure, then some curls")
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
            if workoutManager.activeSession != nil {
                activeWorkoutBanner
            } else {
                startWorkoutCompactCard
            }

            if !workoutManager.workoutStore.index.isEmpty {
                weeklySummaryCard
            }

            Section("Workout History") {
                ForEach(workoutManager.workoutStore.index) { entry in
                    NavigationLink(value: entry.id) {
                        workoutRow(entry)
                    }
                    .listRowBackground(Theme.cardBackground)
                    .listRowSeparatorTint(Theme.divider)
                }
                .onDelete { offsets in
                    let ids = offsets.map { workoutManager.workoutStore.index[$0].id }
                    for id in ids { workoutManager.workoutStore.deleteSession(id: id) }
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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 8, height: 8)
                        Text("Workout Active").font(.headline)
                    }
                    Text("\(workoutManager.activeSession?.moments.count ?? 0) moments")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("View").font(.subheadline.bold()).foregroundStyle(Theme.accent)
            }
            .padding(.vertical, 4)
            .listRowBackground(Theme.cardBackground)
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
                HStack(spacing: 8) {
                    Text(entry.startedAt, style: .date)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let duration = entry.duration {
                        Text(formatDuration(duration))
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                if !entry.exerciseNames.isEmpty {
                    Text(entry.exerciseNames.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
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

        var streak = 0
        var checkDate = calendar.startOfDay(for: now)
        while true {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: checkDate)!
            let hasWorkout = workoutManager.workoutStore.index.contains { $0.startedAt >= checkDate && $0.startedAt < dayEnd }
            if hasWorkout {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else { break }
        }

        return WeeklyStatsResult(workoutCount: thisWeek.count, totalVolume: totalVolume, topExercises: top3, streak: streak)
    }

    // MARK: - Helpers

    private func deleteSelected() {
        for id in selectedWorkouts { workoutManager.workoutStore.deleteSession(id: id) }
        selectedWorkouts.removeAll()
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
