import SwiftUI
import Security

struct SettingsView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(InsightsStore.self) private var insightsStore

    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue
    @State private var showDeleteConfirmation = false
    @State private var showExportSheet = false
    @State private var exportData: Data?
    // Trainer Soul
    @State private var soul = TrainerSoul.load()
    @State private var showSoulEditor = false

    // TODO: ⚠️ REMOVE BEFORE APP STORE SUBMISSION ⚠️
    @State private var devTapCount = 0
    @State private var showLoadSampleData = false
    @State private var sampleDataLoaded = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
        Form {
            // MARK: - Trainer Soul
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(soul.fitnessGoal.rawValue)
                            .font(.subheadline.weight(.semibold))
                        Text("\(soul.experienceLevel.rawValue) · \(soul.trainingStyle.rawValue) · \(soul.coachingTone.rawValue)")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { showSoulEditor = true }

                if !soul.customPrompt.isEmpty {
                    Text(soul.customPrompt)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            } header: {
                Text("Trainer Soul")
            } footer: {
                Text("Shapes how your AI trainer talks, what it focuses on, and how it coaches you.")
            }

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

            // MARK: - About
            Section("About") {
                LabeledContent("AI", value: "Built-in")
                LabeledContent("Transcription", value: "Voice Recognition")

                // TODO: ⚠️ REMOVE BEFORE APP STORE SUBMISSION ⚠️
                // Tap version 5 times to reveal sample data loader
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(appVersion) (\(buildNumber))")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    devTapCount += 1
                    if devTapCount >= 5 {
                        showLoadSampleData = true
                        devTapCount = 0
                    }
                }
            }

            // TODO: ⚠️ REMOVE BEFORE APP STORE SUBMISSION ⚠️
            if showLoadSampleData {
                Section {
                    Button {
                        let samples = SampleDataGenerator.generate()
                        for session in samples {
                            workoutManager.workoutStore.saveSession(session)
                        }
                        workoutManager.workoutStore.loadIndex()
                        NotificationCenter.default.post(name: .workoutsDidChange, object: nil)
                        sampleDataLoaded = true
                    } label: {
                        Label("Load Sample Workouts (7)", systemImage: "tray.and.arrow.down")
                    }

                    if sampleDataLoaded {
                        Text("✅ 7 sample workouts loaded!")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("🛠 Developer")
                } footer: {
                    Text("Loads 7 realistic workouts spanning 9 days: Chest, Pull, Leg, Push, Back & Biceps, Full Body, Shoulders.")
                }
            }
        }
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
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all workouts, transcripts, and AI-generated content from this device. This cannot be undone.")
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

    // MARK: - Export Helpers

    private func writeExportFile(_ data: Data) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("momentary_workouts_export.json")
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
