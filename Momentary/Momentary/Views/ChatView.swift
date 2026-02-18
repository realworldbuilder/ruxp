import SwiftUI

struct ChatView: View {
    @Environment(ChatEngine.self) private var chatService
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WorkoutProcessor.self) private var aiPipeline
    @State private var inputText = ""
    @State private var navigationPath = NavigationPath()
    @State private var showExportSheet = false
    @State private var exportData: Data?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                if chatService.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                inputBar
            }
            .background(Theme.background)
            .navigationTitle("Trainer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !chatService.messages.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            chatService.clearConversation()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { workoutID in
                WorkoutDetailView(workoutID: workoutID)
            }
            .sheet(isPresented: $showExportSheet) {
                if let data = exportData {
                    ShareSheet(data: data)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(Theme.textTertiary)

            Text("Your AI training coach. Ask about your workouts, plan your next session, or get form tips.")
                .font(.title3)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SuggestedChip(text: "Plan workout", icon: "calendar.badge.plus") {
                    sendMessage("Plan my next workout")
                }
                SuggestedChip(text: "My progress", icon: "chart.line.uptrend.xyaxis") {
                    sendMessage("How's my progress?")
                }
                SuggestedChip(text: "Weekly summary", icon: "calendar.day.timeline.leading") {
                    sendMessage("Give me a weekly summary")
                }
                SuggestedChip(text: "Focus areas", icon: "target") {
                    sendMessage("What should I focus on?")
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(chatService.messages) { message in
                        ChatMessageView(
                            message: message,
                            onAction: { action in handleAction(action) },
                            onWorkoutTap: { id in navigationPath.append(id) }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: chatService.messages.count) {
                if let lastID = chatService.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask your trainer...", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .foregroundColor(Theme.textPrimary)

            Button {
                sendMessage(inputText)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.textTertiary : Theme.accent)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || chatService.isResponding)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.background)
    }

    // MARK: - Actions

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        Task {
            await chatService.send(trimmed)
        }
    }

    private func handleAction(_ action: ChatAction) {
        switch action.actionType {
        case .startWorkout:
            workoutManager.startWorkout()
        case .viewWorkout:
            if let idStr = action.workoutId, let uuid = UUID(uuidString: idStr) {
                navigationPath.append(uuid)
            }
        case .analyzeWorkout:
            if let idStr = action.workoutId, let uuid = UUID(uuidString: idStr) {
                if let session = workoutManager.workoutStore.loadSession(id: uuid) {
                    Task { await aiPipeline.processWorkout(session) }
                }
            }
        case .exportData:
            if let data = workoutManager.workoutStore.exportAllSessionsAsJSON() {
                exportData = data
                showExportSheet = true
            }
        }
    }
}

// MARK: - Suggested Chip

private struct SuggestedChip: View {
    let text: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(text)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Theme.accentSubtle, in: RoundedRectangle(cornerRadius: Theme.radiusMedium))
        }
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let data: Data

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("momentary_export.json")
        try? data.write(to: tempURL)
        return UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
