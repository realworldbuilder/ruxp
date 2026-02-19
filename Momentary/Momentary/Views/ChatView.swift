import SwiftUI

struct ChatView: View {
    @Environment(ChatEngine.self) private var chatService
    @Environment(ConversationStore.self) private var conversationStore
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WorkoutProcessor.self) private var aiPipeline
    @State private var inputText = ""
    @State private var navigationPath = NavigationPath()
    @State private var showExportSheet = false
    @State private var exportData: Data?
    @State private var showHistory = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                if showHistory {
                    historyList
                } else if chatService.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                if !showHistory {
                    inputBar
                }
            }
            .background(Theme.background)
            .navigationTitle(showHistory ? "Chat History" : "Trainer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showHistory.toggle()
                        }
                    } label: {
                        Image(systemName: showHistory ? "xmark" : "clock.arrow.circlepath")
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if showHistory {
                        EmptyView()
                    } else {
                        Button {
                            chatService.startNewConversation()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(Theme.accent)
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

    // MARK: - History List

    private var historyList: some View {
        Group {
            if conversationStore.conversations.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.textTertiary)
                    Text("No conversations yet")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(conversationStore.conversations) { convo in
                        Button {
                            chatService.loadConversation(convo.id)
                            withAnimation { showHistory = false }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(convo.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(conversationStore.activeConversationId == convo.id ? Theme.accent : Theme.textPrimary)
                                    .lineLimit(1)
                                Text(convo.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundColor(Theme.textTertiary)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(
                            conversationStore.activeConversationId == convo.id
                                ? Theme.accent.opacity(0.1)
                                : Theme.surface
                        )
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let convo = conversationStore.conversations[idx]
                            chatService.deleteConversation(convo.id)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
        case .askTrainer:
            if let prompt = action.prompt, !prompt.isEmpty {
                Task { await chatService.send(prompt) }
            }
        case .switchTab:
            if let idx = action.tabIndex {
                NotificationCenter.default.post(name: .switchToTab, object: nil, userInfo: ["tabIndex": idx])
            }
        case .viewInsights:
            NotificationCenter.default.post(name: .switchToTab, object: nil, userInfo: ["tabIndex": 2])
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
