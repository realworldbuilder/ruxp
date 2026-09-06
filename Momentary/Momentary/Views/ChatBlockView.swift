import SwiftUI
import Charts

struct ChatBlockView: View {
    let block: ChatBlock
    var onAction: ((ChatAction) -> Void)?
    var onWorkoutTap: ((UUID) -> Void)?
    var onStartPlan: ((PlannedWorkout) -> Void)?

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
        case .workoutPlan:
            WorkoutPlanBlockView(payload: block.payload, onStartPlan: onStartPlan)
        case .progressCard:
            ProgressCardBlockView(payload: block.payload)
        case .splitOverview:
            SplitOverviewBlockView(payload: block.payload)
        case .prBoard:
            PRBoardBlockView(payload: block.payload)
        case .tipCard:
            TipCardBlockView(payload: block.payload)
        case .checklist:
            ChecklistBlockView(payload: block.payload)
        case .comparison:
            ComparisonBlockView(payload: block.payload)
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

// MARK: - Workout Plan Block

private struct WorkoutPlanBlockView: View {
    let payload: ChatBlockPayload
    var onStartPlan: ((PlannedWorkout) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            if let title = payload.planTitle {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)
            }

            // Duration estimate
            if let duration = payload.estimatedDuration {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    Text(duration)
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
            }

            // Warmup
            if let warmup = payload.warmup {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Warmup")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text(warmup)
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.vertical, 8)
            }

            // Exercises
            if let exercises = payload.exercises, !exercises.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(exercise.name)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                                if let rpe = exercise.targetRPE {
                                    Text("RPE \(rpe)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.accent.opacity(0.2), in: Capsule())
                                        .foregroundColor(Theme.accent)
                                }
                            }

                            Text(exercise.prescription)
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(Theme.accent)

                            if let rest = exercise.rest {
                                Text("Rest: \(rest)")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }

                            if let notes = exercise.notes {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                                    .italic()
                            }
                        }
                        .padding(.vertical, 8)

                        if index < exercises.count - 1 {
                            Divider().overlay(Theme.divider)
                        }
                    }
                }
            }

            // Cooldown
            if let cooldown = payload.cooldown {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cooldown")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    Text(cooldown)
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.vertical, 8)
            }

            // Total volume
            if let volume = payload.totalVolume, volume > 0 {
                HStack {
                    Spacer()
                    Text("Estimated Volume: \(formatVolume(volume))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.accent)
                }
            }

            // Start button — only when the payload converts to a real plan
            if let onStartPlan, let plan = PlannedWorkout(payload: payload) {
                Button {
                    onStartPlan(plan)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.body.weight(.semibold))
                        Text("Start This Workout")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .themeCard()
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fK lbs", volume / 1000)
        }
        return String(format: "%.0f lbs", volume)
    }
}

// MARK: - Progress Card Block

private struct ProgressCardBlockView: View {
    let payload: ChatBlockPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let exerciseName = payload.exerciseName {
                Text(exerciseName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)
            }

            HStack(spacing: 16) {
                // Previous column
                VStack(alignment: .leading, spacing: 4) {
                    Text("Previous")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    if let previous = payload.previous {
                        Text(previous.date)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Theme.textPrimary)
                        Text(previous.topSet)
                            .font(.callout)
                            .foregroundColor(Theme.textSecondary)
                        Text(formatVolume(previous.totalVolume))
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                }

                // Arrow with trend
                VStack {
                    if let trend = payload.trend {
                        Image(systemName: trendIcon(trend))
                            .font(.title2)
                            .foregroundColor(trendColor(trend))
                    }
                    if let change = payload.volumeChange {
                        Text(change)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(trendColor(payload.trend ?? "up"))
                    }
                }

                // Current column
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                    if let current = payload.current {
                        Text(current.date)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Theme.textPrimary)
                        Text(current.topSet)
                            .font(.callout)
                            .foregroundColor(Theme.textSecondary)
                        Text(formatVolume(current.totalVolume))
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                }

                Spacer()
            }
        }
        .themeCard()
    }

    private func trendIcon(_ trend: String) -> String {
        switch trend {
        case "up": return "arrow.up.right"
        case "down": return "arrow.down.right"
        default: return "arrow.right"
        }
    }

    private func trendColor(_ trend: String) -> Color {
        switch trend {
        case "up": return .green
        case "down": return .red
        default: return Theme.textSecondary
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fK lbs", volume / 1000)
        }
        return String(format: "%.0f lbs", volume)
    }
}

