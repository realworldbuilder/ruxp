import SwiftUI
import Charts

struct ChatBlockView: View {
    let block: ChatBlock
    var onAction: ((ChatAction) -> Void)?
    var onWorkoutTap: ((UUID) -> Void)?

    var body: some View {
        switch block.type {
        case .text:
            TextBlockView(payload: block.payload)
        case .workoutSummary:
            WorkoutSummaryBlockView(payload: block.payload, onWorkoutTap: onWorkoutTap)
        case .exerciseTable:
            ExerciseTableBlockView(payload: block.payload)
        case .metricGrid:
            MetricGridBlockView(payload: block.payload)
        case .chart:
            ChartBlockView_Inner(payload: block.payload)
        case .insight:
            InsightBlockView(payload: block.payload)
        case .actionButtons:
            ActionButtonsBlockView(payload: block.payload, onAction: onAction)
        case .workoutList:
            WorkoutListBlockView(payload: block.payload, onWorkoutTap: onWorkoutTap)
        }
    }
}

// MARK: - Text Block

private struct TextBlockView: View {
    let payload: ChatBlockPayload

    var body: some View {
        Text(payload.text ?? "")
            .foregroundColor(Theme.textPrimary)
            .font(.body)
            .lineSpacing(2)
    }
}

// MARK: - Workout Summary Block

private struct WorkoutSummaryBlockView: View {
    let payload: ChatBlockPayload
    var onWorkoutTap: ((UUID) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Smart workout title
            if let names = payload.exerciseNames, !names.isEmpty {
                Text(WorkoutTitleGenerator.generate(from: names))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)
            }
            
            if let date = payload.date {
                Text(date)
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
            }

            HStack(spacing: 12) {
                if let duration = payload.duration {
                    statPill(icon: "clock", value: duration)
                }
                if let count = payload.exerciseCount {
                    statPill(icon: "dumbbell.fill", value: "\(count)")
                }
                if let sets = payload.totalSets {
                    statPill(icon: "repeat", value: "\(sets)")
                }
            }

            if let volume = payload.totalVolume, volume > 0 {
                Text(formatVolume(volume))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.accent)
            }

            if let names = payload.exerciseNames, !names.isEmpty {
                Text(names.joined(separator: " \u{2022} "))
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .themeCard()
        .onTapGesture {
            if let idStr = payload.workoutId, let uuid = UUID(uuidString: idStr) {
                onWorkoutTap?(uuid)
            }
        }
    }

    private func statPill(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
            Text(value)
                .font(.caption)
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05), in: Capsule())
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fK lbs", volume / 1000)
        }
        return String(format: "%.0f lbs", volume)
    }
}

// MARK: - Exercise Table Block

private struct ExerciseTableBlockView: View {
    let payload: ChatBlockPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = payload.exerciseName {
                Text(name)
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
            }

            // Header
            HStack {
                Text("Set")
                    .frame(width: 36, alignment: .leading)
                Text("Reps")
                    .frame(width: 44, alignment: .center)
                Text("Weight")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(Theme.textSecondary)

            Divider().overlay(Theme.divider)

            if let sets = payload.sets {
                ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                    HStack {
                        Text("\(set.setNumber ?? 0)")
                            .frame(width: 36, alignment: .leading)
                        Text(set.reps.map { "\($0)" } ?? "-")
                            .frame(width: 44, alignment: .center)
                        Text(formatWeight(set.weight, unit: set.unit))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.callout)
                    .foregroundColor(Theme.textPrimary)
                    .padding(.vertical, 4)
                    .background(index % 2 == 0 ? Color.clear : Theme.surface.opacity(0.3))
                }
                
                // Volume total
                let totalVolume = sets.reduce(0.0) { total, set in
                    total + Double(set.reps ?? 0) * (set.weight ?? 0)
                }
                if totalVolume > 0 {
                    Divider().overlay(Theme.divider)
                    HStack {
                        Spacer()
                        Text("Volume: \(formatVolume(totalVolume))")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(Theme.accent)
                    }
                }
            }
        }
        .themeCard()
    }

    private func formatWeight(_ weight: Double?, unit: String?) -> String {
        guard let w = weight else { return "-" }
        return "\(Int(w)) \(unit ?? "lbs")"
    }
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fK lbs", volume / 1000)
        }
        return String(format: "%.0f lbs", volume)
    }
}

// MARK: - Metric Grid Block

private struct MetricGridBlockView: View {
    let payload: ChatBlockPayload

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if let metrics = payload.metrics, !metrics.isEmpty {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(metrics) { metric in
                    ChatMetricCard(metric: metric)
                }
            }
        }
    }
}

private struct ChatMetricCard: View {
    let metric: ChatMetric

    var body: some View {
        VStack(spacing: 6) {
            if let icon = metric.icon {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(Theme.accent)
            }
            if let value = metric.value {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)
            }
            if let title = metric.title {
                Text(title)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            if let subtitle = metric.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .themeCard()
    }
}

// MARK: - Chart Block

private struct ChartBlockView_Inner: View {
    let payload: ChatBlockPayload

    var body: some View {
        let dataPoints = (payload.dataPoints ?? []).map { $0.toChartDataPoint() }
        let chartType = payload.chartType ?? "volumeOverTime"

        switch chartType {
        case "progressTrend":
            ProgressTrendChart(dataPoints: dataPoints)
        case "prComparison":
            PRComparisonChart(dataPoints: dataPoints)
        default:
            VolumeOverTimeChart(dataPoints: dataPoints)
        }
    }
}

// MARK: - Insight Block

private struct InsightBlockView: View {
    let payload: ChatBlockPayload
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let title = payload.title {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                }

                Spacer()

                if let typeStr = payload.insightType,
                   let type = InsightType(rawValue: typeStr) {
                    Text(type.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(type.color.opacity(0.2), in: Capsule())
                        .foregroundColor(type.color)
                }
            }

            if let body = payload.body {
                Text(body)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(isExpanded ? nil : 3)
            }

            if let body = payload.body, body.count > 100 {
                Text(isExpanded ? "Show less" : "Show more")
                    .font(.caption)
                    .foregroundColor(Theme.accent)
            }
        }
        .themeCard()
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

// MARK: - Action Buttons Block

private struct ActionButtonsBlockView: View {
    let payload: ChatBlockPayload
    var onAction: ((ChatAction) -> Void)?

    var body: some View {
        if let actions = payload.actions, !actions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        Button {
                            onAction?(action)
                        } label: {
                            Text(action.label)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Theme.accentSubtle, in: Capsule())
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Workout List Block

private struct WorkoutListBlockView: View {
    let payload: ChatBlockPayload
    var onWorkoutTap: ((UUID) -> Void)?

    var body: some View {
        if let workouts = payload.workouts, !workouts.isEmpty {
            VStack(spacing: 8) {
                ForEach(workouts) { workout in
                    Button {
                        if let idStr = workout.workoutId, let uuid = UUID(uuidString: idStr) {
                            onWorkoutTap?(uuid)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                if let date = workout.date {
                                    Text(date)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Theme.textPrimary)
                                }
                                if let summary = workout.summary {
                                    Text(summary)
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                }
                            }

                            Spacer()

                            if let volume = workout.volume, volume > 0 {
                                Text(formatVolume(volume))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(Theme.accent)
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Theme.textTertiary)
                        }
                        .themeCard()
                    }
                }
            }
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fK", volume / 1000)
        }
        return String(format: "%.0f lbs", volume)
    }
}
