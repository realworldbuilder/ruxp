import SwiftUI
import Charts

/// Full-screen, screenshot-worthy detail views for persistent insights.
/// Designed to look great when shared on Instagram stories.

// MARK: - Lifetime Stats Detail

struct LifetimeDetailView: View {
    let stats: LifetimeStats
    let weeklySnapshots: [WeeklySnapshot]
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.yellow)
                            Spacer()
                            Button { dismiss() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        Text("All-Time Stats")
                            .font(.largeTitle.bold())
                        if let days = stats.daysSinceFirst {
                            Text("\(days) days of training")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Big Numbers
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        bigStat(value: "\(stats.totalWorkouts)", label: "Workouts", icon: "figure.strengthtraining.traditional", color: .green)
                        bigStat(value: formatVolume(stats.totalVolume), label: "Total Volume", icon: "scalemass.fill", color: .blue)
                        bigStat(value: "\(stats.totalSets)", label: "Total Sets", icon: "repeat", color: .purple)
                        bigStat(value: "\(stats.totalExercises)", label: "Exercises", icon: "dumbbell.fill", color: .orange)
                    }

                    // Averages
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Averages")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            avgCard(value: String(format: "%.0f", stats.averageVolumePerWorkout >= 1000 ? stats.averageVolumePerWorkout / 1000 : stats.averageVolumePerWorkout), unit: stats.averageVolumePerWorkout >= 1000 ? "K lbs" : "lbs", label: "Volume / Workout")
                            avgCard(value: String(format: "%.0f", stats.averageSetsPerWorkout), unit: "sets", label: "Sets / Workout")
                        }
                    }

                    // Weekly Volume Chart
                    if weeklySnapshots.count >= 2 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Weekly Volume")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Chart(weeklySnapshots.suffix(12)) { week in
                                AreaMark(
                                    x: .value("Week", week.weekStart),
                                    y: .value("Volume", week.totalVolume)
                                )
                                .foregroundStyle(Theme.accent.opacity(0.15))

                                LineMark(
                                    x: .value("Week", week.weekStart),
                                    y: .value("Volume", week.totalVolume)
                                )
                                .foregroundStyle(Theme.accent)
                                .lineStyle(StrokeStyle(lineWidth: 2))

                                PointMark(
                                    x: .value("Week", week.weekStart),
                                    y: .value("Volume", week.totalVolume)
                                )
                                .foregroundStyle(Theme.accent)
                                .symbolSize(30)
                            }
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 4)) {
                                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .chartYAxis {
                                AxisMarks { mark in
                                    AxisValueLabel()
                                        .foregroundStyle(.secondary)
                                    AxisGridLine()
                                        .foregroundStyle(.white.opacity(0.1))
                                }
                            }
                            .frame(height: 200)
                            .padding()
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }

                    // Branding
                    HStack {
                        Spacer()
                        Text("Mind2Muscle")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.accent)
                        Spacer()
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .padding(.top, 40)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func bigStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private func avgCard(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title.bold())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 { return String(format: "%.1fM", volume / 1_000_000) }
        if volume >= 1000 { return String(format: "%.1fK", volume / 1000) }
        return String(format: "%.0f", volume)
    }
}

// MARK: - PR Detail View

struct PRDetailView: View {
    let personalRecords: [String: PRRecord]
    @Environment(\.dismiss) private var dismiss

    private var sortedPRs: [PRRecord] {
        personalRecords.values.sorted { $0.weight > $1.weight }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "star.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.yellow)
                            Spacer()
                            Button { dismiss() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        Text("Personal Records")
                            .font(.largeTitle.bold())
                        Text("\(sortedPRs.count) exercises tracked")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    // Top 3 Podium
                    if sortedPRs.count >= 3 {
                        HStack(alignment: .bottom, spacing: 12) {
                            podiumCard(pr: sortedPRs[1], place: 2, height: 100)
                            podiumCard(pr: sortedPRs[0], place: 1, height: 130)
                            podiumCard(pr: sortedPRs[2], place: 3, height: 80)
                        }
                    }

                    // Full List
                    VStack(spacing: 8) {
                        ForEach(Array(sortedPRs.enumerated()), id: \.element.id) { index, pr in
                            HStack {
                                Text("#\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 30)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pr.exercise)
                                        .font(.subheadline.bold())
                                    Text(pr.date, format: .dateTime.month(.abbreviated).day().year())
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(Int(pr.weight)) lbs")
                                        .font(.headline)
                                        .foregroundStyle(Theme.accent)
                                    if let reps = pr.reps {
                                        Text("\(reps) reps")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let imp = pr.improvement, imp > 0 {
                                        Text("+\(Int(imp)) lbs")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    // Branding
                    HStack {
                        Spacer()
                        Text("Mind2Muscle")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.accent)
                        Spacer()
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .padding(.top, 40)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func podiumCard(pr: PRRecord, place: Int, height: CGFloat) -> some View {
        VStack(spacing: 6) {
            Text(place == 1 ? "👑" : place == 2 ? "🥈" : "🥉")
                .font(.title2)
            Text("\(Int(pr.weight))")
                .font(.title2.bold())
            Text("lbs")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(pr.exercise)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .padding(.vertical, 12)
        .background(
            place == 1 ? Color.yellow.opacity(0.1) :
            place == 2 ? Color.gray.opacity(0.1) :
            Color.orange.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    place == 1 ? Color.yellow.opacity(0.3) :
                    place == 2 ? Color.gray.opacity(0.3) :
                    Color.orange.opacity(0.2),
                    lineWidth: 1
                )
        )
    }
}
