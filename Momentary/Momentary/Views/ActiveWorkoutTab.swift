import AVFoundation
import SwiftUI

@MainActor
class ExerciseSuggestionEngine: ObservableObject {
    @Published var suggestions: [String] = []
    @Published var suggestionReason: String = ""

    func update(currentTranscripts: [String], workoutStore: WorkoutStore, elapsedTime: TimeInterval = 0) {
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
            .prefix(8)
            .map(\.key)

        if !historySuggestions.isEmpty {
            suggestions = historySuggestions
            suggestionReason = "Based on your history"
        } else {
            suggestions = getDefaultSuggestions(currentExercises: currentExercises, elapsedTime: elapsedTime)
            let elapsedMinutes = elapsedTime / 60
            if elapsedMinutes < 5 {
                suggestionReason = "Warm-up movements"
            } else if elapsedMinutes > 40 {
                suggestionReason = "Finishing exercises"
            } else {
                suggestionReason = "Suggested for your split"
            }
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

    private func getDefaultSuggestions(currentExercises: [String], elapsedTime: TimeInterval = 0) -> [String] {
        let soul = TrainerSoul.load()
        let current = currentExercises.joined(separator: " ").lowercased()
        let elapsedMinutes = elapsedTime / 60

        func filterDone(_ list: [String]) -> [String] {
            let done = Set(currentExercises.map { $0.lowercased() })
            return list.filter { !done.contains($0.lowercased()) }
        }
        
        // Phase-specific suggestions
        if elapsedMinutes < 5 { // Warm-up phase: lighter compound movements
            let warmupExercises = ["Bodyweight Squat", "Push-Ups", "Arm Circles", "Leg Swings", "Light Goblet Squat", "Band Pull-Aparts"]
            return Array(filterDone(warmupExercises).prefix(6))
        }
        
        if elapsedMinutes > 40 { // Finishing phase: isolation/accessory work
            let finishingExercises = ["Lateral Raise", "Bicep Curl", "Tricep Pushdown", "Calf Raise", "Face Pulls", "Plank", "Hammer Curl", "Cable Fly"]
            return Array(filterDone(finishingExercises).prefix(6))
        }

        switch soul.trainingSplit {
        case .pushPullLegs:
            let push = ["Bench Press", "Overhead Press", "Incline Dumbbell Press", "Lateral Raise", "Tricep Pushdown", "Cable Fly"]
            let pull = ["Barbell Row", "Pull-Ups", "Face Pulls", "Hammer Curl", "Lat Pulldown", "Cable Row"]
            let legs = ["Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Calf Raise", "Bulgarian Split Squat"]

            if current.contains("bench") || current.contains("fly") || current.contains("tricep") || current.contains("shoulder") || current.contains("lateral") {
                return Array(filterDone(push).prefix(6))
            } else if current.contains("row") || current.contains("pull") || current.contains("curl") || current.contains("lat") || current.contains("face") {
                return Array(filterDone(pull).prefix(6))
            } else if current.contains("squat") || current.contains("deadlift") || current.contains("leg") || current.contains("calf") || current.contains("lunge") {
                return Array(filterDone(legs).prefix(6))
            }
            // No moments yet — show all three categories as starting points
            return ["Bench Press", "Squat", "Barbell Row", "Overhead Press", "Lateral Raise", "Romanian Deadlift"]

        case .upperLower:
            let upper = ["Bench Press", "Overhead Press", "Barbell Row", "Pull-Ups", "Lateral Raise", "Bicep Curl"]
            let lower = ["Squat", "Romanian Deadlift", "Leg Press", "Hip Thrust", "Leg Curl", "Calf Raise"]
            if current.contains("squat") || current.contains("deadlift") || current.contains("leg") || current.contains("hip") || current.contains("lunge") {
                return Array(filterDone(lower).prefix(6))
            } else if !current.isEmpty {
                return Array(filterDone(upper).prefix(6))
            }
            return ["Bench Press", "Squat", "Overhead Press", "Barbell Row", "Romanian Deadlift", "Pull-Ups"]

        case .fullBody:
            return Array(filterDone(["Squat", "Bench Press", "Barbell Row", "Overhead Press", "Romanian Deadlift", "Pull-Ups", "Lateral Raise", "Bicep Curl"]).prefix(6))

        case .broSplit:
            if current.contains("bench") || current.contains("fly") || current.contains("chest") {
                return Array(filterDone(["Incline Dumbbell Press", "Cable Fly", "Dumbbell Press", "Chest Fly", "Tricep Pushdown", "Dips"]).prefix(6))
            } else if current.contains("row") || current.contains("lat") || current.contains("back") {
                return Array(filterDone(["Barbell Row", "Lat Pulldown", "Cable Row", "Pull-Ups", "Face Pulls", "Hammer Curl"]).prefix(6))
            }
            return ["Bench Press", "Squat", "Barbell Row", "Overhead Press", "Lateral Raise", "Leg Press"]

        case .arnoldSplit:
            if current.contains("bench") || current.contains("row") || current.contains("back") || current.contains("chest") {
                return Array(filterDone(["Bench Press", "Barbell Row", "Incline Dumbbell Press", "Cable Row", "Cable Fly", "Lat Pulldown"]).prefix(6))
            } else if current.contains("curl") || current.contains("tricep") || current.contains("lateral") || current.contains("shoulder") {
                return Array(filterDone(["Overhead Press", "Lateral Raise", "Bicep Curl", "Tricep Pushdown", "Hammer Curl", "Face Pulls"]).prefix(6))
            }
            return ["Bench Press", "Barbell Row", "Overhead Press", "Squat", "Lateral Raise", "Bicep Curl"]

        case .phat, .custom:
            return Array(filterDone(["Bench Press", "Squat", "Deadlift", "Overhead Press", "Barbell Row", "Pull-Ups", "Lateral Raise", "Romanian Deadlift"]).prefix(6))
        }
    }
    
    func getLastPerformance(exercise: String, workoutStore: WorkoutStore) -> (weight: Double, reps: Int)? {
        for entry in workoutStore.index.prefix(10) {
            if let session = workoutStore.loadSession(id: entry.id),
               let group = session.structuredLog?.exercises.first(where: { 
                   $0.exerciseName.lowercased().contains(exercise.lowercased()) 
               }),
               let lastSet = group.sets.last,
               let weight = lastSet.weight,
               let reps = lastSet.reps {
                return (weight, reps)
            }
        }
        return nil
    }
    
    func getSmartOrderedSuggestions(currentTranscripts: [String], workoutStore: WorkoutStore, elapsedTime: TimeInterval = 0) -> [(exercise: String, priority: Int)] {
        let currentExercises = extractExercises(from: currentTranscripts)
        let historicalPairs = buildExercisePairings(from: workoutStore)
        
        var scores: [String: Int] = [:]
        
        // Score based on historical co-occurrence patterns
        for exercise in currentExercises {
            if let paired = historicalPairs[exercise.lowercased()] {
                for (pairedExercise, count) in paired {
                    if !currentExercises.map({ $0.lowercased() }).contains(pairedExercise.lowercased()) {
                        scores[pairedExercise, default: 0] += count * 3 // Historical patterns get high priority
                    }
                }
            }
        }
        
        // Add base suggestions with lower scores (phase-aware)
        let baseSuggestions = getDefaultSuggestions(currentExercises: currentExercises, elapsedTime: elapsedTime)
        for suggestion in baseSuggestions {
            scores[suggestion, default: 0] += 1
        }
        
        // Return sorted by priority (score)
        return scores.map { (exercise: $0.key, priority: $0.value) }
            .sorted { $0.priority > $1.priority }
    }
}

// MARK: - Active Workout Tab

struct ActiveWorkoutTab: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(PlannedWorkoutStore.self) private var plannedWorkoutStore
    @StateObject private var recorder = PhoneAudioRecorderService()
    @StateObject private var suggestionEngine = ExerciseSuggestionEngine()
    @State private var showMicPermissionDenied = false
    @State private var showEndConfirmation = false
    @State private var showDiscardStep1 = false
    @State private var discardConfirmText = ""
    @State private var showDiscardStep2 = false
    @State private var selectedTag: String?

    private var allTags: [ExerciseTag] {
        let completedExercises = Set(
            (workoutManager.activeSession?.moments.map(\.transcript) ?? [])
                .joined(separator: " ")
                .lowercased()
                .components(separatedBy: .whitespaces)
        )
        
        var tags: [ExerciseTag] = []
        
        // Get smart-ordered suggestions
        let smartSuggestions = suggestionEngine.getSmartOrderedSuggestions(
            currentTranscripts: workoutManager.activeSession?.moments.map(\.transcript) ?? [],
            workoutStore: workoutManager.workoutStore,
            elapsedTime: workoutElapsedTime
        )
        
        // Planned exercises first (from trainer)
        let plannedNames = Set(plannedWorkoutStore.plannedExercises.map { $0.lowercased() })
        for exercise in plannedWorkoutStore.plannedExercises {
            let isCompleted = completedExercises.contains(where: { exercise.lowercased().contains($0) })
            let priority = smartSuggestions.first(where: { $0.exercise.lowercased() == exercise.lowercased() })?.priority ?? 0
            tags.append(ExerciseTag(name: exercise, source: .planned, isCompleted: isCompleted, priority: priority))
        }
        
        // Then smart suggestions (skip if already in planned)
        for suggestion in smartSuggestions.prefix(8) {
            if !plannedNames.contains(suggestion.exercise.lowercased()) {
                tags.append(ExerciseTag(name: suggestion.exercise, source: .suggested, priority: suggestion.priority))
            }
        }
        
        // Sort all tags by priority (highest first)
        return tags.sorted { $0.priority > $1.priority }
    }
    
    private var workoutElapsedTime: TimeInterval {
        guard let session = workoutManager.activeSession else { return 0 }
        return Date().timeIntervalSince(session.startedAt)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Compact timer header
                timerHeader
                
                // Main canvas area - always visible
                ScrollView {
                    VStack(spacing: 20) {
                        // Moments feed (when exists)
                        if let session = workoutManager.activeSession, !session.moments.isEmpty {
                            momentsFeedContent(session: session)
                        }
                        
                        // The tag cloud is ALWAYS the main interface
                        if !allTags.isEmpty {
                            VStack(spacing: 12) {
                                // Workout type header
                                if let session = workoutManager.activeSession, session.moments.isEmpty {
                                    workoutTypeHeader
                                }
                                
                                WorkoutCanvas(
                                    tags: allTags,
                                    reason: plannedWorkoutStore.planSource.isEmpty 
                                        ? suggestionEngine.suggestionReason 
                                        : plannedWorkoutStore.planSource,
                                    selectedTag: $selectedTag,
                                    momentsCount: workoutManager.activeSession?.moments.count ?? 0,
                                    workoutElapsed: workoutElapsedTime,
                                    workoutStore: workoutManager.workoutStore,
                                    suggestionEngine: suggestionEngine,
                                    currentSession: workoutManager.activeSession
                                )
                            }
                            .frame(maxWidth: .infinity)
                        }
                        
                        Spacer(minLength: 120) // Space for mic button
                    }
                }
                .background(Theme.background)
                
                // Bottom mic button (always visible)
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
        suggestionEngine.update(
            currentTranscripts: transcripts, 
            workoutStore: workoutManager.workoutStore,
            elapsedTime: workoutElapsedTime
        )
        
        // Update suggestions with smart ordering
        let smartSuggestions = suggestionEngine.getSmartOrderedSuggestions(
            currentTranscripts: transcripts, 
            workoutStore: workoutManager.workoutStore,
            elapsedTime: workoutElapsedTime
        )
        suggestionEngine.suggestions = smartSuggestions.prefix(8).map(\.exercise)
    }

    private var timerHeader: some View {
        VStack(spacing: 6) {
            Text(formattedElapsed)
                .font(.system(size: 36, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                Label("\(workoutManager.activeSession?.moments.count ?? 0) \((workoutManager.activeSession?.moments.count ?? 0) == 1 ? "moment" : "moments")", systemImage: "waveform")
                    .font(.caption).foregroundStyle(Theme.textSecondary)

                if workoutManager.isProcessingMoment {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Transcribing...").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
    }
    
    private var workoutTypeHeader: some View {
        VStack(spacing: 4) {
            Text("YOUR WORKOUT")
                .font(.caption2)
                .foregroundColor(Theme.textTertiary)
                .textCase(.uppercase)
                .tracking(1.5)
            
            if !plannedWorkoutStore.planSource.isEmpty {
                Text(plannedWorkoutStore.planSource)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.top, 8)
    }

    private func momentsFeedContent(session: WorkoutSession) -> some View {
        VStack(spacing: 0) {
            ForEach(session.moments.reversed()) { moment in
                VStack(alignment: .leading, spacing: 4) {
                    Text(moment.transcript)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text(moment.timestamp, style: .time)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        
                        if moment.source == .watch {
                            Image(systemName: "applewatch")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
            }
        }
        .padding(.horizontal, 16)
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
