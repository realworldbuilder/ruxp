import AVFoundation
import SwiftUI

// MARK: - Active Workout Tab (Stripped — stable core only)

struct ActiveWorkoutTab: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(\.livePresence) private var presence
    @Environment(\.liveEvents) private var events
    @StateObject private var recorder = PhoneAudioRecorderService()
    @State private var showMicPermissionDenied = false
    @State private var showEndConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var elapsedText = "0:00"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                timerBlock
                liveStrip
                if let plan = workoutManager.activeSession?.plannedWorkout {
                    PlanStripView(plan: plan, transcriptBlob: transcriptBlob)
                }
                momentsFeed
                micBlock
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    LiveDot(label: "LIVE")
                }
            }
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
                Button(hasNothingLogged ? "Save Anyway" : "End") { workoutManager.endWorkout() }
                if hasNothingLogged {
                    Button("Discard", role: .destructive) { workoutManager.discardWorkout() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(hasNothingLogged
                     ? "Nothing logged yet. Sessions of \(Int(ProgressionRules.minimumWorkoutDuration / 60))+ minutes still earn XP."
                     : "This locks in your XP and starts parsing your notes.")
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

    // MARK: - Sub-views

    private var timerBlock: some View {
        VStack(spacing: 6) {
            Text(elapsedText)
                .font(Theme.Fonts.number(46))
                .foregroundStyle(Theme.textPrimary)

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
    }

    private var momentsFeed: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let session = workoutManager.activeSession {
                    ForEach(session.moments.reversed()) { moment in
                        momentRow(moment)
                    }
                }
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(Theme.background)
    }

    private func momentRow(_ moment: Moment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(moment.transcript)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
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
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 0.5))
    }

    private var micBlock: some View {
        VStack(spacing: 12) {
            if recorder.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(Theme.live).frame(width: 10, height: 10)
                    Text(formattedRecordingDuration).font(.body.monospacedDigit())
                }
            }
            Button {
                if recorder.isRecording { stopAndAddMoment() }
                else { requestMicAndRecord() }
            } label: {
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title2)
                    .foregroundStyle(recorder.isRecording ? Color.white : Theme.onAccent)
                    .frame(width: 64, height: 64)
                    .background(recorder.isRecording ? Theme.live : Theme.accent, in: Circle())
                    .shadow(color: (recorder.isRecording ? Theme.live : Theme.accent).opacity(0.4), radius: 8, y: 2)
            }
            .padding(.bottom, 16)
        }
        .padding()
        .background(Theme.background)
    }

    private var hasNothingLogged: Bool {
        workoutManager.activeSession?.moments.isEmpty ?? true
    }

    /// Other people are doing this with you.
    private var liveStrip: some View {
        let live = presence?.snapshot ?? .empty
        let event = events.activeEvent(at: ScheduledEventService.now())
        return HStack(spacing: 10) {
            LiveDot(label: nil, size: 7)
            Text("\(live.liftingNow.grouped) still lifting")
                .font(Theme.Fonts.label).monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.numericText())
                .animation(Theme.Motion.snappy, value: live.liftingNow)
            Spacer()
            if let event {
                HStack(spacing: 6) {
                    Text(event.title).eyebrow().foregroundStyle(Theme.accent)
                    Text("+\(event.xpReward) XP").eyebrow().foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.accentSubtle, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.divider) }
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

    /// All moment transcripts joined lowercase, for cheap "was this exercise mentioned" checks.
    private var transcriptBlob: String {
        (workoutManager.activeSession?.moments ?? [])
            .map { $0.transcript.lowercased() }
            .joined(separator: " ")
    }
}

// MARK: - Plan Strip

private struct PlanStripView: View {
    let plan: PlannedWorkout
    let transcriptBlob: String
    @State private var expanded = false

    private var mentionedCount: Int {
        plan.exercises.filter { PlanMatching.blobMentions($0.name, in: transcriptBlob) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Text(plan.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(mentionedCount)/\(plan.exercises.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 6) {
                    ForEach(plan.exercises) { exercise in
                        let mentioned = PlanMatching.blobMentions(exercise.name, in: transcriptBlob)
                        HStack(spacing: 8) {
                            Image(systemName: mentioned ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(mentioned ? Theme.accent : Theme.textSecondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(exercise.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 8) {
                                    Text(exercise.prescription)
                                        .font(.caption)
                                        .foregroundStyle(Theme.accent)
                                    if let rest = exercise.restDisplay {
                                        Text("Rest \(rest)")
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .opacity(mentioned ? 0.4 : 1.0)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Theme.cardBackground)
        .overlay(alignment: .bottom) {
            Divider().overlay(Theme.border)
        }
    }
}
