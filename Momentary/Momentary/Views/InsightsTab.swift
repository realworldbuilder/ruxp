import SwiftUI

struct InsightsTab: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(InsightsEngine.self) private var insightsService
    @Environment(InsightsStore.self) private var insightsStore
    @State private var selectedTag: String?
    @State private var showingStoryViewer = false
    @State private var storyViewerStartIndex = 0
    @State private var showingLifetimeDetail = false
    @State private var showingPRDetail = false

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
                    // Story Carousel
                    if !insightsService.stories.isEmpty {
                        storyCarouselSection
                    }

                    // Dashboard Metrics
                    if !insightsService.dashboardMetrics.isEmpty {
                        dashboardSection
                    }

                    // Persistent lifetime stats (always show if we have data)
                    if insightsStore.lifetimeStats.totalWorkouts > 0 {
                        lifetimeSection
                            .onTapGesture { showingLifetimeDetail = true }
                    }

                    // Persistent PRs
                    if !insightsStore.personalRecords.isEmpty {
                        prSection
                            .onTapGesture { showingPRDetail = true }
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

    // MARK: - Dashboard Section
    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("This Week", systemImage: "chart.bar.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(insightsService.dashboardMetrics) { metric in
                    MetricCard(metric: metric)
                }
            }
            .padding(.horizontal)
        }
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

    // MARK: - Lifetime Stats Section
    private var lifetimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("All-Time", systemImage: "trophy.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                lifetimeStatCard(
                    icon: "figure.strengthtraining.traditional",
                    value: "\(insightsStore.lifetimeStats.totalWorkouts)",
                    title: "Workouts",
                    subtitle: insightsStore.lifetimeStats.daysSinceFirst.map { "over \($0) days" },
                    color: .green
                )
                lifetimeStatCard(
                    icon: "scalemass.fill",
                    value: formatVolume(insightsStore.lifetimeStats.totalVolume),
                    title: "Total Volume",
                    subtitle: "lbs lifted",
                    color: .blue
                )
                lifetimeStatCard(
                    icon: "repeat",
                    value: "\(insightsStore.lifetimeStats.totalSets)",
                    title: "Total Sets",
                    subtitle: String(format: "%.0f avg/workout", insightsStore.lifetimeStats.averageSetsPerWorkout),
                    color: .purple
                )
                lifetimeStatCard(
                    icon: "dumbbell.fill",
                    value: "\(insightsStore.lifetimeStats.totalExercises)",
                    title: "Exercises",
                    subtitle: "logged",
                    color: .orange
                )
            }
            .padding(.horizontal)
        }
    }

    private func lifetimeStatCard(icon: String, value: String, title: String, subtitle: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    // MARK: - PR Section
    private var prSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Personal Records", systemImage: "star.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(spacing: 12) {
                // Top 3 PRs - Achievement Wall Style
                if topPRs.count >= 3 {
                    HStack(spacing: 8) {
                        ForEach(Array(topPRs.prefix(3).enumerated()), id: \.element.id) { index, pr in
                            topPRCard(pr: pr, rank: index + 1)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Remaining PRs as smaller rows
                if topPRs.count > 3 {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(topPRs.dropFirst(3).prefix(7))) { pr in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pr.exercise)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Theme.textPrimary)
                                    if let date = pr.date as Date? {
                                        Text(date, format: .dateTime.month(.abbreviated).day())
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(Int(pr.weight)) lbs")
                                        .font(.headline)
                                        .foregroundStyle(Theme.accent)
                                    if let improvement = pr.improvement, improvement > 0 {
                                        Text("+\(Int(improvement)) lbs")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .themeCard()
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private func topPRCard(pr: PRRecord, rank: Int) -> some View {
        VStack(spacing: 8) {
            // Rank indicator
            ZStack {
                Circle()
                    .fill(rankColor(rank).opacity(0.2))
                    .frame(width: 24, height: 24)
                Text("\(rank)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(rankColor(rank))
            }
            
            // Weight - The star of the show
            VStack(spacing: 2) {
                Text("\(Int(pr.weight))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                
                Text("lbs")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            
            // Exercise name
            Text(pr.exercise)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            
            // Improvement if available
            if let improvement = pr.improvement, improvement > 0 {
                Text("+\(Int(improvement))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Text("")
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .padding(12)
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
                .stroke(rankColor(rank).opacity(0.3), lineWidth: 1.5)
        )
    }
    
    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(hex: "FFD700") // Gold
        case 2: return Color(hex: "C0C0C0") // Silver
        case 3: return Color(hex: "CD7F32") // Bronze
        default: return Theme.accent
        }
    }

    private var topPRs: [PRRecord] {
        Array(insightsStore.personalRecords.values.sorted { $0.weight > $1.weight }.prefix(10))
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        } else if volume >= 1000 {
            return String(format: "%.1fK", volume / 1000)
        }
        return String(format: "%.0f", volume)
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
