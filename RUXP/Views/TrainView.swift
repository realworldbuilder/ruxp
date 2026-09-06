import SwiftUI

/// Training history plus a quick way to start. Detail views are the existing Momentary ones.
struct TrainView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(ProgressionService.self) private var progression
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue

    private var entries: [WorkoutSessionIndex] {
        workoutManager.workoutStore.index.filter { $0.endedAt != nil }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Train").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(entries.count) WORKOUT\(entries.count == 1 ? "" : "S")")
                                .eyebrow().foregroundStyle(Theme.textTertiary)
                        }
                        PrimaryButton(title: "START WORKOUT", height: 54) {
                            workoutManager.startWorkout()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                }

                if entries.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No workouts yet.")
                                .font(Theme.Fonts.title(18))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Your first one is +\(ProgressionRules.workoutCompleteXP) XP. Talk through your sets while you lift and RUXP writes the log.")
                                .font(Theme.Fonts.body)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                    }
                } else {
                    Section {
                        ForEach(entries) { entry in
                            NavigationLink(value: entry.id) {
                                workoutRow(entry)
                            }
                            .listRowBackground(Theme.surface)
                            .listRowSeparatorTint(Theme.divider)
                        }
                        .onDelete(perform: delete)
                    } header: {
                        Text("HISTORY").eyebrow().foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(HUDBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { workoutID in
                WorkoutDetailView(workoutID: workoutID)
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { entries[$0].id }
        for id in ids { workoutManager.workoutStore.deleteSession(id: id) }
        NotificationCenter.default.post(name: .workoutsDidChange, object: nil)
    }

    // MARK: - Row

    private func workoutRow(_ entry: WorkoutSessionIndex) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(Theme.Fonts.title(16))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    Text(entry.startedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(Theme.Fonts.ui(.caption))
                        .foregroundStyle(Theme.textSecondary)
                    if let duration = entry.duration {
                        Text(formatDuration(duration))
                            .font(Theme.Fonts.ui(.caption, mono: true))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                if !entry.exerciseNames.isEmpty {
                    Text(entry.exerciseNames.joined(separator: " · "))
                        .font(Theme.Fonts.ui(.caption))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                } else if entry.momentCount > 0 && !entry.hasStructuredLog {
                    Text("\(entry.momentCount) voice note\(entry.momentCount == 1 ? "" : "s") · not parsed yet")
                        .font(Theme.Fonts.ui(.caption))
                        .foregroundStyle(Theme.textTertiary)
                }
                let hasHealth = (entry.averageHeartRate ?? 0) > 0 || (entry.activeCalories ?? 0) > 0
                if hasHealth {
                    HStack(spacing: 10) {
                        if let hr = entry.averageHeartRate, hr > 0 {
                            Label("\(Int(hr)) bpm", systemImage: "heart.fill")
                                .font(Theme.Fonts.ui(.caption2, mono: true))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if let cal = entry.activeCalories, cal > 0 {
                            Label("\(Int(cal)) cal", systemImage: "flame.fill")
                                .font(Theme.Fonts.ui(.caption2, mono: true))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            Spacer()
            if entry.totalVolume > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatVolume(entry.totalVolume))
                        .font(Theme.Fonts.mono(15))
                        .foregroundStyle(Theme.textPrimary)
                    Text(weightUnit).eyebrow().foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hrs = total / 3600, mins = (total % 3600) / 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }

    private func formatVolume(_ volume: Double) -> String {
        volume >= 1000 ? String(format: "%.1fk", volume / 1000) : "\(Int(volume))"
    }
}
