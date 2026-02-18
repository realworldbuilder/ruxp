import SwiftUI

@main
struct Mind2MuscleApp: App {
    @State private var workoutManager: WorkoutManager
    @State private var workoutProcessor: WorkoutProcessor
    @State private var insightsEngine: InsightsEngine
    @State private var chatEngine: ChatEngine

    init() {
        let store = WorkoutStore()
        let aiService = AIService()
        let transcription = TranscriptionService()
        let connectivity = ConnectivityService()
        let healthKit = HealthKitService()
        let processor = WorkoutProcessor(aiService: aiService, workoutStore: store)
        let insights = InsightsEngine(workoutStore: store, aiService: aiService)
        let chat = ChatEngine(workoutStore: store, insightsEngine: insights, aiService: aiService)
        let manager = WorkoutManager(
            workoutStore: store,
            connectivity: connectivity,
            transcription: transcription,
            healthKit: healthKit,
            processor: processor
        )
        processor.insightsEngine = insights

        _workoutManager = State(initialValue: manager)
        _workoutProcessor = State(initialValue: processor)
        _insightsEngine = State(initialValue: insights)
        _chatEngine = State(initialValue: chat)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(workoutManager)
                .environment(workoutProcessor)
                .environment(insightsEngine)
                .environment(chatEngine)
                .preferredColorScheme(.dark)
                .task {
                    await workoutProcessor.processPendingQueue()
                    await insightsEngine.generateInsights()
                }
        }
    }
}
