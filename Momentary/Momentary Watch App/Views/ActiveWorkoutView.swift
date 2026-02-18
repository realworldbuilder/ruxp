import SwiftUI
import WatchKit

struct ActiveWorkoutView: View {
    @Environment(WatchWorkoutManager.self) private var workoutManager

    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State private var isPulsing = false
    @State private var ringRotation: Double = 0
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
                withAnimation(.easeOut(duration: 0.4)) {
                    showSnippet = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeIn(duration: 0.3)) {
                        showSnippet = false
                    }
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
            if workoutManager.didReceiveRemoteStop {
                showSummary = true
            }
        }
    }

    // MARK: - Active View

    private var activeView: some View {
        TabView {
            workoutPage
                .containerBackground(WatchTheme.background.gradient, for: .tabView)

            NowPlayingPage()
                .containerBackground(WatchTheme.background.gradient, for: .tabView)
        }
        .tabViewStyle(.verticalPage)
    }

    // MARK: - Workout Page

    private var workoutPage: some View {
        VStack(spacing: 4) {
            workoutTimer
            healthMetricsRow
            Spacer(minLength: 0)
            momentRecordButton
            statusArea
            Spacer(minLength: 0)
            endWorkoutButton
        }
        .padding(.horizontal, 8)
        .overlay(alignment: .bottom) {
            snippetOverlay
                .padding(.bottom, 44)
        }
    }

    // MARK: - Always On Display

    private var alwaysOnView: some View {
        VStack(spacing: 10) {
            Spacer()

            Text(formattedElapsed)
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(WatchTheme.textPrimary.opacity(0.6))

            if workoutManager.healthKitService.heartRate > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.5))
                    Text("\(Int(workoutManager.healthKitService.heartRate))")
                        .font(.caption)
                }
                .foregroundStyle(WatchTheme.textSecondary.opacity(0.6))
            }

            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.caption)
                Text("\(workoutManager.momentCount)")
                    .font(.caption)
            }
            .foregroundStyle(WatchTheme.textSecondary.opacity(0.6))

            Spacer()
        }
    }

    // MARK: - Workout Timer

    private var workoutTimer: some View {
        Text(formattedElapsed)
            .font(.system(.title3, design: .monospaced))
            .foregroundStyle(WatchTheme.textPrimary)
            .accessibilityLabel("Workout time: \(spokenElapsed)")
    }

    // MARK: - Health Metrics

    private var healthMetricsRow: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.caption2)
                Text(workoutManager.healthKitService.heartRate > 0
                     ? "\(Int(workoutManager.healthKitService.heartRate))"
                     : "--")
                    .font(.system(.caption, design: .monospaced))
                Text("BPM")
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.textTertiary)
            }

            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .font(.caption2)
                Text(workoutManager.healthKitService.activeCalories > 0
                     ? "\(Int(workoutManager.healthKitService.activeCalories))"
                     : "--")
                    .font(.system(.caption, design: .monospaced))
                Text("CAL")
                    .font(.caption2)
                    .foregroundStyle(WatchTheme.textTertiary)
            }
        }
        .foregroundStyle(WatchTheme.textPrimary)
    }

    // MARK: - Record Button

    private var momentRecordButton: some View {
        Button {
            if workoutManager.isRecordingMoment {
                workoutManager.stopRecordingMoment()
            } else {
                workoutManager.recordMoment()
            }
        } label: {
            ZStack {
                // Outer glow when recording
                if workoutManager.isRecordingMoment {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [WatchTheme.accentBright.opacity(0.4), .clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 50
                            )
                        )
                        .frame(width: 82, height: 82)
                        .opacity(isPulsing ? 0.8 : 0.3)
                        .accessibilityHidden(true)
                }

                // Spinning ring when recording
                if workoutManager.isRecordingMoment {
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: WatchTheme.recordingGradient + [WatchTheme.recordingGradient[0]],
                                center: .center
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 76, height: 76)
                        .rotationEffect(.degrees(ringRotation))
                        .accessibilityHidden(true)
                }

                // Main button circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: workoutManager.isRecordingMoment ? WatchTheme.recordingGradient : WatchTheme.accentGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 66, height: 66)

                Image(systemName: workoutManager.isRecordingMoment ? "stop.fill" : "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(isPulsing ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: workoutManager.isRecordingMoment)
        .accessibilityLabel(workoutManager.isRecordingMoment ? "Stop recording moment" : "Record a moment")
    }

    // MARK: - Status Area

    @ViewBuilder
    private var statusArea: some View {
        if workoutManager.isRecordingMoment {
            HStack(spacing: 6) {
                Circle()
                    .fill(WatchTheme.accentBright)
                    .frame(width: 8, height: 8)
                    .opacity(dotVisible ? 1.0 : 0.0)

                Text(formattedRecordingDuration)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(WatchTheme.textPrimary)
            }
            .accessibilityElement(children: .combine)
        } else if workoutManager.connectivity.isSending {
            VStack(spacing: 6) {
                ProgressView()
                    .tint(WatchTheme.accent)
                Text("Transcribing")
                    .font(.caption)
                    .foregroundStyle(WatchTheme.accent)
                    .fixedSize()
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.caption2)
                Text("\(workoutManager.momentCount) moment\(workoutManager.momentCount == 1 ? "" : "s")")
                    .font(.caption)
            }
            .foregroundStyle(WatchTheme.textSecondary)
        }
    }

    // MARK: - Snippet Overlay

    @ViewBuilder
    private var snippetOverlay: some View {
        if let snippet = workoutManager.latestTranscriptSnippet, showSnippet {
            Text(truncatedSnippet(snippet))
                .font(.caption2)
                .foregroundStyle(WatchTheme.textPrimary.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(WatchTheme.surface.opacity(0.95))
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        if let error = workoutManager.lastError {
            Label {
                Text(error)
                    .lineLimit(2)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption2)
            .foregroundStyle(.red)
            .padding(.horizontal, 8)
        }
    }

    // MARK: - End Workout Button

    private var endWorkoutButton: some View {
        Button {
            workoutManager.endWorkout()
            showSummary = true
        } label: {
            Text("End Workout")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: WatchTheme.dangerGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End workout")
    }

    // MARK: - Helpers

    private var formattedElapsed: String {
        let total = Int(workoutManager.elapsedTime)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    private var spokenElapsed: String {
        let total = Int(workoutManager.elapsedTime)
        let mins = total / 60
        let secs = total % 60
        if mins == 0 { return "\(secs) seconds" }
        return "\(mins) minutes \(secs) seconds"
    }

    private var formattedRecordingDuration: String {
        let seconds = Int(workoutManager.recorder.recordingDuration)
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func truncatedSnippet(_ text: String, maxLength: Int = 80) -> String {
        guard text.count > maxLength else { return text }
        let trimmed = text.prefix(maxLength)
        if let lastSpace = trimmed.lastIndex(of: " ") {
            return String(trimmed[trimmed.startIndex..<lastSpace]) + "..."
        }
        return String(trimmed) + "..."
    }

    // MARK: - Animations

    private func startAnimations() {
        if reduceMotion {
            isPulsing = true
            ringRotation = 0
            dotVisible = true
        } else {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                dotVisible = false
            }
        }
    }

    private func stopAnimations() {
        withAnimation(.easeOut(duration: 0.3)) {
            isPulsing = false
            ringRotation = 0
            dotVisible = true
        }
    }
}
