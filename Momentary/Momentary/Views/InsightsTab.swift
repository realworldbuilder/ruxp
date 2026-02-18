import SwiftUI

struct InsightsTab: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(InsightsEngine.self) private var insightsService
    @State private var selectedTag: String?
    @State private var showingStoryViewer = false
    @State private var storyViewerStartIndex = 0

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

                    // Recent per-workout insights
                    if allLinkedInsights.isEmpty && insightsService.stories.isEmpty {
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
            .fullScreenCover(isPresented: $showingStoryViewer) {
                InsightStoryView(
                    stories: insightsService.stories,
                    startingStoryIndex: storyViewerStartIndex
                ) {
                    showingStoryViewer = false
                }
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
