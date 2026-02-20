import SwiftUI
import UniformTypeIdentifiers

enum TimePeriod: String, CaseIterable {
    case weekly = "Weekly"
    case monthly = "Monthly"
    case allTime = "All-Time"
}

struct ShareableImageItem: Identifiable, Transferable {
    let id = UUID()
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .png) { item in
            item.image.pngData() ?? Data()
        } importing: { data in
            ShareableImageItem(image: UIImage(data: data) ?? UIImage())
        }
    }
}

struct InsightsTab: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(InsightsEngine.self) private var insightsService
    @Environment(InsightsStore.self) private var insightsStore
    @State private var selectedTag: String?
    @State private var showingStoryViewer = false
    @State private var storyViewerStartIndex = 0
    @State private var showingLifetimeDetail = false
    @State private var showingPRDetail = false
    @State private var selectedPeriod: TimePeriod = .weekly
    @State private var shareItem: ShareableImageItem? = nil

    private struct LinkedInsight: Identifiable {
        let id: UUID
        let story: InsightStory
        let workoutID: UUID
        let workoutDate: Date
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Time Period Toggle
                    Picker("Time Period", selection: $selectedPeriod) {
                        ForEach(TimePeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Story Carousel
                    if !insightsService.stories.isEmpty {
                        storyCarouselSection
                    }

                    // Unified Stats Section (one section, controlled by toggle)
                    if periodStats.totalWorkouts > 0 || insightsStore.lifetimeStats.totalWorkouts > 0 {
                        statsSection
                    }

                    // Persistent PRs
                    if !insightsStore.personalRecords.isEmpty {
                        prSection
                    }

                    // Recent per-workout insights
                    if allLinkedInsights.isEmpty && insightsService.stories.isEmpty && insightsStore.lifetimeStats.totalWorkouts == 0 {
                        ContentUnavailableView {
                            Label("No Insights Yet", systemImage: "lightbulb")
                        } description: {
                            Text("Complete a workout to get AI-generated insights about your training.")
                        }
                        .padding(.top, 60)
                    } else if !allLinkedInsights.isEmpty {
                        recentInsightsSection
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Insights")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .navigationDestination(for: UUID.self) { workoutID in
                WorkoutDetailView(workoutID: workoutID)
            }
            .fullScreenCover(isPresented: $showingLifetimeDetail) {
                LifetimeDetailView(
                    stats: insightsStore.lifetimeStats,
                    weeklySnapshots: insightsStore.weeklySnapshots
                )
            }
            .fullScreenCover(isPresented: $showingPRDetail) {
                PRDetailView(personalRecords: insightsStore.personalRecords)
            }
            .fullScreenCover(isPresented: $showingStoryViewer) {
                InsightStoryView(
                    stories: insightsService.stories,
                    startingStoryIndex: storyViewerStartIndex
                ) {
                    showingStoryViewer = false
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheetView(activityItems: [item.image])
                    .presentationDetents([.medium])
            }
            .task {
                await insightsService.generateInsights()
            }
            .onReceive(NotificationCenter.default.publisher(for: .workoutsDidChange)) { _ in
                Task { await insightsService.generateInsights() }
            }
        }
    }

    // MARK: - Story Carousel Section
    private var storyCarouselSection: some View {
        StoryCarouselView(stories: insightsService.stories) { index in
            storyViewerStartIndex = index
            showingStoryViewer = true
        }
    }

    // MARK: - Unified Stats Section
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(periodLabel, systemImage: "chart.bar.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            let stats = periodStats
            let columns = [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]

            LazyVGrid(columns: columns, spacing: 12) {
                statCard(
                    icon: "figure.strengthtraining.traditional",
                    value: "\(stats.totalWorkouts)",
                    title: "Workouts",
                    subtitle: selectedPeriod == .allTime ? stats.daysSinceFirst.map { "over \($0) days" } : nil,
                    color: .green
                )
                statCard(
                    icon: "scalemass.fill",
                    value: formatVolume(stats.totalVolume),
                    title: "Volume",
                    subtitle: "total lbs",
                    color: .blue
                )
                statCard(
                    icon: "dumbbell.fill",
                    value: "\(stats.totalExercises)",
                    title: "Exercises",
                    subtitle: "unique movements",
                    color: .orange
                )
                statCard(
                    icon: "repeat",
                    value: "\(stats.totalSets)",
                    title: "Sets",
                    subtitle: "total sets",
                    color: .purple
                )
            }
            .padding(.horizontal)

            // Streak row
            HStack(spacing: 12) {
                statCard(
                    icon: "flame.fill",
                    value: "\(insightsStore.lifetimeStats.currentStreak)",
                    title: "Day Streak",
                    subtitle: "current",
                    color: .red
                )
                statCard(
                    icon: "trophy.fill",
                    value: "\(insightsStore.lifetimeStats.longestStreak)",
                    title: "Best Streak",
                    subtitle: "all-time",
                    color: .yellow
                )
            }
            .padding(.horizontal)
        }
    }

    private func statCard(icon: String, value: String, title: String, subtitle: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer()
                Button(action: {
                    shareStatCard(icon: icon, value: value, title: title, subtitle: subtitle, color: color)
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text(value)
                .font(.title2.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .themeCard()
    }

    // MARK: - Recent Insights Section
    private var recentInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recent Insights", systemImage: "lightbulb.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if !allTags.isEmpty {
                tagFilter
            }

            LazyVStack(spacing: 8) {
                ForEach(filteredInsights) { linked in
                    NavigationLink(value: linked.workoutID) {
                        storyCard(linked)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - PR Section
    private var prSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Personal Records", systemImage: "star.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("See All") {
                    showingPRDetail = true
                }
                .font(.caption)
                .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal)

            if topPRs.count >= 3 {
                HStack(spacing: 8) {
                    ForEach(Array(topPRs.prefix(3).enumerated()), id: \.element.id) { index, pr in
                        topPRCard(pr: pr, rank: index + 1)
                    }
                }
                .padding(.horizontal)
            } else {
                // Fewer than 3 PRs — show as list
                VStack(spacing: 8) {
                    ForEach(topPRs) { pr in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pr.exercise)
                                    .font(.subheadline.bold())
                                if let date = pr.date as Date? {
                                    Text(date, format: .dateTime.month(.abbreviated).day())
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Text("\(Int(pr.weight)) lbs")
                                .font(.headline)
                                .foregroundStyle(Theme.accent)
                        }
                        .themeCard()
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func topPRCard(pr: PRRecord, rank: Int) -> some View {
        VStack(spacing: 6) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(rankColor(rank).opacity(0.2))
                    .frame(width: 24, height: 24)
                Text("\(rank)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(rankColor(rank))
            }

            // Weight
            Text("\(Int(pr.weight))")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)

            Text("lbs")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)

            // Exercise name
            Text(pr.exercise)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            // Improvement
            if let improvement = pr.improvement, improvement > 0 {
                Text("+\(Int(improvement))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.radiusMedium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(rankColor(rank).opacity(0.3), lineWidth: 1.5)
        )
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(hex: "FFD700")
        case 2: return Color(hex: "C0C0C0")
        case 3: return Color(hex: "CD7F32")
        default: return Theme.accent
        }
    }

    private var topPRs: [PRRecord] {
        Array(insightsStore.personalRecords.values.sorted { $0.weight > $1.weight }.prefix(10))
    }

    // MARK: - Computed

    private var periodLabel: String {
        switch selectedPeriod {
        case .weekly: return "This Week"
        case .monthly: return "This Month"
        case .allTime: return "All-Time"
        }
    }

    private var periodStats: LifetimeStats {
        switch selectedPeriod {
        case .weekly: return calculatePeriodStats(days: 7)
        case .monthly: return calculatePeriodStats(days: 30)
        case .allTime: return insightsStore.lifetimeStats
        }
    }

    private func calculatePeriodStats(days: Int) -> LifetimeStats {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let relevantSnapshots = insightsStore.weeklySnapshots.filter { $0.weekStart >= cutoffDate }

        var stats = LifetimeStats()
        stats.totalWorkouts = relevantSnapshots.reduce(0) { $0 + $1.workoutCount }
        stats.totalVolume = relevantSnapshots.reduce(0.0) { $0 + $1.totalVolume }
        stats.totalSets = relevantSnapshots.reduce(0) { $0 + $1.totalSets }
        stats.totalExercises = relevantSnapshots.reduce(0) { $0 + $1.exerciseNames.count }
        return stats
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        } else if volume >= 1000 {
            return String(format: "%.1fK", volume / 1000)
        }
        return String(format: "%.0f", volume)
    }

    // MARK: - Share

    @MainActor
    private func renderShareImage(title: String, value: String, subtitle: String?, icon: String, accentColor: Color) -> UIImage? {
        let card = ShareableInsightCard(title: title, value: value, subtitle: subtitle, icon: icon, accentColor: accentColor)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        return renderer.uiImage
    }

    private func shareStatCard(icon: String, value: String, title: String, subtitle: String?, color: Color) {
        Task { @MainActor in
            if let image = renderShareImage(title: title, value: value, subtitle: subtitle, icon: icon, accentColor: color) {
                shareItem = ShareableImageItem(image: image)
            }
        }
    }

    // MARK: - Data
    private var allLinkedInsights: [LinkedInsight] {
        var insights: [LinkedInsight] = []
        for entry in workoutManager.workoutStore.index {
            if let session = workoutManager.workoutStore.loadSession(id: entry.id) {
                for story in session.stories {
                    insights.append(LinkedInsight(
                        id: story.id,
                        story: story,
                        workoutID: session.id,
                        workoutDate: session.startedAt
                    ))
                }
            }
        }
        return insights
    }

    private var allTags: [String] {
        let tags = Set(allLinkedInsights.flatMap(\.story.tags))
        return tags.sorted()
    }

    private var filteredInsights: [LinkedInsight] {
        guard let tag = selectedTag else { return allLinkedInsights }
        return allLinkedInsights.filter { $0.story.tags.contains(tag) }
    }

    // MARK: - Tag Filter
    private var tagFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: selectedTag == nil) {
                    selectedTag = nil
                }
                ForEach(allTags, id: \.self) { tag in
                    FilterChip(title: tag, isSelected: selectedTag == tag) {
                        selectedTag = tag
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Story Card
    private func storyCard(_ linked: LinkedInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(linked.story.title)
                    .font(.headline)
                Spacer()
                Text(linked.story.type.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(linked.story.type.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(linked.story.type.color)
            }

            Text(linked.story.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 4) {
                Image(systemName: "dumbbell.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
                Text(linked.workoutDate, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }

            if !linked.story.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(linked.story.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
        .themeCard()
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let metric: DashboardMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: metric.icon)
                    .font(.caption)
                    .foregroundStyle(metric.color)
                Spacer()
                if let trend = metric.trend, let trendValue = metric.trendValue {
                    HStack(spacing: 2) {
                        Image(systemName: trend.icon)
                            .font(.caption2)
                        Text(trendValue)
                            .font(.caption2)
                    }
                    .foregroundStyle(trend.color)
                }
            }

            Text(metric.value)
                .font(.title2)
                .fontWeight(.bold)

            Text(metric.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let subtitle = metric.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .themeCard()
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Theme.accentSubtle : Theme.cardBackground,
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ShareableInsightCard

struct ShareableInsightCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let icon: String
    let accentColor: Color

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "dumbbell.fill")
                    .foregroundColor(Color(hex: "10a37f"))
                Text("Mind2Muscle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }

            Spacer()

            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(accentColor)

            Text(value)
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundColor(.white)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            Text(Date().formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(24)
        .frame(width: 360, height: 480)
        .background(
            LinearGradient(
                colors: [Color(hex: "1a1a1a"), Color(hex: "0d0d0d")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(20)
    }
}