// MARK: - Split Overview Block

private struct SplitOverviewBlockView: View {
    let payload: ChatBlockPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = payload.title {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)
            }

            if let days = payload.days {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(days) { day in
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(day.completed ? Theme.accent : Theme.surface)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(day.day)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(day.completed ? .black : Theme.textPrimary)
                                    )

                                Text(day.focus)
                                    .font(.caption2)
                                    .foregroundColor(Theme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .themeCard()
    }
}

// MARK: - PR Board Block

private struct PRBoardBlockView: View {
    let payload: ChatBlockPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = payload.title {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(.yellow)
                    Text(title)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.textPrimary)
                }
            }

            if let records = payload.records {
                VStack(spacing: 8) {
                    ForEach(records) { record in
                        HStack {
                            if record.isNew {
                                Image(systemName: "trophy.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            } else {
                                Image(systemName: "trophy")
                                    .foregroundColor(Theme.textTertiary)
                                    .font(.caption)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.exercise)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(Theme.textPrimary)
                                Text(record.date)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }

                            Spacer()

                            Text(record.value)
                                .font(.callout)
                                .fontWeight(.semibold)
                                .foregroundColor(record.isNew ? Theme.accent : Theme.textPrimary)

                            if record.isNew {
                                Text("NEW")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.2), in: Capsule())
                                    .foregroundColor(Theme.accent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .themeCard()
    }
}

// MARK: - Tip Card Block

private struct TipCardBlockView: View {
    let payload: ChatBlockPayload
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let icon = payload.icon {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(categoryColor(payload.category))
                }

                if let title = payload.title {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.textPrimary)
                }

                Spacer()

                if let category = payload.category {
                    Text(category.capitalized)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor(category).opacity(0.2), in: Capsule())
                        .foregroundColor(categoryColor(category))
                }
            }

            if let body = payload.body {
                Text(body)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(isExpanded ? nil : 3)

                if body.count > 100 {
                    Text(isExpanded ? "Show less" : "Show more")
                        .font(.caption)
                        .foregroundColor(Theme.accent)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }
                }
            }
        }
        .themeCard()
        .overlay(
            Rectangle()
                .fill(categoryColor(payload.category))
                .frame(width: 4)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall)),
            alignment: .leading
        )
    }

    private func categoryColor(_ category: String?) -> Color {
        guard let category = category else { return Theme.accent }
        switch category.lowercased() {
        case "technique": return .blue
        case "recovery": return .green
        case "nutrition": return .orange
        case "mindset": return .purple
        default: return Theme.accent
        }
    }
}

// MARK: - Checklist Block

private struct ChecklistBlockView: View {
    let payload: ChatBlockPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = payload.title {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)
            }

            if let items = payload.items {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Circle()
                                .stroke(item.checked ? Theme.accent : Theme.textTertiary, lineWidth: 2)
                                .fill(item.checked ? Theme.accent : Color.clear)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    item.checked ?
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                    : nil
                                )

                            Text(item.text)
                                .font(.subheadline)
                                .foregroundColor(item.checked ? Theme.textSecondary : Theme.textPrimary)
                                .strikethrough(item.checked)

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .themeCard()
    }
}

// MARK: - Comparison Block

private struct ComparisonBlockView: View {
    let payload: ChatBlockPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = payload.title {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.textPrimary)
            }

            // Header row
            if let leftLabel = payload.leftLabel, let rightLabel = payload.rightLabel {
                HStack {
                    Text(leftLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer().frame(width: 40) // Space for trend arrow

                    Text(rightLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Divider().overlay(Theme.divider)
            }

            // Data rows
            if let rows = payload.rows {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                                Text(row.left)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(Theme.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Trend arrow
                            Image(systemName: trendIcon(row.trend))
                                .font(.callout)
                                .foregroundColor(trendColor(row.trend))
                                .frame(width: 40)

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(row.label)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                                Text(row.right)
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(Theme.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .themeCard()
    }

    private func trendIcon(_ trend: String) -> String {
        switch trend {
        case "up": return "arrow.up.right"
        case "down": return "arrow.down.right"
        default: return "arrow.right"
        }
    }

    private func trendColor(_ trend: String) -> Color {
        switch trend {
        case "up": return .green
        case "down": return .red
        default: return Theme.textSecondary
        }
    }
}
