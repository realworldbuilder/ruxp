import AVFoundation
import SwiftUI

@MainActor
class ExerciseSuggestionEngine: ObservableObject {
    @Published var suggestions: [String] = []
    @Published var suggestionReason: String = ""

    func update(currentTranscripts: [String], workoutStore: WorkoutStore) {
        let currentExercises = extractExercises(from: currentTranscripts)

        // Look at past workouts for co-occurrence patterns
        let historicalPairs = buildExercisePairings(from: workoutStore)

        var scores: [String: Int] = [:]
        for exercise in currentExercises {
            if let paired = historicalPairs[exercise.lowercased()] {
                for (pairedExercise, count) in paired {
                    if !currentExercises.map({ $0.lowercased() }).contains(pairedExercise.lowercased()) {
                        scores[pairedExercise, default: 0] += count
                    }
                }
            }
        }

        let historySuggestions = scores.sorted { $0.value > $1.value }
            .prefix(4)
            .map(\.key)

        if !historySuggestions.isEmpty {
            suggestions = historySuggestions
            suggestionReason = "Based on your history"
        } else {
            suggestions = getDefaultSuggestions(currentExercises: currentExercises)
            suggestionReason = "Suggested for your split"
        }
    }

    private func extractExercises(from transcripts: [String]) -> [String] {
        let knownExercises = [
            "bench press", "incline bench", "incline dumbbell press", "dumbbell press",
            "squat", "front squat", "back squat", "goblet squat",
            "deadlift", "romanian deadlift", "sumo deadlift",
            "overhead press", "military press", "shoulder press",
            "barbell row", "bent over row", "cable row", "dumbbell row",
            "pull-ups", "pull ups", "chin-ups", "chin ups", "lat pulldown",
            "leg press", "leg extension", "leg curl", "hamstring curl",
            "bicep curl", "hammer curl", "preacher curl",
            "tricep pushdown", "skull crushers", "tricep extension",
            "lateral raise", "face pulls", "face pull",
            "cable fly", "dumbbell fly", "chest fly",
            "calf raise", "hip thrust",
            "lunges", "walking lunges", "bulgarian split squat"
        ]

        let combined = transcripts.joined(separator: " ").lowercased()
        return knownExercises.filter { combined.contains($0) }
            .map { $0.split(separator: " ").map { $0.capitalized }.joined(separator: " ") }
    }

    private func buildExercisePairings(from store: WorkoutStore) -> [String: [String: Int]] {
        var pairings: [String: [String: Int]] = [:]

        for entry in store.index.prefix(20) {
            let exercises = entry.exerciseNames
            for exercise in exercises {
                for other in exercises where other != exercise {
                    pairings[exercise.lowercased(), default: [:]][other, default: 0] += 1
                }
            }
        }

        return pairings
    }

