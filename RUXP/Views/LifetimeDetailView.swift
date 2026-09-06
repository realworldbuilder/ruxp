import SwiftUI
import Charts

struct LifetimeDetailView: View {
    let stats: LifetimeStats
    let weeklySnapshots: [WeeklySnapshot]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Section
                VStack(spacing: 8) {
                    Text("\(stats.totalWorkouts)")
                        .font(Theme.Fonts.number(72))
                        .foregroundStyle(Theme.accent)
                    
                    Text("LIFETIME")
                        .font(Theme.Fonts.ui(.title2, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .tracking(2)
                }
                .padding(.top, 40)
                
                // Stats Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    
                    lifetimeStatCard(
                        title: "Total Volume",
                        value: formatVolume(stats.totalVolume),
                        subtitle: "\(weightUnit) lifted",
                        icon: "scalemass.fill"
                    )
                    
                    lifetimeStatCard(
                        title: "Total Sets",
                        value: "\(stats.totalSets)",
                        subtitle: String(format: "%.0f avg/workout", stats.averageSetsPerWorkout),
                        icon: "repeat"
                    )
                    
                    lifetimeStatCard(
                        title: "Total Exercises",
                        value: "\(stats.totalExercises)",
                        subtitle: "logged",
                        icon: "dumbbell.fill"
                    )
                    
                    lifetimeStatCard(
                        title: "Current Streak",
                        value: "\(stats.currentStreak)",
                        subtitle: stats.currentStreak == 1 ? "day" : "days",
                        icon: "flame.fill"
                    )
                    
                    lifetimeStatCard(
                        title: "Longest Streak",
                        value: "\(stats.longestStreak)",
                        subtitle: stats.longestStreak == 1 ? "day" : "days",
                        icon: "star.fill"
                    )
                    
                    if let daysSinceFirst = stats.daysSinceFirst {
                        lifetimeStatCard(
                            title: "Days Since First",
                            value: "\(daysSinceFirst)",
                            subtitle: "days training",
                            icon: "calendar.badge.clock"
                        )
                    }
                }
                .padding(.horizontal)
                
                // Weekly Volume Chart
                if !weeklySnapshots.isEmpty {
                    weeklyVolumeChart
                        .padding(.horizontal)
                }
                
                // Average Stats Section
                averageStatsSection
                    .padding(.horizontal)
                
                Spacer(minLength: 80)
            }
        }
        .background(Theme.background)
        .navigationBarHidden(true)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(Theme.Fonts.ui(.title3, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface.opacity(0.8), in: Circle())
                    .background(Material.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 60)
            .padding(.trailing, 20)
        }
    }
    
    // MARK: - Lifetime Stat Card
    
    private func lifetimeStatCard(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(Theme.Fonts.ui(.title3))
                .foregroundStyle(Theme.accent)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(Theme.Fonts.number(32))
                    .foregroundStyle(Theme.textPrimary)
                
                Text(title)
                    .font(Theme.Fonts.ui(.headline, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                
                Text(subtitle)
                    .font(Theme.Fonts.ui(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 140)
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.1),
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.radiusMedium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Weekly Volume Chart
    
    private var weeklyVolumeChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weekly Volume")
                .font(Theme.Fonts.ui(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            
            Chart {
                ForEach(recentWeeklySnapshots) { snapshot in
                    BarMark(
                        x: .value("Week", snapshot.weekStart, unit: .weekOfYear),
                        y: .value("Volume", snapshot.totalVolume)
                    )
                    .foregroundStyle(Theme.accent.gradient)
                    .cornerRadius(4)
                }
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Theme.divider)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Theme.divider)
                    AxisValueLabel()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .chartBackground { proxy in
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(Theme.surface.opacity(0.5))
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.1),
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.radiusMedium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var recentWeeklySnapshots: [WeeklySnapshot] {
        Array(weeklySnapshots.suffix(12))
    }
    
    // MARK: - Average Stats Section
    
    private var averageStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Average Per Workout")
                .font(Theme.Fonts.ui(.headline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            
            VStack(spacing: 12) {
                averageStatRow(
                    title: "Volume",
                    value: formatVolume(stats.averageVolumePerWorkout),
                    unit: weightUnit,
                    icon: "scalemass.fill"
                )
                
                averageStatRow(
                    title: "Sets",
                    value: String(format: "%.1f", stats.averageSetsPerWorkout),
                    unit: "sets",
                    icon: "repeat"
                )
                
                averageStatRow(
                    title: "Exercises",
                    value: String(format: "%.1f", Double(stats.totalExercises) / Double(max(stats.totalWorkouts, 1))),
                    unit: "exercises",
                    icon: "dumbbell.fill"
                )
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.1),
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.radiusMedium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func averageStatRow(title: String, value: String, unit: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(Theme.Fonts.ui(.title3))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            
            Text(title)
                .font(Theme.Fonts.ui(.body, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            
            Spacer()
            
            HStack(spacing: 4) {
                Text(value)
                    .font(Theme.Fonts.ui(.title3, weight: .bold, mono: true))
                    .foregroundStyle(Theme.textPrimary)
                
                Text(unit)
                    .font(Theme.Fonts.ui(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        } else if volume >= 1000 {
            return String(format: "%.1fK", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }
}

#Preview {
    let sampleStats = LifetimeStats(
        totalWorkouts: 142,
        totalVolume: 125000,
        totalSets: 1850,
        totalExercises: 420,
        firstWorkoutDate: Calendar.current.date(byAdding: .day, value: -200, to: Date()),
        lastWorkoutDate: Date(),
        currentStreak: 5,
        longestStreak: 12,
        workoutDates: []
    )
    
    let sampleSnapshots = (0..<12).map { week in
        WeeklySnapshot(
            weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -week, to: Date()) ?? Date(),
            workoutCount: Int.random(in: 2...5),
            totalVolume: Double.random(in: 8000...15000),
            totalSets: Int.random(in: 20...40),
            exerciseNames: ["Bench", "Squat", "Deadlift"]
        )
    }
    
    return LifetimeDetailView(stats: sampleStats, weeklySnapshots: sampleSnapshots)
}