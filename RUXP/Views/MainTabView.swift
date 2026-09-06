import SwiftUI

extension Notification.Name {
    static let switchToWorkoutTab = Notification.Name("switchToWorkoutTab")
    static let workoutsDidChange = Notification.Name("workoutsDidChange")
    static let switchToTab = Notification.Name("switchToTab")
}

enum AppTab: Hashable {
    case home, train, profile
}

/// Three tabs. One full-screen cover hosts the entire workout flow
/// (active workout → completion) so the transition never crosses presentation hosts.
struct MainTabView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @State private var selectedTab: AppTab = .home

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.background)
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.08)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private var workoutFlowPresented: Binding<Bool> {
        Binding(
            get: { workoutManager.activeSession != nil || workoutManager.completedWorkoutID != nil },
            set: { if !$0 { workoutManager.completedWorkoutID = nil } }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "bolt.fill") }
                .tag(AppTab.home)

            TrainView()
                .tabItem { Label("Train", systemImage: "list.bullet.rectangle.fill") }
                .tag(AppTab.train)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(AppTab.profile)
        }
        .tint(Theme.accent)
        .fullScreenCover(isPresented: workoutFlowPresented) {
            WorkoutFlowCover()
        }
        .onChange(of: workoutManager.completedWorkoutID) { old, new in
            // CONTINUE on the completion screen returns to Home.
            if old != nil && new == nil { selectedTab = .home }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notification in
            if let idx = notification.userInfo?["tabIndex"] as? Int {
                selectedTab = idx == 1 ? .train : idx == 2 ? .profile : .home
            }
        }
    }
}

/// Switches between the live workout and the reward screen inside one cover.
struct WorkoutFlowCover: View {
    @Environment(WorkoutManager.self) private var workoutManager

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if workoutManager.activeSession != nil {
                ActiveWorkoutTab()
                    .transition(.opacity)
            } else if let id = workoutManager.completedWorkoutID {
                WorkoutCompletionSheet(workoutID: id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: workoutManager.activeSession == nil)
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
    }
}
