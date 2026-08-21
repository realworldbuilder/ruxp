import SwiftUI

@main
struct Mind2MuscleApp: App {
    @State private var workoutManager: WorkoutManager
    @State private var workoutProcessor: WorkoutProcessor
    @State private var insightsEngine: InsightsEngine
    @State private var chatEngine: ChatEngine
    @State private var conversationStore: ConversationStore
    @State private var insightsStore: InsightsStore
    @State private var workoutStore: WorkoutStore
    @State private var plannedWorkoutStore = PlannedWorkoutStore()

    init() {
        let store = WorkoutStore()
        let aiService = AIService()
        let transcription = TranscriptionService(aiService: aiService)
        let connectivity = ConnectivityService()
        let healthKit = HealthKitService()
        let processor = WorkoutProcessor(aiService: aiService, workoutStore: store)
        let insights = InsightsEngine(workoutStore: store, aiService: aiService)
        let persistentInsights = InsightsStore()
        let convoStore = ConversationStore()
        let chat = ChatEngine(workoutStore: store, insightsEngine: insights, aiService: aiService, conversationStore: convoStore)
        let manager = WorkoutManager(
            workoutStore: store,
            connectivity: connectivity,
            transcription: transcription,
            healthKit: healthKit,
            processor: processor
        )
        processor.insightsEngine = insights
        processor.insightsStore = persistentInsights

        _workoutManager = State(initialValue: manager)
        _workoutProcessor = State(initialValue: processor)
        _insightsEngine = State(initialValue: insights)
        _chatEngine = State(initialValue: chat)
        _conversationStore = State(initialValue: convoStore)
        _insightsStore = State(initialValue: persistentInsights)
        _workoutStore = State(initialValue: store)

        // Rebuild persistent insights if empty (first launch / migration)
        if persistentInsights.lifetimeStats.totalWorkouts == 0 && !store.index.isEmpty {
            persistentInsights.rebuild(from: store)
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(workoutManager)
                .environment(workoutProcessor)
                .environment(insightsEngine)
                .environment(chatEngine)
                .environment(conversationStore)
                .environment(insightsStore)
                .environment(workoutStore)
                .environment(plannedWorkoutStore)
                .preferredColorScheme(.dark)
                .task {
                    await workoutProcessor.processPendingQueue()
                    await insightsEngine.generateInsights()
                }
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        // Restore active workout if app was backgrounded/killed
                        workoutManager.refreshActiveSession()
                    }
                }
        }
    }
}
