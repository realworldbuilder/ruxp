import SwiftUI

/// Full-screen sheet shown immediately after a workout ends.
/// Displays AI processing status, then the structured summary with a share button.
struct WorkoutCompletionSheet: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WorkoutProcessor.self) private var processor
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue

    let workoutID: UUID
    @State private var session: WorkoutSession?
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if let session {
                    ScrollView {
                        VStack(spacing: 20) {
                            completionHeader(session)
                            processingStatus
                            if let log = session.structuredLog {
                                summarySection(log)
                                exerciseList(log.exercises)
                                if !log.highlights.isEmpty { highlightsSection(log.highlights) }
                            }
                            shareButton
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                    }
                } else {
                    ProgressView("Loading workout...")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        workoutManager.completedWorkoutID = nil
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .onAppear { loadSession() }
        .onChange(of: processor.state) {
            if processor.state == .completed {
                loadSession()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareImage {
                WorkoutShareSheet(items: [shareImage])
            }
        }
    }

    // MARK: - Completion Header

    private func completionHeader(_ session: WorkoutSession) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)

            Text("Workout Complete")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)

            Text(session.startedAt, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            // Stats row
            HStack(spacing: 24) {
                if let duration = session.duration {
                    statItem(icon: "clock", value: formatDuration(duration), label: "Duration")
                }
                let exercises = session.structuredLog?.exercises ?? []
                if !exercises.isEmpty {
                    statItem(icon: "figure.strengthtraining.traditional", value: "\(exercises.count)", label: "Exercises")
                    statItem(icon: "repeat", value: "\(exercises.reduce(0) { $0 + $1.sets.count })", label: "Sets")
                }
            }

            let volume = computeVolume(session)
            if volume > 0 {
                Text("\(formatVolume(volume)) \(weightUnit) total volume")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.accent)
            }

            // Health data
            if session.averageHeartRate != nil || session.activeCalories != nil {
                Divider().overlay(Theme.divider)
                HStack(spacing: 24) {
                    if let hr = session.averageHeartRate, hr > 0 {
                        VStack(spacing: 4) {
                            Image(systemName: "heart.fill").font(.caption).foregroundStyle(.red)
                            Text("\(Int(hr))").font(.headline.monospacedDigit())
                            Text("Avg BPM").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if let cal = session.activeCalories, cal > 0 {
                        VStack(spacing: 4) {
                            Image(systemName: "flame.fill").font(.caption).foregroundStyle(.orange)
                            Text("\(Int(cal))").font(.headline.monospacedDigit())
                            Text("Calories").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .themeCard(cornerRadius: Theme.radiusLarge)
    }

    // MARK: - Processing Status

    @ViewBuilder
    private var processingStatus: some View {
        switch processor.state {
        case .processing(let stage):
            HStack(spacing: 12) {
                ProgressView()
                    .tint(Theme.accent)
                Text(stage)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Analysis Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()

        case .queued:
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash").foregroundStyle(.orange)
                Text("Queued — will process when online")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()

        default:
            EmptyView()
        }
    }

    // MARK: - Summary

    private func summarySection(_ log: StructuredLog) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Summary", systemImage: "sparkles")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.accent)
            Text(log.summary)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    // MARK: - Exercise List

    private func exerciseList(_ exercises: [ExerciseGroup]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Exercises", systemImage: "list.bullet")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.accent)

            ForEach(exercises) { exercise in
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.exerciseName)
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.textPrimary)

                    ForEach(Array(exercise.sets.enumerated()), id: \.offset) { idx, set in
                        HStack {
                            Text("Set \(idx + 1)")
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 44, alignment: .leading)

                            if let reps = set.reps {
                                Text("\(reps) reps")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            if let weight = set.weight, weight > 0 {
                                Text("@ \(formatWeight(weight)) \(weightUnit)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()
                        }
                    }

                    if exercises.last?.id != exercise.id {
                        Divider().overlay(Theme.divider)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    // MARK: - Highlights

    private func highlightsSection(_ highlights: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Highlights", systemImage: "star.fill")
                .font(.subheadline.bold())
                .foregroundStyle(Theme.accent)

            ForEach(highlights, id: \.self) { highlight in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(Theme.accent)
                    Text(highlight)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    // MARK: - Share

    @ViewBuilder
    private var shareButton: some View {
        if session?.structuredLog != nil {
            Button {
                generateShareImage()
                showShareSheet = true
            } label: {
                Label("Share Workout", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        }
    }

    // MARK: - Share Image Generation

    private func generateShareImage() {
        guard let session else { return }

        let renderer = ImageRenderer(content:
            ShareableWorkoutCard(session: session, weightUnit: weightUnit)
                .frame(width: 390)
        )
        renderer.scale = 3.0
        shareImage = renderer.uiImage
    }

    // MARK: - Helpers

    private func loadSession() {
        session = workoutManager.workoutStore.loadSession(id: workoutID)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hrs = total / 3600, mins = (total % 3600) / 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }

    private func computeVolume(_ session: WorkoutSession) -> Double {
        session.structuredLog?.exercises.reduce(0.0) { total, group in
            total + group.sets.reduce(0.0) { $0 + (($1.weight ?? 0) * Double($1.reps ?? 0)) }
        } ?? 0
    }

    private func formatVolume(_ volume: Double) -> String {
        volume >= 1000 ? String(format: "%.1fk", volume / 1000) : "\(Int(volume))"
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shareable Card (rendered to image)

private struct ShareableWorkoutCard: View {
    let session: WorkoutSession
    let weightUnit: String

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mind2Muscle")
                        .font(.caption.bold())
                        .foregroundStyle(Color(hex: "10a37f"))
                    Text(session.startedAt, format: .dateTime.month(.wide).day().year())
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(Color(hex: "10a37f"))
            }

            Divider().overlay(Color.white.opacity(0.15))

            // Stats
            if let duration = session.duration {
                HStack(spacing: 20) {
                    shareStatItem(value: formatDuration(duration), label: "Duration")
                    if let exercises = session.structuredLog?.exercises {
                        shareStatItem(value: "\(exercises.count)", label: "Exercises")
                        shareStatItem(value: "\(exercises.reduce(0) { $0 + $1.sets.count })", label: "Sets")
                    }
                }
            }

            // Exercise names
            if let exercises = session.structuredLog?.exercises {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(exercises) { exercise in
                        HStack {
                            Text(exercise.exerciseName)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(exercise.sets.count) sets")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }

            // Summary
            if let summary = session.structuredLog?.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .background(Color(hex: "0d0d0d"))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(hex: "10a37f").opacity(0.3), lineWidth: 1)
        )
    }

    private func shareStatItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hrs = total / 3600, mins = (total % 3600) / 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }
}

// MARK: - Activity Sheet

private struct WorkoutShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
