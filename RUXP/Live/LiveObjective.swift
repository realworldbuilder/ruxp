import SwiftUI

// MARK: - Models

/// One player's share of tonight's total. A real Game Center alias; the floor reads these.
struct SessionContributor: Identifiable, Equatable {
    /// `GKPlayer.gamePlayerID`, session-scoped for strangers; never persisted.
    let id: String
    let alias: String
    let volumeLB: Double
}

/// The shared objective right now: how much the session has moved together, out of the target.
struct SessionObjectiveState: Equatable {
    var targetLB: Double
    var totalLB: Double
    var contributors: Int
    /// False until the source has a real number (Game Center signed in and one read landed).
    var isAvailable: Bool
    var updatedAt: Date?
    /// Top contributors this window, highest first.
    var leaders: [SessionContributor]

    static func unavailable(targetLB: Double) -> SessionObjectiveState {
        SessionObjectiveState(targetLB: targetLB, totalLB: 0, contributors: 0, isAvailable: false, updatedAt: nil, leaders: [])
    }

    var fraction: Double { targetLB > 0 ? min(1, totalLB / targetLB) : 0 }
    var isMet: Bool { targetLB > 0 && totalLB >= targetLB }
}

// MARK: - Provider

/// "How much have we moved together tonight?" The phone answers with a Game Center recurring
/// board (`GameCenterSessionObjective`); a backend replaces it with the same shape. Views only
/// ever see this protocol.
@MainActor
protocol SessionObjectiveProviding: AnyObject {
    var state: SessionObjectiveState { get }
    /// Fired after every change. Assigned once in RUXPApp.init; chain there.
    var onStateChanged: ((SessionObjectiveState) -> Void)? { get set }
    func start()
    func stop()
    /// The local player's cumulative lb for this session's window. Best-score semantics: pass
    /// the sum, never a delta.
    func submit(volumeLB: Double, for event: LiveEvent) async
}

// MARK: - Environment

private struct SessionObjectiveKey: EnvironmentKey {
    static let defaultValue: (any SessionObjectiveProviding)? = nil
}

extension EnvironmentValues {
    var liveObjective: (any SessionObjectiveProviding)? {
        get { self[SessionObjectiveKey.self] }
        set { self[SessionObjectiveKey.self] = newValue }
    }
}

// MARK: - Formatting

extension Double {
    /// "742,391" for volume in lb. Whole pounds only.
    var groupedLB: String { Int(rounded()).grouped }

    /// "742K", "1.2M", "18,420": the compact form for tight rows.
    var compactLB: String {
        if self >= 1_000_000 { return String(format: "%.1fM", self / 1_000_000).replacingOccurrences(of: ".0M", with: "M") }
        if self >= 100_000 { return "\(Int((self / 1000).rounded()))K" }
        return groupedLB
    }
}
