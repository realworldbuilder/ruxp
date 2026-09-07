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
    @State private var gameCenter: GameCenterService
    @State private var livePresence: GameCenterLivePresence
    @State private var liveSessions: LiveSessionService
    @State private var liveRoom: LiveRoomService
    @State private var liveOps: LiveOpsService
    @State private var world: WorldSnapshotService
    @State private var crew: CrewService
    private let eventService = ScheduledEventService()

    init() {
        Typeface.registerFonts()
        Self.applyDebugLaunchArguments()
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
        // Live Ops first: it sets `LiveOpsCatalog.current`, which the event provider reads.
        let liveOpsService = LiveOpsService()
        let progressionService = ProgressionService()
        let events = ScheduledEventService()
        let gameCenterService = GameCenterService(progression: progressionService)
        progressionService.onProgressChanged = { [weak gameCenterService] in gameCenterService?.noteProgressChanged($0) }
        let presence = GameCenterLivePresence(gameCenter: gameCenterService, season: progressionService.season)
        gameCenterService.onSyncEnabledChanged = { [weak connectivity] in connectivity?.pushGameCenterSync($0) }
        connectivity.pushGameCenterSync(gameCenterService.isSyncEnabled)
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
        manager.gameCenter = gameCenterService

        // RUXP Live: participation record + optional Training Room. Both sit behind services so
        // views never touch GameKit and the presence source can be swapped later.
        let liveSessionService = LiveSessionService(events: events, presence: presence)
        liveSessionService.playerIDProvider = { [weak gameCenterService] in gameCenterService?.playerID }
        gameCenterService.onPlayerIdentified = { [weak liveSessionService] in liveSessionService?.attachPlayerID($0) }
        // Joining counts you in the event's window right away ("84 players joined" is joins, not finishes).
        liveSessionService.onJoined = { [weak gameCenterService] event in
            guard let board = GameCenterCatalog.eventBoard(for: event) else { return }
            Task { await gameCenterService?.submitPresence(boards: [board]) }
        }
        let room = LiveRoomService(gameCenter: gameCenterService)
        liveSessionService.roomPeerCountProvider = { [weak room] in
            guard let room, room.peakPeerCount > 0 else { return nil }
            return room.peakPeerCount
        }
        manager.liveSessions = liveSessionService
        manager.onWorkoutEnded = { [weak room] in room?.leave() }
        // Moments stored while offline get transcribed the moment the network is back.
        processor.onNetworkRestored = { [weak manager] in await manager?.retryPendingTranscriptions() }

        // Your crew: Game Center friends who lift. Reads the crew boards; pays CREW WEEK.
        let crewService = CrewService(gameCenter: gameCenterService, progression: progressionService, season: progressionService.season)
        manager.crew = crewService

        // The world keeps moving while the player is gone. One snapshot hook: the presence
        // poller feeds both the watch and the live-event join counts the ledger remembers.
        let worldService = WorldSnapshotService(events: events, season: progressionService.season,
                                                progression: progressionService, gameCenter: gameCenterService,
                                                presence: presence)
        worldService.crewStateProvider = { [weak crewService] in crewService?.state }
        worldService.crewRefresh = { [weak crewService] in await crewService?.refresh() }
        crewService.onSnapshotChanged = { [weak worldService] in worldService?.noteCrewUpdated() }
        presence.onSnapshotChanged = { [weak connectivity, weak worldService] snapshot in
            connectivity?.pushPresence(snapshot)
            worldService?.notePresenceUpdated()
        }

        _workoutManager = State(initialValue: manager)
        _workoutProcessor = State(initialValue: processor)
        _insightsEngine = State(initialValue: insights)
        _chatEngine = State(initialValue: chat)
        _conversationStore = State(initialValue: convoStore)
        _insightsStore = State(initialValue: persistentInsights)
        _workoutStore = State(initialValue: store)
        _plannedWorkoutStore = State(initialValue: plannedStore)
        _progression = State(initialValue: progressionService)
        _gameCenter = State(initialValue: gameCenterService)
        _livePresence = State(initialValue: presence)
        _liveSessions = State(initialValue: liveSessionService)
        _liveRoom = State(initialValue: room)
        _liveOps = State(initialValue: liveOpsService)
        _world = State(initialValue: worldService)
        _crew = State(initialValue: crewService)

        #if DEBUG
        // -RUXPLoadSamples: seed the seven sample workouts on an empty install (simulator screenshots).
        if ProcessInfo.processInfo.arguments.contains("-RUXPLoadSamples"), store.index.isEmpty {
            for session in SampleDataGenerator.generate() { store.saveSession(session) }
            store.loadIndex()
            persistentInsights.rebuild(from: store)
        }
        #endif

        // Rebuild persistent insights if empty (first launch / migration)
        if persistentInsights.lifetimeStats.totalWorkouts == 0 && !store.index.isEmpty {
            persistentInsights.rebuild(from: store)
        }
        // Seed progression from existing history so an upgrade starts with a real level
        if progressionService.progress.workoutCount == 0 && !store.index.isEmpty {
            let sessions = store.index.compactMap { store.loadSession(id: $0.id) }
            progressionService.rebuild(from: sessions, events: events)
        }
        // Live history for players whose event bonuses predate the participation file.
        if liveSessionService.participations.isEmpty && !progressionService.progress.eventsJoined.isEmpty {
            let sessions = store.index.compactMap { store.loadSession(id: $0.id) }
            liveSessionService.backfill(from: progressionService.progress, sessions: sessions)
        }

        #if DEBUG
        // -RUXPLiveScene active|complete: drop straight into a Live Session workout or its reward
        // screen (pair with -RUXPEventClock sunday -RUXPSkipMinimum). "lobby" is handled by HomeView.
        if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-RUXPLiveScene"),
           idx + 1 < ProcessInfo.processInfo.arguments.count {
            switch ProcessInfo.processInfo.arguments[idx + 1] {
            case "active":
                manager.startWorkout()
            case "complete":
                manager.startWorkout()
                manager.endWorkout()
            default:
                break
            }
        }
        #endif
    }

    @Environment(\.scenePhase) private var scenePhase

    /// DEBUG-only knobs for exercising the reward flow quickly:
    ///   -RUXPSkipMinimum   no 10-minute minimum for completion XP
    ///   -RUXPEventClock friday|sunday|tuesday   pretend it is that day
    ///   -RUXPLoadSamples   seed sample workouts on an empty install
    ///   -RUXPTab train|profile   open on that tab (see MainTabView)
    ///   -RUXPSkipHealthKit   bypass HealthKit (see HealthKitService.isDisabledForTesting)
    ///   -RUXPSkipGameCenter  no Game Center sign-in, scores, or live counts (see GameCenterService.isDisabledForTesting)
    ///   -RUXPLiveScene lobby|active|complete   open the Live Session lobby, a joined workout, or its reward screen
    ///   -RUXPSeason S00|S01|S02   pretend that season is current (exercise the rollover and recap)
    ///   -RUXPLastSeen 3d|18h|45m   pretend the last visit was that long ago (WHILE YOU WERE GONE)
    ///   -RUXPWorldDemo   with Game Center off, seed friends/rank so every ledger line renders
    ///   -RUXPLiveOps off|<path.json>   no Live Ops rules, or a local calendar instead of the remote one
    ///   -RUXPScreen seasonpass|settings|livehistory|archivedpass   open that sheet at launch (see MainTabView)
    ///   -RUXPCrewDemo [room|last|final|complete|empty]   with Game Center off, seed a crew in that state



    private static func applyDebugLaunchArguments() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-RUXPSkipMinimum") { ProgressionRules.minimumWorkoutDuration = 0 }
        // -RUXPSeason S01: pretend that season is current (rollover, boards, ladders). The
        // Developer picker stores the same thing in UserDefaults for the next relaunch.
        if let idx = args.firstIndex(of: "-RUXPSeason"), idx + 1 < args.count {
            SeasonCatalog.overrideID = args[idx + 1]
        } else if let id = UserDefaults.standard.string(forKey: "ruxp.debugSeasonOverride"), !id.isEmpty {
            SeasonCatalog.overrideID = id
        }
        if let idx = args.firstIndex(of: "-RUXPLastSeen"), idx + 1 < args.count {
            let raw = args[idx + 1].lowercased()
            let number = Double(raw.filter { $0.isNumber || $0 == "." }) ?? 0
            let unit: Double = raw.hasSuffix("d") ? 86400 : raw.hasSuffix("m") ? 60 : 3600
            WorldSnapshotService.debugLastSeen = number * unit
        }
        if args.contains("-RUXPWorldDemo") { WorldSnapshotService.debugDemo = true }
        if let idx = args.firstIndex(of: "-RUXPCrewDemo") {
            let value = idx + 1 < args.count && !args[idx + 1].hasPrefix("-") ? args[idx + 1] : "room"
            CrewService.demoMode = value
        }

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
                .environment(gameCenter)
                .environment(\.livePresence, livePresence)
                .environment(\.liveEvents, eventService)
                .environment(liveSessions)
                .environment(\.liveRoom, liveRoom)
                .environment(liveOps)
                .environment(world)
                .environment(crew)
                .preferredColorScheme(.dark)
                .task {
                    gameCenter.start()
                    livePresence.start()
                    liveOps.refresh()
                    crew.start()
                    world.noteForeground()
                    await workoutProcessor.processPendingQueue()
                    await workoutManager.retryPendingTranscriptions()
                    // InsightsEngine (Momentary story generation) renders nowhere in RUXP; it is
                    // not run so the bundled OpenAI key is spent only on parsing voice notes.

                }
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        // Restore active workout if app was backgrounded/killed
                        workoutManager.refreshActiveSession()
                        Task { await workoutManager.retryPendingTranscriptions() }
                        livePresence.start()
                        liveOps.refresh()
                        crew.start()
                        world.noteForeground()
                    } else if scenePhase == .background {
                        // Snapshot first, while the last live count is still in hand.
                        world.noteBackground()
                        livePresence.stop()
                        crew.stop()


                        gameCenter.flushNow()
                        // Real-time rooms are foreground-only; the peer connection dies when suspended.
                        liveRoom.leave()
                    }
                }
        }
    }
}