    private func getDefaultSuggestions(currentExercises: [String]) -> [String] {
        let soul = TrainerSoul.load()
        let current = currentExercises.joined(separator: " ").lowercased()

        func filterDone(_ list: [String]) -> [String] {
            let done = Set(currentExercises.map { $0.lowercased() })
            return list.filter { !done.contains($0.lowercased()) }
        }

        switch soul.trainingSplit {
        case .pushPullLegs:
            let push = ["Bench Press", "Overhead Press", "Incline Dumbbell Press", "Lateral Raise", "Tricep Pushdown", "Cable Fly"]
            let pull = ["Barbell Row", "Pull-Ups", "Face Pulls", "Hammer Curl", "Lat Pulldown", "Cable Row"]
            let legs = ["Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Calf Raise", "Bulgarian Split Squat"]

            if current.contains("bench") || current.contains("fly") || current.contains("tricep") || current.contains("shoulder") || current.contains("lateral") {
                return Array(filterDone(push).prefix(4))
            } else if current.contains("row") || current.contains("pull") || current.contains("curl") || current.contains("lat") || current.contains("face") {
                return Array(filterDone(pull).prefix(4))
            } else if current.contains("squat") || current.contains("deadlift") || current.contains("leg") || current.contains("calf") || current.contains("lunge") {
                return Array(filterDone(legs).prefix(4))
            }
            // No moments yet — show all three categories as starting points
            return ["Bench Press", "Squat", "Barbell Row", "Overhead Press"]

        case .upperLower:
            let upper = ["Bench Press", "Overhead Press", "Barbell Row", "Pull-Ups", "Lateral Raise", "Bicep Curl"]
            let lower = ["Squat", "Romanian Deadlift", "Leg Press", "Hip Thrust", "Leg Curl", "Calf Raise"]
            if current.contains("squat") || current.contains("deadlift") || current.contains("leg") || current.contains("hip") || current.contains("lunge") {
                return Array(filterDone(lower).prefix(4))
            } else if !current.isEmpty {
                return Array(filterDone(upper).prefix(4))
            }
            return ["Bench Press", "Squat", "Overhead Press", "Barbell Row"]

        case .fullBody:
            return Array(filterDone(["Squat", "Bench Press", "Barbell Row", "Overhead Press", "Romanian Deadlift", "Pull-Ups"]).prefix(4))

        case .broSplit:
            if current.contains("bench") || current.contains("fly") || current.contains("chest") {
                return Array(filterDone(["Incline Dumbbell Press", "Cable Fly", "Dumbbell Press", "Chest Fly"]).prefix(4))
            } else if current.contains("row") || current.contains("lat") || current.contains("back") {
                return Array(filterDone(["Barbell Row", "Lat Pulldown", "Cable Row", "Pull-Ups"]).prefix(4))
            }
            return ["Bench Press", "Squat", "Barbell Row", "Overhead Press"]

        case .arnoldSplit:
            if current.contains("bench") || current.contains("row") || current.contains("back") || current.contains("chest") {
                return Array(filterDone(["Bench Press", "Barbell Row", "Incline Dumbbell Press", "Cable Row", "Cable Fly", "Lat Pulldown"]).prefix(4))
            } else if current.contains("curl") || current.contains("tricep") || current.contains("lateral") || current.contains("shoulder") {
                return Array(filterDone(["Overhead Press", "Lateral Raise", "Bicep Curl", "Tricep Pushdown", "Hammer Curl"]).prefix(4))
            }
            return ["Bench Press", "Barbell Row", "Overhead Press", "Squat"]

        case .phat, .custom:
            return Array(filterDone(["Bench Press", "Squat", "Deadlift", "Overhead Press", "Barbell Row", "Pull-Ups"]).prefix(4))
        }
    }
}

// MARK: - Suggestions View

