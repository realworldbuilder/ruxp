import SwiftUI
import Security

struct SettingsView: View {
    @Environment(WorkoutManager.self) private var workoutManager

    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue
    @State private var showDeleteConfirmation = false
    @State private var showExportSheet = false
    @State private var exportData: Data?
    @State private var customAPIKey: String = ""
    @State private var showAPIKeyField = false
    @State private var apiKeySaved = false

    // Trainer Soul
    @State private var soul = TrainerSoul.load()
    @State private var showSoulEditor = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var hasCustomAPIKey: Bool {
        loadKeychainKey() != nil
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

            // MARK: - AI / API Key
            Section {
                HStack {
                    Image(systemName: hasCustomAPIKey ? "key.fill" : "checkmark.circle.fill")
                        .foregroundStyle(hasCustomAPIKey ? .orange : Theme.accent)
                    Text(hasCustomAPIKey ? "Using Custom API Key" : "Using Built-in API Key")
                }

                if showAPIKeyField {
                    SecureField("sk-...", text: $customAPIKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { saveCustomAPIKey() }

                    HStack {
                        Button("Save Key") { saveCustomAPIKey() }
                            .disabled(customAPIKey.isEmpty)
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)

                        if hasCustomAPIKey {
                            Button("Remove Key", role: .destructive) {
                                deleteKeychainKey()
                                customAPIKey = ""
                                showAPIKeyField = false
                            }
                        }

                        Spacer()

                        Button("Cancel") {
                            customAPIKey = ""
                            showAPIKeyField = false
                        }
                    }
                    .font(.subheadline)
                } else {
                    Button {
                        showAPIKeyField = true
                    } label: {
                        Label("Set Custom OpenAI Key", systemImage: "key")
                    }
                }

                if apiKeySaved {
                    Text("API key saved to Keychain")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            } header: {
                Text("OpenAI")
            } footer: {
                Text("Custom keys are stored securely in the iOS Keychain.")
            }

            // MARK: - About
            Section("About") {
                LabeledContent("Version", value: "\(appVersion) (\(buildNumber))")
                LabeledContent("AI Model", value: "GPT-4o")
                LabeledContent("Transcription", value: "OpenAI Whisper API")
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

    // MARK: - Keychain Helpers

    private static let keychainService = "com.williamhussey.mind2muscle.openai"
    private static let keychainAccount = "custom_api_key"

    private func saveCustomAPIKey() {
        guard !customAPIKey.isEmpty else { return }
        let data = Data(customAPIKey.utf8)

        // Delete existing first
        deleteKeychainKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
        customAPIKey = ""
        showAPIKeyField = false
        apiKeySaved = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            apiKeySaved = false
        }
    }

    private func loadKeychainKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
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
