import SwiftUI
import WatchKit

struct ActiveWorkoutView: View {
    @Environment(WatchWorkoutManager.self) private var workoutManager
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State private var isPulsing = false
    @State private var dotVisible = true
    @State private var showSnippet = false
    @State private var showSummary = false

    var body: some View {
        Group {
            if showSummary {
                WorkoutSummaryView(
                    duration: workoutManager.elapsedTime,
                    momentCount: workoutManager.momentCount,
                    averageHeartRate: workoutManager.healthKitService.averageHeartRate,
                    totalCalories: workoutManager.healthKitService.totalActiveCalories
                ) {
                    showSummary = false
                    workoutManager.completeWorkoutDismissal()
                }
            } else if isLuminanceReduced {
                alwaysOnView
            } else {
                activeView
            }
        }
        .onChange(of: workoutManager.latestTranscriptSnippet) {
            if workoutManager.latestTranscriptSnippet != nil {
                withAnimation(.easeOut(duration: 0.4)) { showSnippet = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeIn(duration: 0.3)) { showSnippet = false }
                }
            }
        }
        .onChange(of: workoutManager.isRecordingMoment) {
            if workoutManager.isRecordingMoment {
                showSnippet = false
                startAnimations()
            } else {
                stopAnimations()
            }
        }
        .onChange(of: workoutManager.didReceiveRemoteStop) {
            if workoutManager.didReceiveRemoteStop { showSummary = true }
        }
    }

    // MARK: - Active View (Vertical Pages)

    private var activeView: some View {
        TabView {
            // Page 1: Main controls
            mainPage
                .containerBackground(WatchTheme.background.gradient, for: .tabView)

            // Page 2: Health stats
            statsPage
                .containerBackground(WatchTheme.background.gradient, for: .tabView)

            // Page 3: Now Playing
            NowPlayingPage()
                .containerBackground(WatchTheme.background.gradient, for: .tabView)
        }
        .tabViewStyle(.verticalPage)
    }

    // MARK: - Page 1: Main Controls

    private var mainPage: some View {
        VStack(spacing: 0) {
            // Timer — uses TimelineView so watchOS keeps it ticking
            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                Text(formattedElapsed)
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(WatchTheme.textPrimary)
            }
            .padding(.top, 4)

            Spacer(minLength: 4)

            // Record button
            recordButton

            // Status
            statusArea
                .padding(.top, 4)

            Spacer(minLength: 4)

            // End workout
            Button {
                workoutManager.endWorkout()
                showSummary = true
            } label: {
                Text("End")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .overlay(alignment: .bottom) {
            snippetOverlay.padding(.bottom, 40)
        }
    }

    // MARK: - Page 2: Stats

    private var statsPage: some View {
        VStack(spacing: 14) {
            Text("STATS")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(WatchTheme.textTertiary)
                .tracking(1.5)

            Spacer()

            // Heart Rate
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text(workoutManager.healthKitService.heartRate > 0
                     ? "\(Int(workoutManager.healthKitService.heartRate))"
                     : "--")
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                Text("BPM")
                    .font(.caption)
                    .foregroundStyle(WatchTheme.textTertiary)
            }
            .foregroundStyle(WatchTheme.textPrimary)

            // Calories
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text(workoutManager.healthKitService.activeCalories > 0
                     ? "\(Int(workoutManager.healthKitService.activeCalories))"
                     : "--")
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                Text("CAL")
                    .font(.caption)
                    .foregroundStyle(WatchTheme.textTertiary)
            }
            .foregroundStyle(WatchTheme.textPrimary)

            // Moments
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .foregroundStyle(WatchTheme.accent)
                Text("\(workoutManager.momentCount)")
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                Text(workoutManager.momentCount == 1 ? "MOMENT" : "MOMENTS")
                    .font(.caption)
                    .foregroundStyle(WatchTheme.textTertiary)
            }
            .foregroundStyle(WatchTheme.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Always On Display

    private var alwaysOnView: some View {
        VStack(spacing: 10) {
            Spacer()
            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                Text(formattedElapsed)
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(WatchTheme.textPrimary.opacity(0.6))
            }
            if workoutManager.healthKitService.heartRate > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").font(.caption2).foregroundStyle(.red.opacity(0.5))
                    Text("\(Int(workoutManager.healthKitService.heartRate))").font(.caption)
                }
                .foregroundStyle(WatchTheme.textSecondary.opacity(0.6))
            }
            Spacer()
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            if workoutManager.isRecordingMoment {
                workoutManager.stopRecordingMoment()
            } else {
                workoutManager.recordMoment()
            }
        } label: {
            ZStack {
                if workoutManager.isRecordingMoment {
                    Circle()
                        .fill(RadialGradient(
                            colors: [WatchTheme.accentBright.opacity(0.4), .clear],
                            center: .center, startRadius: 16, endRadius: 40
                        ))
                        .frame(width: 72, height: 72)
                        .opacity(isPulsing ? 0.8 : 0.3)
                }

                Circle()
                    .fill(LinearGradient(
                        colors: workoutManager.isRecordingMoment ? WatchTheme.recordingGradient : WatchTheme.accentGradient,
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 56, height: 56)

                Image(systemName: workoutManager.isRecordingMoment ? "stop.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isPulsing ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: workoutManager.isRecordingMoment)
    }

    // MARK: - Status Area

    @ViewBuilder
    private var statusArea: some View {
        Group {
            if workoutManager.isRecordingMoment {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(WatchTheme.accentBright)
                            .frame(width: 6, height: 6)
                            .opacity(dotVisible ? 1.0 : 0.0)
                        Text(formattedRecordingDuration)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(WatchTheme.textPrimary)
                    }
                }
            } else if workoutManager.connectivity.isSending {
                HStack(spacing: 4) {
                    ProgressView().tint(WatchTheme.accent)
                    Text("Transcribing")
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.accent)
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("\(workoutManager.momentCount) moment\(workoutManager.momentCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - Snippet Overlay

    @ViewBuilder
    private var snippetOverlay: some View {
        if let snippet = workoutManager.latestTranscriptSnippet, showSnippet {
            Text(snippet.prefix(80) + (snippet.count > 80 ? "..." : ""))
                .font(.caption2)
                .foregroundStyle(WatchTheme.textPrimary.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(WatchTheme.surface.opacity(0.95)))
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        if let error = workoutManager.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).foregroundStyle(.red).padding(.horizontal, 8)
        }
    }

    // MARK: - Helpers

    private var formattedElapsed: String {
        let total = Int(workoutManager.elapsedTime)
        let hrs = total / 3600; let mins = (total % 3600) / 60; let secs = total % 60
        return hrs > 0 ? String(format: "%d:%02d:%02d", hrs, mins, secs) : String(format: "%d:%02d", mins, secs)
    }

    private var formattedRecordingDuration: String {
        let s = Int(workoutManager.recorder.recordingDuration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func startAnimations() {
        if reduceMotion { isPulsing = true; dotVisible = true } else {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { isPulsing = true }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dotVisible = false }
        }
    }

    private func stopAnimations() {
        withAnimation(.easeOut(duration: 0.3)) { isPulsing = false; dotVisible = true }
    }
}