struct ExerciseSuggestionsView: View {
    let suggestions: [String]
    var reason: String = "Suggested for your split"

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Up Next")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                    
                    Spacer()
                    
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { exercise in
                            Text(exercise)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.accentSubtle, in: Capsule())
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .themeCard()
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Active Workout Tab

struct ActiveWorkoutTab: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @StateObject private var recorder = PhoneAudioRecorderService()
    @StateObject private var suggestionEngine = ExerciseSuggestionEngine()
    @State private var showMicPermissionDenied = false
    @State private var showEndConfirmation = false
    @State private var showDiscardStep1 = false
    @State private var discardConfirmText = ""
    @State private var showDiscardStep2 = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                timerHeader
                momentsFeed
                if workoutManager.activeSession?.moments.isEmpty == false {
                    ExerciseSuggestionsView(
                        suggestions: suggestionEngine.suggestions,
                        reason: suggestionEngine.suggestionReason
                    )
                }
                Spacer()
                bottomControls
            }
            .background(Theme.background)
            .navigationTitle("Active Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDiscardStep1 = true } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEndConfirmation = true } label: {
                        Text("End")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(.red, in: Capsule())
                    }
                }
            }
            .alert("Microphone Access Required", isPresented: $showMicPermissionDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable microphone access to record moments.")
            }
            .alert("End Workout?", isPresented: $showEndConfirmation) {
                Button("End", role: .destructive) { workoutManager.endWorkout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will end the current workout and begin AI processing.")
            }
            // Discard Step 1: "Are you sure?"
            .alert("Discard Workout?", isPresented: $showDiscardStep1) {
                Button("Yes, Discard", role: .destructive) {
                    discardConfirmText = ""
                    showDiscardStep2 = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will throw away all recorded moments. This cannot be undone.")
            }
            // Discard Step 2: Type "DISCARD" to confirm
            .alert("Type DISCARD to confirm", isPresented: $showDiscardStep2) {
                TextField("DISCARD", text: $discardConfirmText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                Button("Confirm", role: .destructive) {
                    if discardConfirmText.uppercased() == "DISCARD" {
                        workoutManager.discardWorkout()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Type DISCARD to permanently delete this workout.")
            }
            .onChange(of: workoutManager.activeSession?.moments.count) { _, _ in
                updateSuggestions()
            }
            .onAppear {
                updateSuggestions()
            }
        }
    }

    private func updateSuggestions() {
        let transcripts = workoutManager.activeSession?.moments.map(\.transcript) ?? []
        suggestionEngine.update(currentTranscripts: transcripts, workoutStore: workoutManager.workoutStore)
    }

    private var timerHeader: some View {
        VStack(spacing: 8) {
            Text(formattedElapsed)
                .font(.system(size: 48, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                Label("\(workoutManager.activeSession?.moments.count ?? 0) \((workoutManager.activeSession?.moments.count ?? 0) == 1 ? "moment" : "moments")", systemImage: "waveform")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)

                if workoutManager.isProcessingMoment {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Transcribing...").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
    }

    private var momentsFeed: some View {
        Group {
            if let session = workoutManager.activeSession, !session.moments.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(session.moments.reversed()) { moment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(moment.transcript).font(.body)
                                HStack {
                                    Text(moment.timestamp, style: .time).font(.caption).foregroundStyle(Theme.textSecondary)
                                    if moment.source == .watch {
                                        Image(systemName: "applewatch").font(.caption2).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Spacer()
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.textTertiary)
                    
                    Text("Tap the mic to start logging")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                    
                    if !suggestionEngine.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Start with")
                                .font(.caption)
                                .foregroundColor(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(suggestionEngine.suggestions, id: \.self) { exercise in
                                        Text(exercise)
                                            .font(.caption)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Theme.accentSubtle, in: Capsule())
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                    
                    Spacer()
                }
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            if recorder.isRecording { recordingOverlay }

            Button {
                if recorder.isRecording { stopAndAddMoment() }
                else { requestMicAndRecord() }
            } label: {
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(recorder.isRecording ? Color.red : Theme.accent, in: Circle())
                    .shadow(color: (recorder.isRecording ? Color.red : Theme.accent).opacity(0.4), radius: 8, y: 2)
            }
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Record moment")
            .padding(.bottom, 16)
        }
        .padding()
        .background(Theme.background)
    }

    private var recordingOverlay: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 10, height: 10)
            Text(formattedRecordingDuration).font(.body.monospacedDigit())
        }
    }

    private var formattedElapsed: String {
        guard let session = workoutManager.activeSession else { return "0:00" }
        let total = Int(Date().timeIntervalSince(session.startedAt))
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        return hrs > 0 ? String(format: "%d:%02d:%02d", hrs, mins, secs) : String(format: "%d:%02d", mins, secs)
    }

    private var formattedRecordingDuration: String {
        let minutes = Int(recorder.recordingDuration) / 60
        let seconds = Int(recorder.recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func requestMicAndRecord() {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    if granted { recorder.startRecording() }
                    else { showMicPermissionDenied = true }
                }
            }
        case .denied: showMicPermissionDenied = true
        case .granted: recorder.startRecording()
        @unknown default: break
        }
    }

    private func stopAndAddMoment() {
        guard let url = recorder.stopRecording() else { return }
        Task { await workoutManager.addMoment(audioURL: url, source: .phone) }
    }
}
