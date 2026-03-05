import SwiftUI

extension Notification.Name {
    static let switchToWorkoutTab = Notification.Name("switchToWorkoutTab")
    static let workoutsDidChange = Notification.Name("workoutsDidChange")
    static let switchToTab = Notification.Name("switchToTab")
}

struct MainTabView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @State private var selectedTab = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            InsightsTab()
                .tabItem { Label("Insights", systemImage: "lightbulb.fill") }
                .tag(1)

            ChatView()
                .tabItem { Label("Trainer", systemImage: "bubble.left.and.text.bubble.right.fill") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(Theme.accent)
        .onReceive(NotificationCenter.default.publisher(for: .switchToWorkoutTab)) { _ in
            selectedTab = 0 // Home tab now hosts the workout
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notification in
            if let idx = notification.userInfo?["tabIndex"] as? Int {
                selectedTab = idx
            }
        }
        .onChange(of: workoutManager.activeSession?.id) { oldVal, newVal in
            if newVal != nil && oldVal == nil {
                selectedTab = 0 // Stay on home
            }
        }
        .fullScreenCover(item: Binding<WorkoutCompletionID?>(
            get: { workoutManager.completedWorkoutID.map { WorkoutCompletionID(id: $0) } },
            set: { workoutManager.completedWorkoutID = $0?.id }
        )) { item in
            WorkoutCompletionSheet(workoutID: item.id)
                .environment(workoutManager)
        }
    }
}

/// Wrapper to make UUID work with fullScreenCover(item:)
private struct WorkoutCompletionID: Identifiable {
    let id: UUID
}
