import SwiftUI

struct SettingsView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WorkoutProcessor.self) private var workoutProcessor
    @Environment(InsightsStore.self) private var insightsStore
    @Environment(ProgressionService.self) private var progression
    @Environment(\.liveEvents) private var events

    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue
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
                            .font(.subheadline)
                    }
                } else {
                    HStack {
                        Image(systemName: "key.slash")
                            .foregroundStyle(Theme.error)
                        Text("No key set — AI features disabled")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                SecureField("sk-...", text: $apiKeyInput)
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
                .disabled(keyTestResult == .testing || (trimmedKeyInput.isEmpty && storedKeyMask == nil))

                switch keyTestResult {
                case .idle:
                    EmptyView()
                case .testing:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking key…").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                case .valid:
                    Label("Key works", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                case .invalid(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.error)
                }

                if storedKeyMask != nil {
                    Button("Remove Key", role: .destructive) {
                        APIKeyProvider.delete()
                        storedKeyMask = nil
                        keyTestResult = .idle
                    }
                }
            } header: {
                Text("OpenAI API Key")
            } footer: {
                Text("Transcription and AI coaching use your own OpenAI API key. It's stored in the iOS Keychain and sent only to api.openai.com. Get one at platform.openai.com/api-keys.")
            }

            // MARK: - About
            Section("About") {
                LabeledContent("Workout parsing", value: "OpenAI GPT-4o")
                LabeledContent("Transcription", value: "OpenAI Whisper (cloud)")
                LabeledContent("Live counts", value: "Simulated in this build")

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
                            .font(.caption)
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
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all workouts, transcripts, XP, and level progress from this device. This cannot be undone.")
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
