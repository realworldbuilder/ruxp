import SwiftUI

struct InsightStoryView: View {
    let stories: [InsightStory]
    let startingStoryIndex: Int
    let onDismiss: () -> Void

    @State private var currentStoryIndex: Int
    @State private var currentPageIndex = 0
    @State private var progress: CGFloat = 0
    @State private var timer: Timer?
    @State private var isAutoAdvancing = true
    @State private var showingShareSheet = false

    private let pageDisplayTime: TimeInterval = 4.0

    init(stories: [InsightStory], startingStoryIndex: Int = 0, onDismiss: @escaping () -> Void) {
        self.stories = stories
        self.startingStoryIndex = startingStoryIndex
        self.onDismiss = onDismiss
        self._currentStoryIndex = State(initialValue: startingStoryIndex)
    }

    init(story: InsightStory, onDismiss: @escaping () -> Void) {
        self.init(stories: [story], startingStoryIndex: 0, onDismiss: onDismiss)
    }

    private var currentStory: InsightStory {
        stories[currentStoryIndex]
    }

    private var currentPages: [InsightPage] {
        currentStory.resolvedPages
    }

    private var currentPage: InsightPage {
        currentPages[currentPageIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                overallStoryProgress
                storyContent
                    .id("\(currentStoryIndex)-\(currentPageIndex)")
                pageTimerProgress
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startAutoAdvance()
            StoryReadTracker.shared.markAsRead(currentStory.storyIdentifier, contentHash: currentStory.contentHash)
        }
        .onDisappear {
            stopAutoAdvance()
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheetView(activityItems: [getShareContent()])
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 100 {
                        previousPage()
                    } else if value.translation.width < -100 {
                        nextPage()
                    } else if value.translation.height > 100 {
                        onDismiss()
                    }
                }
        )
        .onTapGesture { location in
            let screenWidth = UIScreen.main.bounds.width
            if location.x < screenWidth / 3 {
                previousPage()
            } else if location.x > 2 * screenWidth / 3 {
                nextPage()
            } else {
                toggleAutoAdvance()
            }
        }
    }

    // MARK: - Overall Story Progress (Top)
    private var overallStoryProgress: some View {
        VStack(spacing: 8) {
            if stories.count > 1 {
                HStack(spacing: 3) {
                    ForEach(0..<stories.count, id: \.self) { storyIndex in
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 3)
                            .overlay(
                                Capsule()
                                    .fill(Color.white)
                                    .scaleEffect(x: getStoryProgress(for: storyIndex), anchor: .leading)
                            )
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack {
                Spacer()
                Button(action: { showingShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .padding(.top, 60)
    }

    // MARK: - Page Timer Progress (Bottom)
    private var pageTimerProgress: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<currentPages.count, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(0.4))
                        .frame(height: 3)
                        .overlay(
                            Capsule()
                                .fill(Color.white)
                                .scaleEffect(x: getPageProgress(for: index), anchor: .leading)
                        )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 40)
        .padding(.top, 12)
    }

    // MARK: - Progress Helpers
    private func getStoryProgress(for storyIndex: Int) -> CGFloat {
        if storyIndex < currentStoryIndex {
            return 1.0
        } else if storyIndex == currentStoryIndex {
            let totalPages = currentPages.count
            return (CGFloat(currentPageIndex) + progress) / CGFloat(totalPages)
        } else {
            return 0.0
        }
    }

    private func getPageProgress(for pageIndex: Int) -> CGFloat {
        if pageIndex < currentPageIndex {
            return 1.0
        } else if pageIndex == currentPageIndex {
            return progress
        } else {
            return 0.0
        }
    }

    // MARK: - Story Content
    private var storyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: currentStory.type.systemIcon)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                    }

                    Text(currentStory.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text(currentPage.title)
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.9))
                }

                Text(currentPage.content)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineSpacing(4)

                if let chartData = currentPage.chartData {
                    chartView(chartData)
                        .padding(.vertical, 16)
                }

                if let actionable = currentPage.actionable {
                    actionableCard(actionable)
                }

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Chart View
    @ViewBuilder
    func chartView(_ chartData: InsightChartData) -> some View {
        switch chartData.chartType {
        case .volumeOverTime:
            VolumeOverTimeChart(dataPoints: chartData.dataPoints)
        case .progressTrend:
            ProgressTrendChart(dataPoints: chartData.dataPoints)
        case .prComparison:
            PRComparisonChart(dataPoints: chartData.dataPoints)
        }
    }

    // MARK: - Actionable Card
    private func actionableCard(_ actionable: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(Theme.accent.opacity(0.8))
                Text("Action Item")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }

            Text(actionable)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(16)
    }

    // MARK: - Navigation
    private func nextPage() {
        stopAutoAdvance()

        withAnimation(.easeInOut(duration: 0.3)) {
            if currentPageIndex < currentPages.count - 1 {
                currentPageIndex += 1
                progress = 0
            } else if currentStoryIndex < stories.count - 1 {
                currentStoryIndex += 1
                currentPageIndex = 0
                progress = 0
                StoryReadTracker.shared.markAsRead(currentStory.storyIdentifier, contentHash: currentStory.contentHash)
            } else {
                onDismiss()
                return
            }
        }

        startAutoAdvance()
    }

    private func previousPage() {
        stopAutoAdvance()

        withAnimation(.easeInOut(duration: 0.3)) {
            if currentPageIndex > 0 {
                currentPageIndex -= 1
                progress = 0
            } else if currentStoryIndex > 0 {
                currentStoryIndex -= 1
                currentPageIndex = stories[currentStoryIndex].resolvedPages.count - 1
                progress = 0
            }
        }

        startAutoAdvance()
    }

    private func startAutoAdvance() {
        guard isAutoAdvancing else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            withAnimation(.linear(duration: 0.1)) {
                progress += 0.1 / pageDisplayTime
                if progress >= 1.0 {
                    nextPage()
                }
            }
        }
    }

    private func stopAutoAdvance() {
        timer?.invalidate()
        timer = nil
    }

    private func toggleAutoAdvance() {
        isAutoAdvancing.toggle()
        if isAutoAdvancing {
            startAutoAdvance()
        } else {
            stopAutoAdvance()
        }
    }

    // MARK: - Share
    private func getShareContent() -> String {
        var text = """
        \(currentStory.title)

        \(currentPage.content)
        """
        if let actionable = currentPage.actionable {
            text += "\n\n\(actionable)"
        }
        return text
    }
}

// ShareSheetView is defined in SettingsView.swift
