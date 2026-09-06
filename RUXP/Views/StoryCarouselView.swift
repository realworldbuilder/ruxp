import SwiftUI

struct StoryCarouselView: View {
    let stories: [InsightStory]
    let onStoryTapped: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(Array(stories.enumerated()), id: \.element.id) { index, story in
                    StoryBadgeView(story: story) {
                        onStoryTapped(index)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct StoryBadgeView: View {
    let story: InsightStory
    let action: () -> Void

    private var isUnread: Bool {
        StoryReadTracker.shared.isUnread(story.storyIdentifier, contentHash: story.contentHash)
    }

    @State private var glowPhase = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    // Subtle ring
                    Circle()
                        .stroke(
                            Theme.accent.opacity(isUnread ? 0.8 : 0.4),
                            lineWidth: isUnread ? 3 : 2
                        )
                        .frame(width: 64, height: 64)

                    // Icon background
                    Circle()
                        .fill(Theme.cardBackground)
                        .frame(width: 56, height: 56)

                    // Icon
                    Image(systemName: story.type.systemIcon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                .overlay(
                    Circle()
                        .stroke(Theme.accent.opacity(glowPhase ? 0.6 : 0), lineWidth: 2)
                        .frame(width: 68, height: 68)
                        .scaleEffect(glowPhase ? 1.1 : 1.0)
                )

                Text(story.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            if isUnread {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    glowPhase = true
                }
            }
        }
    }
}
