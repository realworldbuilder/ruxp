import SwiftUI
import Charts

// MARK: - Volume Over Time Chart

struct VolumeOverTimeChart: View {
    let dataPoints: [ChartDataPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volume Trend")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.7))

            if dataPoints.isEmpty {
                emptyState("chart.line.uptrend.xyaxis")
            } else {
                Chart(dataPoints) { point in
                    if let date = point.date {
                        LineMark(
                            x: .value("Date", date),
                            y: .value("Volume", point.value)
                        )
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        AreaMark(
                            x: .value("Date", date),
                            y: .value("Volume", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green.opacity(0.3), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        PointMark(
                            x: .value("Date", date),
                            y: .value("Volume", point.value)
                        )
                        .foregroundStyle(.green)
                        .symbolSize(30)
                    }
                }
                .frame(height: 150)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel()
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel {
                            if let volume = value.as(Double.self) {
                                Text(formatVolume(volume))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardBackground)
        )
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.0fK", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }
}

// MARK: - Progress Trend Chart

struct ProgressTrendChart: View {
    let dataPoints: [ChartDataPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let exerciseName = dataPoints.first?.label {
                Text(exerciseName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.7))
            }

            if dataPoints.isEmpty {
                emptyState("chart.line.uptrend.xyaxis")
            } else {
                Chart(dataPoints) { point in
                    if let date = point.date {
                        LineMark(
                            x: .value("Date", date),
                            y: .value("Weight", point.value)
                        )
                        .foregroundStyle(.green)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Date", date),
                            y: .value("Weight", point.value)
                        )
                        .foregroundStyle((point.isPR ?? false) ? .orange : .green)
                        .symbolSize((point.isPR ?? false) ? 80 : 40)
                        .annotation(position: .top) {
                            if point.isPR ?? false {
                                Text("PR")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .frame(height: 120)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel()
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel {
                            if let weight = value.as(Double.self) {
                                Text("\(Int(weight))")
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardBackground)
        )
    }
}

// MARK: - PR Comparison Chart

struct PRComparisonChart: View {
    let dataPoints: [ChartDataPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Records")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.7))

            if dataPoints.isEmpty {
                emptyState("trophy")
            } else {
                VStack(spacing: 10) {
                    ForEach(dataPoints.prefix(3)) { pr in
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(.orange)
                                .font(.caption)

                            Text(pr.label)
                                .font(.caption)
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Spacer()

                            HStack(spacing: 4) {
                                if let oldWeight = pr.secondaryValue, oldWeight > 0 {
                                    Text("\(Int(oldWeight))")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .strikethrough()
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                Text("\(Int(pr.value)) lbs")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.cardBackground)
        )
    }
}

// MARK: - Empty State Helper

private func emptyState(_ icon: String) -> some View {
    VStack(spacing: 8) {
        Image(systemName: icon)
            .font(.title2)
            .foregroundColor(.gray)
        Text("Not enough data yet")
            .font(.caption)
            .foregroundColor(.gray)
    }
    .frame(height: 120)
    .frame(maxWidth: .infinity)
}
