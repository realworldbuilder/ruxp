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
            Group {
                mainContent
            }
            .navigationTitle("Momentary")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !workoutManager.workoutStore.index.isEmpty {
                        Button {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                            }
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
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .onChange(of: editMode) {
                if !editMode.isEditing {
                    selectedWorkouts.removeAll()
                }
            }
            .alert("Delete Workouts", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteSelected()
                }
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
        List(selection: editMode.isEditing ? $selectedWorkouts : nil) {
            if workoutManager.activeSession != nil {
                activeWorkoutBanner
            } else {
                startWorkoutCard
            }

            if !workoutManager.workoutStore.index.isEmpty {
                weeklySummaryCard
            }

            if workoutManager.workoutStore.index.isEmpty {
                ContentUnavailableView {
                    Label("No Workouts", systemImage: "figure.strengthtraining.traditional")
                } description: {
                    Text("Start a workout and record voice notes during your session. AI will turn your notes into a structured workout log.")
                }
            } else {
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
                        for id in ids {
                            workoutManager.workoutStore.deleteSession(id: id)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .listRowSeparator(.hidden)
        .navigationDestination(for: UUID.self) { workoutID in
            WorkoutDetailView(workoutID: workoutID)
        }
    }

    // MARK: - Start Workout Card

    private var startWorkoutCard: some View {
        Section {
            Button {
                workoutManager.startWorkout()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(Theme.accent)

                    Text("Start Workout")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textPrimary)

                    Text("Use Apple Watch for best experience")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusLarge))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusLarge)
                        .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Active Workout Banner

    private var activeWorkoutBanner: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 8, height: 8)
                        Text("Workout Active")
                            .font(.headline)
                    }
                    Text("\(workoutManager.activeSession?.moments.count ?? 0) moments")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("View")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.accent)
            }
            .padding(.vertical, 4)
            .listRowBackground(Theme.cardBackground)
        }
    }

    // MARK: - Weekly Summary Card

    private var weeklySummaryCard: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("This Week")
                    .font(.headline)

                let stats = weeklyStats
                HStack(spacing: 16) {
                    weeklyStat(value: "\(stats.workoutCount)", label: "Workouts", icon: "flame.fill", color: .orange)
                    weeklyStat(value: formatVolume(stats.totalVolume), label: "Volume (\(weightUnit))", icon: "scalemass.fill", color: .green)
                    weeklyStat(value: "\(stats.streak)", label: "Day Streak", icon: "flame", color: .red)
                }

                if !stats.topExercises.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "trophy.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text(stats.topExercises.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Theme.cardBackground)
        }
    }

    private func weeklyStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Workout Row

    private func workoutRow(_ entry: WorkoutSessionIndex) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.startedAt, style: .date)
                .font(.headline)
            HStack(spacing: 12) {
                if let duration = entry.duration {
                    Label(formatDuration(duration), systemImage: "clock")
                }
                if entry.exerciseCount > 0 {
                    Label("\(entry.exerciseCount) exercises", systemImage: "figure.strengthtraining.traditional")
                }
                if entry.totalSets > 0 {
                    Label("\(entry.totalSets) sets", systemImage: "repeat")
                }
                if entry.hasStructuredLog {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .font(.caption)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if entry.totalVolume > 0 {
                    Text("\(formatVolume(entry.totalVolume)) \(weightUnit)")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.accent)
                }
                if !entry.exerciseNames.isEmpty {
                    Text(entry.exerciseNames.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Weekly Stats

    private struct WeeklyStatsResult {
        var workoutCount: Int = 0
        var totalVolume: Double = 0
        var topExercises: [String] = []
        var streak: Int = 0
    }

    private var weeklyStats: WeeklyStatsResult {
        let calendar = Calendar.current
        let now = Date()
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else {
            return WeeklyStatsResult()
        }

        let thisWeek = workoutManager.workoutStore.index.filter { $0.startedAt >= weekAgo }
        var exerciseFrequency: [String: Int] = [:]
        var totalVolume: Double = 0

        for entry in thisWeek {
            totalVolume += entry.totalVolume
            for name in entry.exerciseNames {
                exerciseFrequency[name, default: 0] += 1
            }
        }

        let top3 = exerciseFrequency.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        // Streak: consecutive days with workouts going backwards from today
        var streak = 0
        var checkDate = calendar.startOfDay(for: now)
        while true {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: checkDate)!
            let hasWorkout = workoutManager.workoutStore.index.contains {
                $0.startedAt >= checkDate && $0.startedAt < dayEnd
            }
            if hasWorkout {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else {
                break
            }
        }

        return WeeklyStatsResult(
            workoutCount: thisWeek.count,
            totalVolume: totalVolume,
            topExercises: top3,
            streak: streak
        )
    }

    // MARK: - Helpers

    private func deleteSelected() {
        for id in selectedWorkouts {
            workoutManager.workoutStore.deleteSession(id: id)
        }
        selectedWorkouts.removeAll()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        if hrs > 0 {
            return "\(hrs)h \(mins)m"
        }
        return "\(mins)m"
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }
}
