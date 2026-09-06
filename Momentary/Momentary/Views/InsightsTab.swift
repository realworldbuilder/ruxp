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
    @State private var intelligenceEngine: InsightsIntelligenceEngine?

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
                    // Story Carousel (includes trainer feedback as a story)
                    if !allStories.isEmpty {
                        StoryCarouselView(stories: allStories) { index in
                            storyViewerStartIndex = index
                            showingStoryViewer = true
                        }
                    }
                    
                    // Time Period Toggle
                    Picker("Time Period", selection: $selectedPeriod) {
                        ForEach(TimePeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Unified Stats Section (one section, controlled by toggle)
                    if periodStats.totalWorkouts > 0 || insightsStore.lifetimeStats.totalWorkouts > 0 {
                        statsSection
                    }
                    
                    // PR Predictions (NEW)
                    if let engine = intelligenceEngine, !engine.prPredictions.isEmpty {
                        prPredictionsSection
                    }

                    // Persistent PRs
                    if !insightsStore.personalRecords.isEmpty {
                        prSection
                    }
                    
                    // Muscle Balance now lives in story carousel
                    
                    // Smart Insight Cards (NEW)
                    if let engine = intelligenceEngine, !engine.smartInsights.isEmpty {
                        smartInsightsSection
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
                    stories: allStories,
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
                // Initialize intelligence engine
                if intelligenceEngine == nil {
                    intelligenceEngine = InsightsIntelligenceEngine(
                        insightsStore: insightsStore,
                        workoutStore: workoutManager.workoutStore
                    )
                }
                
                await insightsService.generateInsights()
                await intelligenceEngine?.generateIntelligence()
            }
            .onReceive(NotificationCenter.default.publisher(for: .workoutsDidChange)) { _ in
                Task { 
                    await insightsService.generateInsights()
                    await intelligenceEngine?.generateIntelligence()
                }
            }
        }
    }

    // MARK: - All Stories (including trainer feedback + weekly comparison)
    private var allStories: [InsightStory] {
        // Start with AI-generated stories but filter out weekly reviews to avoid duplicates
        var stories = insightsService.stories.filter { $0.type != .weeklyReview }
        
        // Add ONE weekly comparison story (computed from intelligence engine)
        if let engine = intelligenceEngine {
            let comp = engine.weeklyComparison
            let hasData = comp.volumeChange.direction != .same || comp.workoutChange.direction != .same
            if hasData {
                let body = """
                Volume: \(comp.volumeChange.displayValue)
                Workouts: \(comp.workoutChange.displayValue)
                Exercises: \(comp.exerciseChange.displayValue)
                Sets: \(comp.setsChange.displayValue)
                """
                let preview = "Vol \(comp.volumeChange.displayValue) · Workouts \(comp.workoutChange.displayValue)"
                let weeklyStory = InsightStory(
                    title: "This Week vs Last",
                    body: body,
                    tags: ["weekly", "comparison"],
                    type: .weeklyReview,
                    preview: preview
                )
                stories.insert(weeklyStory, at: 0)
            }
        }
        
        // Merge muscle balance into existing nextGoals story (append as extra page context)
        // If no nextGoals story exists, skip — muscle balance alone isn't worth a carousel slot
        if let engine = intelligenceEngine, !engine.muscleBalance.muscleGroups.isEmpty {
            if let idx = stories.firstIndex(where: { $0.type == .nextGoals }) {
                let groups = engine.muscleBalance.muscleGroups.map { "\($0.muscleGroup): \(Int($0.percentage))%" }
                let balanceText = groups.joined(separator: " · ")
                let existing = stories[idx]
                stories[idx] = InsightStory(
                    title: existing.title,
                    body: existing.body + "\n\nBalance: " + balanceText,
                    tags: existing.tags + ["balance"],
                    type: existing.type,
                    pages: existing.pages,
                    preview: existing.preview,
                    generatedAt: existing.generatedAt
                )
            }
        }
        
        // Add trainer feedback story
        if let engine = intelligenceEngine, !engine.aiProgressSummary.isEmpty {
            let trainerStory = InsightStory(
                title: "Trainer Feedback",
                body: engine.aiProgressSummary,
                tags: ["trainer", "ai"],
                type: .trainerFeedback,
                preview: String(engine.aiProgressSummary.prefix(60))
            )
            stories.insert(trainerStory, at: 0)
        }
        return stories
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

            // Streak row — only show if meaningful
            if insightsStore.lifetimeStats.currentStreak > 1 || insightsStore.lifetimeStats.longestStreak > 1 {
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
    }

    private func statCard(icon: String, value: String, title: String, subtitle: String?, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.title3.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        let compoundPRs = insightsStore.personalRecords.values.filter { $0.isCompound }.sorted { $0.weight > $1.weight }
        // Prioritize compound PRs, but if we have fewer than 10, fill with isolation PRs
        if compoundPRs.count >= 10 {
            return Array(compoundPRs.prefix(10))
        } else {
            let isolationPRs = insightsStore.personalRecords.values.filter { !$0.isCompound }.sorted { $0.weight > $1.weight }
            return Array((compoundPRs + isolationPRs).prefix(10))
        }
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
    
    // MARK: - AI Progress Summary Section
    private var aiProgressSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Training Summary", systemImage: "brain.head.profile")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent.opacity(0.7))
                        .padding(.top, 2)
                    
                    Text(intelligenceEngine?.aiProgressSummary ?? "")
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(2)
                }
                .padding(16)
            }
            .background(
                LinearGradient(
                    colors: [Theme.accent.opacity(0.05), Theme.accent.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: Theme.radiusMedium)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .stroke(Theme.accent.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }
    
    // MARK: - PR Predictions Section
    private var prPredictionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("PR Predictions", systemImage: "crystal.ball")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            LazyVStack(spacing: 8) {
                ForEach(intelligenceEngine?.prPredictions ?? []) { prediction in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(Int(prediction.targetWeight))")
                                    .font(.title2.bold())
                                    .foregroundStyle(Theme.accent)
                                Text("lbs")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text(prediction.exercise)
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            
                            Text("from \(Int(prediction.currentWeight))lbs")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("~\(prediction.weeksEstimate) weeks")
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.textSecondary)
                            
                            HStack(spacing: 4) {
                                ForEach(0..<5, id: \.self) { index in
                                    Circle()
                                        .fill(index < Int(prediction.confidence * 5) ? Theme.accent : Theme.accent.opacity(0.2))
                                        .frame(width: 6, height: 6)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .themeCard()
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Muscle Balance Section
    private var muscleBalanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Muscle Balance", systemImage: "figure.strengthtraining.traditional")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                // Horizontal bar chart
                ForEach(intelligenceEngine?.muscleBalance.muscleGroups ?? []) { muscle in
                    HStack {
                        Text(muscle.muscleGroup)
                            .font(.caption.bold())
                            .frame(width: 60, alignment: .leading)
                            .foregroundStyle(Theme.textPrimary)
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Theme.cardBackground)
                                    .frame(height: 8)
                                    .cornerRadius(4)
                                
                                Rectangle()
                                    .fill(colorForMuscle(muscle.muscleGroup))
                                    .frame(width: geo.size.width * (muscle.percentage / 100), height: 8)
                                    .cornerRadius(4)
                            }
                        }
                        .frame(height: 8)
                        
                        Text("\(Int(muscle.percentage))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                }
                
                // Imbalances warning
                if !(intelligenceEngine?.muscleBalance.imbalances.isEmpty ?? true) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Balance Notes")
                                .font(.caption.bold())
                                .foregroundStyle(Theme.textPrimary)
                        }
                        
                        ForEach(intelligenceEngine?.muscleBalance.imbalances ?? [], id: \.self) { imbalance in
                            Text("• \(imbalance)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
            .themeCard()
            .padding(.horizontal)
        }
    }
    
    // MARK: - Weekly Comparison Section
    private var weeklyComparisonSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("This Week vs Last Week", systemImage: "chart.bar.xaxis")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            HStack(spacing: 12) {
                comparisonCard("Volume", change: intelligenceEngine?.weeklyComparison.volumeChange)
                comparisonCard("Workouts", change: intelligenceEngine?.weeklyComparison.workoutChange)
                comparisonCard("Exercises", change: intelligenceEngine?.weeklyComparison.exerciseChange)
                comparisonCard("Sets", change: intelligenceEngine?.weeklyComparison.setsChange)
            }
            .padding(.horizontal)
        }
    }
    
    private func comparisonCard(_ title: String, change: WeeklyChange?) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Text(change?.displayValue ?? "=")
                .font(.subheadline.bold())
                .foregroundStyle(change?.color ?? .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .themeCard()
    }
    
    // MARK: - Smart Insights Section
    private var smartInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Smart Insights", systemImage: "lightbulb.2.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            LazyVStack(spacing: 8) {
                ForEach(intelligenceEngine?.smartInsights ?? []) { insight in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: insight.type.icon)
                                .font(.title3)
                                .foregroundStyle(insight.type.color)
                            
                            Text(insight.title)
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            
                            Spacer()
                        }
                        
                        Text(insight.insight)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.caption)
                                .foregroundStyle(insight.type.color)
                            
                            Text(insight.recommendation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .background(
                        LinearGradient(
                            colors: [insight.type.color.opacity(0.05), insight.type.color.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMedium)
                            .stroke(insight.type.color.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Helper Functions
    private func colorForMuscle(_ muscle: String) -> Color {
        switch muscle.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "shoulders": return .orange
        case "legs": return .green
        case "arms": return .purple
        case "core": return .yellow
        default: return .gray
        }
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
                Text("RUXP")
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
