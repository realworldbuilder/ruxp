import AVFoundation
import SwiftUI

@MainActor
class ExerciseSuggestionEngine: ObservableObject {
    @Published var suggestions: [String] = []
    @Published var suggestionReason: String = ""
    @Published var todaysFocus: String = "" // e.g. "Pull Day", "Leg Day"

    func update(currentTranscripts: [String], workoutStore: WorkoutStore, elapsedTime: TimeInterval = 0) {
        let currentExercises = extractExercises(from: currentTranscripts)
        let focus = determineTodaysFocus(workoutStore: workoutStore, currentExercises: currentExercises)
        todaysFocus = focus.name
        
        // Historical co-occurrence
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

        let historySuggestions = scores.sorted { $0.value > $1.value }.prefix(8).map(\.key)

        if !historySuggestions.isEmpty {
            suggestions = historySuggestions
            suggestionReason = "Based on your history"
        } else {
            suggestions = focus.exercises
            suggestionReason = focus.name
        }
    }

    // MARK: - Determine Today's Focus
    
    struct FocusPlan {
        let name: String       // "Pull Day", "Upper Body", etc.
        let exercises: [String] // The main exercises for this focus
    }
    
    private func determineTodaysFocus(workoutStore: WorkoutStore, currentExercises: [String]) -> FocusPlan {
        let soul = TrainerSoul.load()
        let current = currentExercises.joined(separator: " ").lowercased()
        let done = Set(currentExercises.map { $0.lowercased() })
        
        func filterDone(_ list: [String]) -> [String] {
            list.filter { !done.contains($0.lowercased()) }
        }
        
        // If user already started exercises, detect the focus from what they're doing
        if !current.isEmpty {
            return detectFocusFromExercises(current: current, soul: soul, filterDone: filterDone)
        }
        
        // Otherwise, determine focus from last workout + split rotation
        let lastFocus = workoutStore.index.first?.muscleGroupFocus.lowercased() ?? ""
        
        switch soul.trainingSplit {
        case .pushPullLegs:
            let push = ["Bench Press", "Overhead Press", "Incline Dumbbell Press", "Lateral Raise", "Tricep Pushdown", "Cable Fly"]
            let pull = ["Deadlift", "Barbell Row", "Pull-Ups", "Face Pulls", "Lat Pulldown", "EZ Bar Curl"]
            let legs = ["Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Calf Raise", "Bulgarian Split Squat"]
            
            if lastFocus.contains("push") || lastFocus.contains("chest") {
                return FocusPlan(name: "Pull Day", exercises: filterDone(pull))
            } else if lastFocus.contains("pull") || lastFocus.contains("back") {
                return FocusPlan(name: "Leg Day", exercises: filterDone(legs))
            } else {
                return FocusPlan(name: "Push Day", exercises: filterDone(push))
            }
            
        case .upperLower:
            let upper = ["Bench Press", "Overhead Press", "Barbell Row", "Pull-Ups", "Lateral Raise", "Bicep Curl"]
            let lower = ["Squat", "Romanian Deadlift", "Leg Press", "Hip Thrust", "Leg Curl", "Calf Raise"]
            
            if lastFocus.contains("upper") || lastFocus.contains("chest") || lastFocus.contains("back") || lastFocus.contains("shoulder") {
                return FocusPlan(name: "Lower Body", exercises: filterDone(lower))
            } else {
                return FocusPlan(name: "Upper Body", exercises: filterDone(upper))
            }
            
        case .fullBody:
            return FocusPlan(name: "Full Body", exercises: filterDone(["Squat", "Bench Press", "Barbell Row", "Overhead Press", "Romanian Deadlift", "Pull-Ups"]))
            
        case .broSplit:
            let splits: [(name: String, exercises: [String])] = [
                ("Chest Day", ["Bench Press", "Incline Dumbbell Press", "Cable Fly", "Dumbbell Press", "Chest Fly", "Dips"]),
                ("Back Day", ["Deadlift", "Barbell Row", "Lat Pulldown", "Cable Row", "Pull-Ups", "Face Pulls"]),
                ("Shoulder Day", ["Overhead Press", "Lateral Raise", "Face Pulls", "Rear Delt Fly", "Shrugs", "Arnold Press"]),
                ("Leg Day", ["Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Calf Raise", "Bulgarian Split Squat"]),
                ("Arms Day", ["Bicep Curl", "Tricep Pushdown", "Hammer Curl", "Skull Crushers", "Preacher Curl", "Tricep Extension"])
            ]
            // Rotate based on last focus
            let lastIndex = splits.firstIndex(where: { lastFocus.contains($0.name.split(separator: " ").first?.lowercased() ?? "") }) ?? -1
            let nextIndex = (lastIndex + 1) % splits.count
            let next = splits[nextIndex]
            return FocusPlan(name: next.name, exercises: filterDone(next.exercises))
            
        case .arnoldSplit:
            let chestBack = ["Bench Press", "Barbell Row", "Incline Dumbbell Press", "Cable Row", "Cable Fly", "Lat Pulldown"]
            let shouldersArms = ["Overhead Press", "Lateral Raise", "Bicep Curl", "Tricep Pushdown", "Hammer Curl", "Face Pulls"]
            let legs = ["Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Calf Raise", "Bulgarian Split Squat"]
            
            if lastFocus.contains("chest") || lastFocus.contains("back") {
                return FocusPlan(name: "Shoulders & Arms", exercises: filterDone(shouldersArms))
            } else if lastFocus.contains("shoulder") || lastFocus.contains("arm") {
                return FocusPlan(name: "Leg Day", exercises: filterDone(legs))
            } else {
                return FocusPlan(name: "Chest & Back", exercises: filterDone(chestBack))
            }
            
        case .phat, .custom:
            return FocusPlan(name: "Workout", exercises: filterDone(["Bench Press", "Squat", "Deadlift", "Overhead Press", "Barbell Row", "Pull-Ups"]))
        }
    }
    
