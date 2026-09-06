import SwiftUI
import WatchKit

struct NowPlayingPage: View {
    @Environment(WatchWorkoutManager.self) private var workoutManager

    var body: some View {
        NowPlayingView()
            .overlay {
                if workoutManager.isRecordingMoment {
                    Color.black.opacity(0.6)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "mic.fill")
                                    .font(.title3)
                                    .foregroundStyle(.green)
                                Text("Recording...")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                }
            }
    }
}
