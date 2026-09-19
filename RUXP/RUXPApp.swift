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
    @State private var livePresence: any LivePresenceProviding
    @State private var liveObjective: any SessionObjectiveProviding
    @State private var liveActivity: any LiveActivityProviding
    @State private var liveSessions: LiveSessionService
    @State private var liveRoom: LiveRoomService
    @State private var liveOps: LiveOpsService
    @State private var world: WorldSnapshotService
    @State private var crew: CrewService
    @State private var community: CommunityService
    @State private var communityMoments: CommunityMomentComposer
    @State private var router = AppRouter()
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
        // Same for the community directory (`CommunityCatalog.current`, `AppLinks.origin`).
        let communityService = CommunityService()
        let progressionService = ProgressionService()
        let events = ScheduledEventService()
        let gameCenterService = GameCenterService(progression: progressionService)
        progressionService.onProgressChanged = { [weak gameCenterService] in gameCenterService?.noteProgressChanged($0) }
        // Presence, the shared objective, and the floor: real Game Center readers, or (DEBUG,
        // -RUXPLiveDemo) one simulator behind all three so every surface agrees. Views see protocols.
        let presence: any LivePresenceProviding
        let objective: any SessionObjectiveProviding
        let activity: any LiveActivityProviding
        let observed = ObservedLiveActivity()
        #if DEBUG
        let simulator: LiveWorldSimulator? = LiveWorldSimulator.isRequested ? LiveWorldSimulator(events: events) : nil
        #endif
        #if DEBUG
        if let simulator {
            presence = simulator
            objective = simulator
            activity = simulator
        } else {
            presence = GameCenterLivePresence(gameCenter: gameCenterService, season: progressionService.season)
            objective = GameCenterSessionObjective(gameCenter: gameCenterService, events: events)
            activity = observed
        }
        #else
        presence = GameCenterLivePresence(gameCenter: gameCenterService, season: progressionService.season)
        objective = GameCenterSessionObjective(gameCenter: gameCenterService, events: events)
        activity = observed
        #endif
        observed.localAlias = { [weak gameCenterService] in gameCenterService?.alias }
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
        // Discord: moments leave the phone through one publisher, behind a policy. The relay
        // URL comes from the directory; with none configured, moments are logged and kept.
        let relay = RelayCommunityPublisher(urlProvider: { [weak communityService] in communityService?.relayURL })
        let composer = CommunityMomentComposer(events: events, publisher: relay)
        composer.sharingProvider = { [weak communityService] in communityService?.sharing ?? CommunitySharing() }
        composer.aliasProvider = { [weak gameCenterService] in gameCenterService?.alias }
        // Joining counts you in the event's window right away ("84 players joined" is joins, not finishes).
        liveSessionService.onJoined = { [weak gameCenterService, weak observed, weak composer, weak presence] event in
            observed?.noteJoined(event)
            composer?.noteJoined(event, liftingNow: presence?.snapshot.isAvailable == true ? presence?.snapshot.liftingNow : nil)
            guard let board = GameCenterCatalog.eventBoard(for: event) else { return }
            Task { await gameCenterService?.submitPresence(boards: [board]) }
        }
        // The shared objective: a parse credits the workout's volume to its session, the provider
        // submits the player's cumulative total, and the floor gets a "you moved" line.
        liveSessionService.objectiveSubmit = { [weak objective] total, event in
            Task { await objective?.submit(volumeLB: total, for: event) }
        }
        liveSessionService.onContributionRecorded = { [weak observed] _, volume in observed?.noteOwnContribution(volumeLB: volume) }
        processor.onWorkoutParsed = { [weak liveSessionService] in liveSessionService?.recordContribution(session: $0) }
        processor.onPersonalRecords = { [weak composer, weak progressionService] records, session in
            let paid = progressionService?.lastReward.flatMap { $0.workoutID == session.id ? $0.awards : nil } ?? []
            composer?.notePersonalRecords(records, workoutID: session.id,
                                          xp: paid.filter { $0.reason == .personalRecord }.map(\.amount))
        }
        manager.onRewardChanged = { [weak composer] in composer?.noteReward($0) }
        let room = LiveRoomService(gameCenter: gameCenterService)
        room.onReaction = { [weak observed] in observed?.noteReaction($0) }
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
        crewService.onSnapshotChanged = { [weak worldService, weak crewService, weak observed] in
            worldService?.noteCrewUpdated()
            observed?.noteCrew(lifting: crewService?.liftingNow.map(\.displayName) ?? [])
        }
        let presenceHook: (LiveSnapshot) -> Void = { [weak connectivity, weak worldService, weak observed, weak composer, weak presence] snapshot in
            connectivity?.pushPresence(snapshot)
            worldService?.notePresenceUpdated()
            observed?.notePresence(snapshot)
            if snapshot.isAvailable, let presence, let event = events.activeEvent(at: ScheduledEventService.now()), !event.isSeasonWide {
                composer?.noteLifters(presence.participantCount(for: event), for: event)
            }
        }
        let objectiveHook: (SessionObjectiveState) -> Void = { [weak liveSessionService, weak presence, weak observed, weak composer] state in
            liveSessionService?.noteObjectiveUpdated(totalLB: state.totalLB, contributors: state.contributors,
                                                     liftingNow: presence?.snapshot.liftingNow ?? 0)
            observed?.noteObjective(state)
            composer?.noteObjective(state)
        }
        (presence as? GameCenterLivePresence)?.onSnapshotChanged = presenceHook
        (objective as? GameCenterSessionObjective)?.onStateChanged = objectiveHook
        #if DEBUG
        simulator?.onSnapshotChanged = presenceHook
        simulator?.onStateChanged = objectiveHook
        #endif

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
        _liveObjective = State(initialValue: objective)
        _liveActivity = State(initialValue: activity)
        _liveSessions = State(initialValue: liveSessionService)
        _liveRoom = State(initialValue: room)
        _liveOps = State(initialValue: liveOpsService)
        _world = State(initialValue: worldService)
        _crew = State(initialValue: crewService)
        _community = State(initialValue: communityService)
        _communityMoments = State(initialValue: composer)

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
            case "contributed":
                // Reward screen with a parsed log attached (no OpenAI): the contribution row and
                // the ticket can be screenshotted offline.
                manager.startWorkout()
                manager.endWorkout()
                if let id = manager.completedWorkoutID, var session = store.loadSession(id: id),
                   let log = SampleDataGenerator.generate().first(where: { $0.structuredLog != nil })?.structuredLog {
                    session.structuredLog = log
                    store.saveSession(session)
                    Task { try? await Task.sleep(for: .seconds(2)); processor.onWorkoutParsed?(session) }
                }
            default:
                break
            }
        }
        #endif
    }

    @Environment(\.scenePhase) private var scenePhase

    /// DEBUG-only knobs for exercising the reward flow quickly:
    ///   -RUXPSkipMinimum   no 10-minute minimum for completion XP
    ///   -RUXPEventClock friday|sunday|tuesday|saturday|weeknight   pretend it is that day (weeknight = Tuesday 7 PM)
    ///   -RUXPLoadSamples   seed sample workouts on an empty install
    ///   -RUXPTab train|profile   open on that tab (see MainTabView)
    ///   -RUXPSkipHealthKit   bypass HealthKit (see HealthKitService.isDisabledForTesting)
    ///   -RUXPSkipGameCenter  no Game Center sign-in, scores, or live counts (see GameCenterService.isDisabledForTesting)
    ///   -RUXPLiveScene lobby|active|complete|contributed   open the Live Session lobby, a joined workout, its reward screen, or the reward screen with a sample log attached
    ///   -RUXPSeason S00|S01|S02   pretend that season is current (exercise the rollover and recap)
    ///   -RUXPLastSeen 3d|18h|45m   pretend the last visit was that long ago (WHILE YOU WERE GONE)
    ///   -RUXPWorldDemo   with Game Center off, seed friends/rank so every ledger line renders
    ///   -RUXPLiveOps off|<path.json>   no Live Ops rules, or a local calendar instead of the remote one
    ///   -RUXPScreen seasonpass|settings|livehistory|archivedpass   open that sheet at launch (see MainTabView)
    ///   -RUXPCrewDemo [room|last|final|complete|empty]   with Game Center off, seed a crew in that state
    ///   -RUXPLiveDemo [seed]   simulated presence, shared objective, and floor (never the release source)
    ///   -RUXPOpenURL <url>   feed the router at launch (ruxp://join/live, https://ruxp.app/join/<id>)
    ///   -RUXPCommunity off|<path.json>   no community directory, or a local one instead of the remote one



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
        // -RUXPLiveDemo [seed]: one simulator behind presence, the objective, and the floor.
        if let idx = args.firstIndex(of: "-RUXPLiveDemo") {
            LiveWorldSimulator.isRequested = true
            if idx + 1 < args.count, let seed = UInt64(args[idx + 1]) { LiveWorldSimulator.seed = seed }
        } else if UserDefaults.standard.bool(forKey: LiveWorldSimulator.defaultsKey) {
            LiveWorldSimulator.isRequested = true
        }
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
            case "saturday": comps.weekday = 7; comps.hour = 19
            case "weeknight": comps.weekday = 3; comps.hour = 19
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
                .environment(\.liveObjective, liveObjective)
                .environment(\.liveActivity, liveActivity)
                .environment(\.liveEvents, eventService)
                .environment(liveSessions)
                .environment(\.liveRoom, liveRoom)
                .environment(liveOps)
                .environment(world)
                .environment(crew)
                .environment(community)
                .environment(communityMoments)
                .environment(router)
                // Custom-scheme URLs and Universal Links both arrive here; the root is always in
                // the hierarchy, HomeView is not (lazy tab, covers).
                .onOpenURL { router.open($0) }
                .preferredColorScheme(.dark)
                .task {
                    gameCenter.start()
                    livePresence.start()
                    liveObjective.start()
                    liveActivity.start()
                    liveOps.refresh()
                    community.refresh()
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
                        liveObjective.start()
                        liveActivity.start()
                        liveOps.refresh()
                        community.refresh()
                        crew.start()
                        world.noteForeground()
                    } else if scenePhase == .background {
                        // Snapshot first, while the last live count is still in hand.
                        world.noteBackground()
                        livePresence.stop()
                        liveObjective.stop()
                        liveActivity.stop()
                        crew.stop()


                        gameCenter.flushNow()
                        // Real-time rooms are foreground-only; the peer connection dies when suspended.
                        liveRoom.leave()
                    }
                }
        }
    }
}
