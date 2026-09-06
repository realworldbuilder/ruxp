import SwiftUI

@main
struct RUXPApp: App {
    @State private var workoutManager: WorkoutManager
    @State private var workoutProcessor: WorkoutProcessor
    @State private var insightsEngine: InsightsEngine
    @State private var chatEngine: ChatEngine
    @State private var conversationStore: ConversationStore
    @State private var insightsStore: InsightsStore
    @State private var workoutStore: WorkoutStore
    @State private var plannedWorkoutStore: PlannedWorkoutStore
    @State private var progression: ProgressionService
    @State private var livePresence: SimulatedLivePresence
    private let eventService = ScheduledEventService()

    init() {
        let store = WorkoutStore()
        let plannedStore = PlannedWorkoutStore()
        let aiService = AIService()
        let transcription = TranscriptionService(aiService: aiService)
        let connectivity = ConnectivityService()
        let healthKit = HealthKitService()
        let processor = WorkoutProcessor(aiService: aiService, workoutStore: store)
        let insights = InsightsEngine(workoutStore: store, aiService: aiService)
        let persistentInsights = InsightsStore()
        let convoStore = ConversationStore()
        let chat = ChatEngine(workoutStore: store, insightsEngine: insights, aiService: aiService, conversationStore: convoStore)
        let progressionService = ProgressionService()
        let events = ScheduledEventService()
        let presence = SimulatedLivePresence(tickInterval: 4)
        let manager = WorkoutManager(
            workoutStore: store,
            connectivity: connectivity,
            transcription: transcription,
            healthKit: healthKit,
            processor: processor,
            plannedWorkoutStore: plannedStore,
            progression: progressionService,
            events: events
        )
        processor.insightsEngine = insights
        processor.insightsStore = persistentInsights
        processor.progression = progressionService

        _workoutManager = State(initialValue: manager)
        _workoutProcessor = State(initialValue: processor)
        _insightsEngine = State(initialValue: insights)
        _chatEngine = State(initialValue: chat)
        _conversationStore = State(initialValue: convoStore)
        _insightsStore = State(initialValue: persistentInsights)
        _workoutStore = State(initialValue: store)
        _plannedWorkoutStore = State(initialValue: plannedStore)
        _progression = State(initialValue: progressionService)
        _livePresence = State(initialValue: presence)

        // Rebuild persistent insights if empty (first launch / migration)
        if persistentInsights.lifetimeStats.totalWorkouts == 0 && !store.index.isEmpty {
            persistentInsights.rebuild(from: store)
        }
        // Seed progression from existing history so an upgrade starts with a real level
        if progressionService.progress.workoutCount == 0 && !store.index.isEmpty {
            let sessions = store.index.compactMap { store.loadSession(id: $0.id) }
            progressionService.rebuild(from: sessions, events: events)
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    /// DEBUG-only knobs for exercising the reward flow quickly:
    ///   -RUXPSkipMinimum   no 10-minute minimum for completion XP
    ///   -RUXPEventClock friday|sunday|tuesday   pretend it is that day
    private func applyDebugLaunchArguments() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-RUXPSkipMinimum") { ProgressionRules.minimumWorkoutDuration = 0 }
        if let idx = args.firstIndex(of: "-RUXPEventClock"), idx + 1 < args.count {
            let cal = Calendar.current
            var comps = DateComponents()
            comps.minute = 0
            switch args[idx + 1] {
            case "friday": comps.weekday = 6; comps.hour = 19
            case "sunday": comps.weekday = 1; comps.hour = 12
            case "tuesday": comps.weekday = 3; comps.hour = 10
            default: return
            }
            ScheduledEventService.clockOverride = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime)
        }
        #endif
    }

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
                .environment(progression)
                .environment(\.livePresence, livePresence)
                .environment(\.liveEvents, eventService)
                .preferredColorScheme(.dark)
                .task {
                    applyDebugLaunchArguments()
                    livePresence.start()
                    await workoutProcessor.processPendingQueue()
                    await insightsEngine.generateInsights()
                }
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        // Restore active workout if app was backgrounded/killed
                        workoutManager.refreshActiveSession()
                        livePresence.start()
                    } else if scenePhase == .background {
                        livePresence.stop()
                    }
                }
        }
    }
}
