import AVFoundation
import SwiftUI

struct ActiveWorkoutTab: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @StateObject private var recorder = PhoneAudioRecorderService()
    @State private var showMicPermissionDenied = false
    @State private var showEndConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                timerHeader
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
