import AVFoundation
import SwiftUI

@MainActor
class ExerciseSuggestionEngine: ObservableObject {
    @Published var suggestions: [String] = []
    
    func update(currentTranscripts: [String], workoutStore: WorkoutStore) {
        // 1. Extract exercise names mentioned in current transcripts
        let currentExercises = extractExercises(from: currentTranscripts)
        
        // 2. Look at past workouts that contained similar exercises
        let historicalPairs = buildExercisePairings(from: workoutStore)
        
        // 3. Find exercises that commonly follow the current ones
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
        
        // 4. Sort by frequency and take top 4
        suggestions = scores.sorted { $0.value > $1.value }
            .prefix(4)
            .map(\.key)
        
        // 5. If no history-based suggestions, use split-based defaults
        if suggestions.isEmpty {
            suggestions = getDefaultSuggestions(currentExercises: currentExercises)
        }
    }
    
    private func extractExercises(from transcripts: [String]) -> [String] {
        // Simple keyword extraction — look for common exercise names in transcripts
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
        // Build a map: exercise → [co-occurring exercise: frequency]
        var pairings: [String: [String: Int]] = [:]
        
        for entry in store.index.prefix(20) { // Last 20 workouts
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
        // Based on split, suggest common exercises
        switch soul.trainingSplit {
        case .pushPullLegs:
            let pushExercises = ["Bench Press", "Overhead Press", "Incline Dumbbell Press", "Lateral Raise", "Tricep Pushdown", "Cable Fly"]
            let pullExercises = ["Barbell Row", "Pull-Ups", "Face Pulls", "Hammer Curl", "Lat Pulldown", "Cable Row"]
            let legExercises = ["Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Calf Raise", "Bulgarian Split Squat"]
            
            // Guess which day based on current exercises
            let current = currentExercises.joined(separator: " ").lowercased()
            if current.contains("bench") || current.contains("press") || current.contains("fly") || current.contains("tricep") {
                return pushExercises.filter { !currentExercises.map { $0.lowercased() }.contains($0.lowercased()) }.prefix(4).map { $0 }
            } else if current.contains("row") || current.contains("pull") || current.contains("curl") || current.contains("lat") {
                return pullExercises.filter { !currentExercises.map { $0.lowercased() }.contains($0.lowercased()) }.prefix(4).map { $0 }
            } else if current.contains("squat") || current.contains("deadlift") || current.contains("leg") || current.contains("calf") {
                return legExercises.filter { !currentExercises.map { $0.lowercased() }.contains($0.lowercased()) }.prefix(4).map { $0 }
            }
            return ["Bench Press", "Squat", "Barbell Row", "Overhead Press"]
        case .upperLower:
            let upper = ["Bench Press", "Overhead Press", "Barbell Row", "Pull-Ups", "Lateral Raise", "Bicep Curl"]
            let lower = ["Squat", "Romanian Deadlift", "Leg Press", "Hip Thrust", "Leg Curl", "Calf Raise"]
            let current = currentExercises.joined(separator: " ").lowercased()
            if current.contains("squat") || current.contains("deadlift") || current.contains("leg") || current.contains("hip") {
                return lower.filter { !currentExercises.map { $0.lowercased() }.contains($0.lowercased()) }.prefix(4).map { $0 }
            }
            return upper.filter { !currentExercises.map { $0.lowercased() }.contains($0.lowercased()) }.prefix(4).map { $0 }
        default:
            return ["Bench Press", "Squat", "Deadlift", "Overhead Press"]
        }
    }
}

struct ExerciseSuggestionsView: View {
    let suggestions: [String]
    
    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Up Next", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary)
                
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
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct ActiveWorkoutTab: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @StateObject private var recorder = PhoneAudioRecorderService()
    @StateObject private var suggestionEngine = ExerciseSuggestionEngine()
    @State private var showMicPermissionDenied = false
    @State private var showEndConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                timerHeader
                ExerciseSuggestionsView(suggestions: suggestionEngine.suggestions)
                momentsFeed
                Spacer()
                bottomControls
            }
            .background(Theme.background)
            .navigationTitle("Active Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
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
            .onChange(of: workoutManager.activeSession?.moments.count) { _, _ in
                let transcripts = workoutManager.activeSession?.moments.map(\.transcript) ?? []
                suggestionEngine.update(currentTranscripts: transcripts, workoutStore: workoutManager.workoutStore)
            }
            .onAppear {
                let transcripts = workoutManager.activeSession?.moments.map(\.transcript) ?? []
                suggestionEngine.update(currentTranscripts: transcripts, workoutStore: workoutManager.workoutStore)
            }
        }
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
                ContentUnavailableView {
                    Label("No Moments Yet", systemImage: "mic.slash")
                } description: {
                    Text("Tap the microphone button to record a moment.")
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