    private func detectFocusFromExercises(current: String, soul: TrainerSoul, filterDone: ([String]) -> [String]) -> FocusPlan {
        // Detect what they're already doing and suggest more of the same
        let push = ["Bench Press", "Overhead Press", "Incline Dumbbell Press", "Lateral Raise", "Tricep Pushdown", "Cable Fly"]
        let pull = ["Deadlift", "Barbell Row", "Pull-Ups", "Face Pulls", "Lat Pulldown", "EZ Bar Curl"]
        let legs = ["Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Calf Raise", "Bulgarian Split Squat"]
        
        if current.contains("bench") || current.contains("fly") || current.contains("tricep") || current.contains("shoulder") || current.contains("lateral") || current.contains("push") {
            return FocusPlan(name: "Push Day", exercises: filterDone(push))
        } else if current.contains("row") || current.contains("pull") || current.contains("curl") || current.contains("lat") || current.contains("face") || current.contains("deadlift") {
            return FocusPlan(name: "Pull Day", exercises: filterDone(pull))
        } else if current.contains("squat") || current.contains("leg") || current.contains("calf") || current.contains("lunge") || current.contains("hip") {
            return FocusPlan(name: "Leg Day", exercises: filterDone(legs))
        }
        return FocusPlan(name: "Workout", exercises: filterDone(push + pull + legs))
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
            "bicep curl", "hammer curl", "preacher curl", "ez bar curl",
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
        let focus = determineTodaysFocus(workoutStore: workoutStore, currentExercises: currentExercises)
        todaysFocus = focus.name
        
        let historicalPairs = buildExercisePairings(from: workoutStore)
        var scores: [String: Int] = [:]
        
        // Score based on historical co-occurrence patterns
        for exercise in currentExercises {
            if let paired = historicalPairs[exercise.lowercased()] {
                for (pairedExercise, count) in paired {
                    if !currentExercises.map({ $0.lowercased() }).contains(pairedExercise.lowercased()) {
                        scores[pairedExercise, default: 0] += count * 3
                    }
                }
            }
        }
        
        // Add focus exercises with base priority
        for (i, exercise) in focus.exercises.enumerated() {
            scores[exercise, default: 0] += max(1, focus.exercises.count - i) // Higher priority for earlier exercises
        }
        
        return scores.map { (exercise: $0.key, priority: $0.value) }
            .sorted { $0.priority > $1.priority }
    }
}

// MARK: - Active Workout Tab (Stripped — stable core only)

struct ActiveWorkoutTab: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @StateObject private var recorder = PhoneAudioRecorderService()
    @State private var showMicPermissionDenied = false
    @State private var showEndConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var elapsedText = "0:00"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Timer
                VStack(spacing: 6) {
                    Text(elapsedText)
                        .font(.system(size: 36, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)

                    HStack(spacing: 16) {
                        Label("\(workoutManager.activeSession?.moments.count ?? 0) moments", systemImage: "waveform")
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

                // Moments feed
                ScrollView {
                    VStack(spacing: 8) {
                        if let session = workoutManager.activeSession {
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
                        Spacer(minLength: 120)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .background(Theme.background)

                // Mic button
                VStack(spacing: 12) {
                    if recorder.isRecording {
                        HStack(spacing: 8) {
                            Circle().fill(.red).frame(width: 10, height: 10)
                            Text(formattedRecordingDuration).font(.body.monospacedDigit())
                        }
                    }
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
                    .padding(.bottom, 16)
                }
                .padding()
                .background(Theme.background)
            }
            .background(Theme.background)
            .navigationTitle("Active Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDiscardConfirmation = true } label: {
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
            .alert("Discard Workout?", isPresented: $showDiscardConfirmation) {
                Button("Discard", role: .destructive) { workoutManager.discardWorkout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will throw away all recorded moments.")
            }
            .onReceive(timer) { _ in updateElapsed() }
            .onAppear { updateElapsed() }
        }
    }

    private func updateElapsed() {
        guard let session = workoutManager.activeSession else { elapsedText = "0:00"; return }
        let total = Int(Date().timeIntervalSince(session.startedAt))
        let hrs = total / 3600, mins = (total % 3600) / 60, secs = total % 60
        elapsedText = hrs > 0 ? String(format: "%d:%02d:%02d", hrs, mins, secs) : String(format: "%d:%02d", mins, secs)
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
