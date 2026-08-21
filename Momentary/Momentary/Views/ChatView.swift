import SwiftUI

struct ChatView: View {
    @Environment(ChatEngine.self) private var chatService
    @Environment(ConversationStore.self) private var conversationStore
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WorkoutProcessor.self) private var aiPipeline
    @Environment(WorkoutStore.self) private var workoutStore
    @State private var inputText = ""
    @State private var navigationPath = NavigationPath()
    @State private var showExportSheet = false
    @State private var exportData: Data?
    @State private var showHistory = false

    var body: some View {
        chatView
    }

    private var chatView: some View {
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
    
    // MARK: - Contextual Chips

    private var contextualChips: [(text: String, icon: String, message: String)] {
        let calendar = Calendar.current
        let now = Date()
        
        // Check for recent workouts
        let recentWorkouts = workoutStore.index.filter {
            calendar.isDateInToday($0.startedAt)
        }
        
        let lastWorkout = workoutStore.index.first
        let daysSinceLastWorkout: Int = {
            guard let lastWorkoutDate = lastWorkout?.startedAt else { return 999 }
            return calendar.dateComponents([.day], from: lastWorkoutDate, to: now).day ?? 999
        }()
        
        // Check for workout completed in last hour
        let recentlyCompleted = workoutStore.index.first?.endedAt.map {
            now.timeIntervalSince($0) < 3600 // Less than 1 hour ago
        } ?? false
        
        var chips: [(text: String, icon: String, message: String)] = []
        
        // Contextual first chip
        if recentlyCompleted {
            chips.append(("Analyze my workout", "chart.line.uptrend.xyaxis", "Analyze my last workout"))
        } else if recentWorkouts.isEmpty && daysSinceLastWorkout < 1 {
            chips.append(("Plan today's workout", "calendar.badge.plus", "Plan my workout for today"))
        } else if daysSinceLastWorkout >= 3 {
            chips.append(("Get back on track", "figure.run", "I haven't worked out in a few days, help me get back on track"))
        } else {
            chips.append(("Plan workout", "calendar.badge.plus", "Plan my next workout"))
        }
        
        // Always include these core chips
        chips.append(("What should I focus on?", "target", "What should I focus on?"))
        chips.append(("Check my progress", "chart.line.uptrend.xyaxis", "How's my progress?"))
        
        // Fourth chip based on context
        if workoutStore.index.count >= 7 {
            chips.append(("Weekly summary", "calendar.day.timeline.leading", "Give me a weekly summary"))
        } else {
            chips.append(("Training tips", "lightbulb", "Give me some training tips"))
        }
        
        return chips
    }

    // MARK: - History List

    private var historyList: some View {
        Group {
            if conversationStore.conversations.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    
                    Circle()
                        .fill(Theme.surface)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.accent)
                        )
                    
                    VStack(spacing: 8) {
                        Text("No conversations yet")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Theme.textPrimary)
                        Text("Start chatting with your trainer\nto see your history here")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button {
                        withAnimation { showHistory = false }
                    } label: {
                        Text("Start a conversation")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Theme.background)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                    
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Grouped near bottom — icon, prompt, chips all together
            VStack(spacing: 20) {
                // Branding
                VStack(spacing: 10) {
                    Circle()
                        .fill(Theme.surface)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.title3)
                                .foregroundColor(Theme.accent)
                        )
                    
                    Text("How can I help with\nyour training?")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                
                // Suggestion chips right below
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(contextualChips, id: \.text) { chip in
                        SuggestedChip(text: chip.text, icon: chip.icon) {
                            sendMessage(chip.message)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
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
        HStack {
            HStack(spacing: 8) {
                TextField("Ask your trainer...", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
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
            .padding(.vertical, 14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusPill))
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
                    .font(.caption2)
                Text(text)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.border, lineWidth: 1)
            )
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
