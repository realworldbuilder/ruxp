import SwiftUI

extension Notification.Name {
    static let switchToWorkoutTab = Notification.Name("switchToWorkoutTab")
    static let workoutsDidChange = Notification.Name("workoutsDidChange")
    static let switchToTab = Notification.Name("switchToTab")
}

enum AppTab: Hashable {
    case home, train, profile
}

#if DEBUG
/// `-RUXPScreen seasonpass|settings|livehistory|archivedpass`: open a sheet or cover at launch so
/// every screen can be screenshotted from the command line. Read by HomeView and ProfileView.
enum DebugScreen: String {
    case seasonPass = "seasonpass", settings, liveHistory = "livehistory", archivedPass = "archivedpass"

    static var requested: DebugScreen? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-RUXPScreen"), idx + 1 < args.count else { return nil }
        return DebugScreen(rawValue: args[idx + 1].lowercased())
    }
}
#endif


/// Three tabs. One full-screen cover hosts the entire workout flow
/// (active workout → completion) so the transition never crosses presentation hosts.
struct MainTabView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(ProgressionService.self) private var progression
    @State private var selectedTab: AppTab = Self.initialTab

    /// DEBUG: `-RUXPTab train|profile` opens on that tab for screenshots.
    private static var initialTab: AppTab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-RUXPTab"), idx + 1 < args.count {
            switch args[idx + 1] {
            case "train": return .train
            case "profile": return .profile
            default: break
            }
        }
        #endif
        return .home
    }

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.background)
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.08)
        let itemFont = UIFont.systemFont(ofSize: 10, weight: .medium)
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(Theme.textTertiary)
            item.normal.titleTextAttributes = [.font: itemFont, .foregroundColor: UIColor(Theme.textTertiary)]
            item.selected.iconColor = UIColor(Theme.accent)
            item.selected.titleTextAttributes = [.font: itemFont, .foregroundColor: UIColor(Theme.accent)]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.background)
        nav.shadowColor = UIColor.white.withAlphaComponent(0.08)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(Theme.textPrimary)
    }

    private var workoutFlowPresented: Binding<Bool> {
        Binding(
            get: { workoutManager.activeSession != nil || workoutManager.completedWorkoutID != nil },
            set: { if !$0 { workoutManager.completedWorkoutID = nil } }
        )
    }

    /// The season that just closed, shown once. Set in `ProgressionService.init`, before any view
    /// exists, so on a normal launch the recap is the first thing on screen.
    private var seasonRecap: Binding<SeasonRecord?> {
        Binding(
            get: { progression.pendingSeasonRecap },
            set: { if $0 == nil { progression.acknowledgeSeasonRecap() } }
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
        .fullScreenCover(item: seasonRecap) { record in
            SeasonRecapView(
                record: record,
                closed: SeasonCatalog.season(id: record.seasonID) ?? SeasonCatalog.earlyAdopters,
                next: progression.season
            )
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
            HUDBackground(glow: true)
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
