import SwiftUI

struct SettingsView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WorkoutProcessor.self) private var workoutProcessor
    @Environment(InsightsStore.self) private var insightsStore
    @Environment(ProgressionService.self) private var progression
    @Environment(\.liveEvents) private var events
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(\.livePresence) private var presence
    @Environment(LiveSessionService.self) private var liveSessions
    @Environment(\.liveRoom) private var liveRoom
    @Environment(LiveOpsService.self) private var liveOps
    @Environment(WorldSnapshotService.self) private var world

    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue
    @AppStorage(GameCenterService.syncEnabledKey) private var gameCenterSync = true
    @State private var showDeleteConfirmation = false
    @State private var showExportSheet = false
    @State private var exportData: Data?
    // Trainer Soul
    @State private var soul = TrainerSoul.load()
    @State private var showSoulEditor = false

    // OpenAI API key
    @State private var apiKeyInput = ""
    @State private var storedKeyMask: String?
    @State private var keyTestResult: KeyTestResult = .idle

    private var trimmedKeyInput: String {
        apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    #if DEBUG
    @State private var devTapCount = 0
    @State private var showLoadSampleData = true
    @State private var sampleDataLoaded = false
    @State private var eventClock: EventClock = .now
    @State private var skipMinimumDuration = ProgressionRules.minimumWorkoutDuration == 0
    @State private var seasonOverride = UserDefaults.standard.string(forKey: "ruxp.debugSeasonOverride") ?? ""

    private enum EventClock: String, CaseIterable, Identifiable {
        case now = "Now", fridayNight = "Friday 7 PM", sunday = "Sunday noon", tuesday = "Tuesday 10 AM"
        var id: String { rawValue }
        var date: Date? {
            let cal = Calendar.current
            let now = Date()
            func next(weekday: Int, hour: Int) -> Date? {
                var comps = DateComponents()
                comps.weekday = weekday
                comps.hour = hour
                comps.minute = 0
                return cal.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
            }
            switch self {
            case .now: return nil
            case .fridayNight: return next(weekday: 6, hour: 19)
            case .sunday: return next(weekday: 1, hour: 12)
            case .tuesday: return next(weekday: 3, hour: 10)
            }
        }
    }
    #endif

    private enum KeyTestResult: Equatable {
        case idle
        case testing
        case valid
        case invalid(String)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
        Form {
            // MARK: - Preferences
            Section("Preferences") {
                Picker("Weight Unit", selection: $weightUnit) {
                    Text("lbs").tag(WeightUnit.lbs.rawValue)
                    Text("kg").tag(WeightUnit.kg.rawValue)
                }
                .pickerStyle(.segmented)
            }

            // MARK: - Game Center
            Section {
                Toggle("Sync to Game Center", isOn: $gameCenterSync)
                    .onChange(of: gameCenterSync) { gameCenter.setSyncEnabled(gameCenterSync) }
                    .disabled(gameCenter.authState == .disabled)
                LabeledContent("Status", value: gameCenter.statusLine)
            } header: {
                Text("Game Center")
            } footer: {
                Text("Leaderboards, achievements, and the live lifting counts run on Game Center. Only your XP totals, week streak, milestones, and an \"I'm training\" ping leave the device.")
            }

            // MARK: - Data
            Section {
                Button {
                    exportData = workoutManager.workoutStore.exportAllSessionsAsJSON()
                    if exportData != nil {
                        showExportSheet = true
                    }
                } label: {
                    Label("Export All Workouts", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete All Data", systemImage: "trash")
                }
            } header: {
                Text("Data")
            } footer: {
                Text("\(workoutManager.workoutStore.index.count) workout\(workoutManager.workoutStore.index.count == 1 ? "" : "s") stored on device")
            }

            // MARK: - OpenAI API Key
            Section {
                if let mask = storedKeyMask {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(Theme.accent)
                        Text("Key configured (\(mask))")
                            .font(Theme.Fonts.ui(.subheadline))
                    }
                } else if APIKeyProvider.hasBundledKey {
                    HStack {
                        Image(systemName: "gift.fill")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI on the house")
                                .font(Theme.Fonts.ui(.subheadline))
                            Text("\(progression.season.code) · \(progression.season.name)")
                                .font(Theme.Fonts.ui(.caption))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "key.slash")
                            .foregroundStyle(Theme.error)
                        Text("No key set — AI features disabled")
                            .font(Theme.Fonts.ui(.subheadline))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                SecureField(APIKeyProvider.hasBundledKey ? "Use your own key instead (sk-...)" : "sk-...", text: $apiKeyInput)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("Save Key") {
                    saveKey()
                }
                .disabled(trimmedKeyInput.isEmpty)

                Button("Test Key") {
                    testKey()
                }
                .disabled(keyTestResult == .testing || (trimmedKeyInput.isEmpty && !APIKeyProvider.hasKey))

                switch keyTestResult {
                case .idle:
                    EmptyView()
                case .testing:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking key…").font(Theme.Fonts.ui(.caption)).foregroundStyle(Theme.textSecondary)
                    }
                case .valid:
                    Label("Key works", systemImage: "checkmark.circle.fill")
                        .font(Theme.Fonts.ui(.caption))
                        .foregroundStyle(Theme.accent)
                case .invalid(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Fonts.ui(.caption))
                        .foregroundStyle(Theme.error)
                }

                if storedKeyMask != nil {
                    Button(APIKeyProvider.hasBundledKey ? "Remove My Key" : "Remove Key", role: .destructive) {
                        APIKeyProvider.delete()
                        storedKeyMask = nil
                        keyTestResult = .idle
                    }
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text(apiKeyFooter)
            }

            // MARK: - About
            Section("About") {
                LabeledContent("Workout parsing", value: "OpenAI GPT-4o")
                LabeledContent("Insights & coach", value: "OpenAI GPT-4o mini")
                LabeledContent("Transcription", value: "OpenAI Whisper (cloud)")
                LabeledContent("AI key", value: keySourceLabel)
                LabeledContent("Live counts", value: "Game Center players")

                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(appVersion) (\(buildNumber))")
                        .foregroundStyle(.secondary)
                }
                #if DEBUG
                // Tap version 5 times to reveal sample data loader
                .contentShape(Rectangle())
                .onTapGesture {
                    devTapCount += 1
                    if devTapCount >= 5 {
                        showLoadSampleData = true
                        devTapCount = 0
                    }
                }
                #endif
            }

            #if DEBUG
            if showLoadSampleData {
                Section {
                    Button {
                        let samples = SampleDataGenerator.generate()
                        for session in samples {
                            workoutManager.workoutStore.saveSession(session)
                        }
                        workoutManager.workoutStore.loadIndex()
                        insightsStore.rebuild(from: workoutManager.workoutStore)
                        let sessions = workoutManager.workoutStore.index.compactMap { workoutManager.workoutStore.loadSession(id: $0.id) }
                        progression.rebuild(from: sessions, events: events)
                        NotificationCenter.default.post(name: .workoutsDidChange, object: nil)
                        sampleDataLoaded = true
                    } label: {
                        Label("Load Sample Workouts (7)", systemImage: "tray.and.arrow.down")
                    }

                    if sampleDataLoaded {
                        Text("7 sample workouts loaded. Profile and level rebuilt.")
                            .font(Theme.Fonts.ui(.caption))
                            .foregroundStyle(Theme.accent)
                    }

                    Picker("Event clock", selection: $eventClock) {
                        ForEach(EventClock.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .onChange(of: eventClock) { ScheduledEventService.clockOverride = eventClock.date }

                    Toggle("Skip 10-minute minimum for XP", isOn: $skipMinimumDuration)
                        .onChange(of: skipMinimumDuration) {
                            ProgressionRules.minimumWorkoutDuration = skipMinimumDuration ? 0 : 10 * 60
                        }

                    LabeledContent("Season", value: progression.season.id)
                    Picker("Season override", selection: $seasonOverride) {
                        Text("Now").tag("")
                        ForEach(SeasonCatalog.all) { Text($0.id).tag($0.id) }
                    }
                    .onChange(of: seasonOverride) {
                        UserDefaults.standard.set(seasonOverride, forKey: "ruxp.debugSeasonOverride")
                    }
                    if seasonOverride != progression.season.id, !seasonOverride.isEmpty {
                        Text("Relaunch to apply. Rolling forward closes the current season into a record and shows the recap; rolling back does not restore its XP.")
                            .font(Theme.Fonts.ui(.caption))
                            .foregroundStyle(Theme.warning)
                    }
                    if let record = progression.progress.seasonHistory?.last {
                        LabeledContent("Last closed season", value: "\(record.seasonID) · LVL \(record.finalLevel)")
                    }


                    LabeledContent("Game Center", value: gameCenter.statusLine)
                    LabeledContent("Last submission", value: gameCenter.lastSubmissionResult)
                    if let live = presence as? GameCenterLivePresence {
                        LabeledContent("Presence", value: live.snapshot.updatedAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "never")
                        ForEach(live.counts.keys.sorted(), id: \.self) { id in
                            LabeledContent(id, value: "\(live.counts[id] ?? 0)")
                        }
                        if let error = live.lastError {
                            Text(error).font(.caption).foregroundStyle(Theme.error)
                        }
                        Button("Refresh presence") { live.refreshNow() }
                    }
                    Button("Flush Game Center now") { gameCenter.flushNow() }
                    if let liveRoom {
                        LabeledContent("Training room", value: roomStateLabel(liveRoom.state))
                        LabeledContent("Room peers", value: "\(liveRoom.members.count) now · \(liveRoom.peakPeerCount) peak")
                    }
                    LabeledContent("Live sessions joined", value: "\(liveSessions.participations.count)")

                    LabeledContent("Live ops", value: liveOps.sourceLabel)
                    LabeledContent("Rules active", value: "\(liveOps.activeModifiers().count) of \(liveOps.calendar.modifiers.count)")
                    if let error = liveOps.lastError {
                        Text(error).font(.caption).foregroundStyle(Theme.error)
                    }
                    Button("Refresh live ops") { liveOps.refresh(force: true) }
                    LabeledContent("Bundled round trip", value: LiveOpsService.bundledRoundTripReport())

                    LabeledContent("World snapshot", value: world.debugDescription)
                    Button("Reset return ledger") { world.debugResetSnapshot() }
                } header: {
                    Text("Developer")

                } footer: {
                    Text("Debug builds only. The event clock pretends it is a different time so live events can be tested.")
                }
            }
            #endif
        }
        .task { storedKeyMask = APIKeyProvider.maskedKey }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Settings")
        .toolbarBackground(Theme.background, for: .navigationBar)
        .confirmationDialog(
            "Delete All Workout Data?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                workoutManager.workoutStore.deleteAllData()
                insightsStore.resetAll()
                progression.resetAll()
                liveSessions.resetAll()
                gameCenter.clearLocalCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all workouts, transcripts, XP, and level progress from this device. Scores already posted to Game Center stay on its leaderboards. This cannot be undone.")
        }
        .sheet(isPresented: $showSoulEditor) {
            TrainerSoulEditor(soul: $soul)
        }
        .sheet(isPresented: $showExportSheet) {
            if let data = exportData {
                let url = writeExportFile(data)
                ShareSheetView(activityItems: [url])
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - API Key Helpers

    private var keySourceLabel: String {
        switch APIKeyProvider.keySource {
        case .custom: return "Your key"
        case .bundled: return "On the house"
        case .none: return "None"
        }
    }

    private var apiKeyFooter: String {
        let season = progression.season
        switch APIKeyProvider.keySource {
        case .bundled:
            return "Voice notes (audio) and your workout text are sent to OpenAI for transcription, parsing, and insights. During \(season.code) · \(season.name) the key is on us. Paste your own key to use it instead; it's stored in the iOS Keychain and sent only to api.openai.com."
        case .custom:
            return "Transcription and AI coaching use your own OpenAI API key. It's stored in the iOS Keychain. Audio and workout notes go only to api.openai.com."
        case .none:
            return "AI features are off. Add an OpenAI API key to enable transcription and parsing. Audio and workout notes are sent only to api.openai.com. Get a key at platform.openai.com/api-keys."
        }
    }

    private func saveKey() {
        guard APIKeyProvider.save(apiKeyInput) else { return }
        apiKeyInput = ""
        storedKeyMask = APIKeyProvider.maskedKey
        keyTestResult = .idle
        // A new key may unblock workouts stuck in the offline queue
        Task { await workoutProcessor.processPendingQueue() }
    }

    private func testKey() {
        let keyToTest = trimmedKeyInput.isEmpty ? APIKeyProvider.resolvedKey : trimmedKeyInput
        keyTestResult = .testing
        Task {
            switch await AIService.validateKey(keyToTest) {
            case .success:
                keyTestResult = .valid
            case .failure(let error):
                keyTestResult = .invalid(error.localizedDescription)
            }
        }
    }

    // MARK: - Live (Developer)

    private func roomStateLabel(_ state: LiveRoomState) -> String {
        switch state {
        case .idle: return "idle"
        case .unavailable(let why): return "unavailable: \(why)"
        case .searching: return "searching"
        case .connecting: return "connecting"
        case .live: return "live"
        case .failed(let why): return "failed: \(why)"
        }
    }

    // MARK: - Export Helpers

    private func writeExportFile(_ data: Data) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("ruxp_workouts_export.json")
        try? data.write(to: fileURL)
        return fileURL
    }
}

// MARK: - Share Sheet

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
