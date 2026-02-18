import SwiftUI

/// Watch-specific theme tokens that match the iOS Theme.swift
/// OpenAI-inspired design: dark bg, green accent, clean and premium
enum WatchTheme {
    // MARK: - Colors
    static let accent = Color(red: 0.063, green: 0.639, blue: 0.498)       // #10a37f
    static let accentBright = Color(red: 0.082, green: 0.729, blue: 0.569) // brighter for watch visibility
    static let background = Color(red: 0.051, green: 0.051, blue: 0.051)   // #0d0d0d
    static let surface = Color(red: 0.102, green: 0.102, blue: 0.102)      // #1a1a1a
    static let surfaceElevated = Color(red: 0.165, green: 0.165, blue: 0.165) // #2a2a2a
    
    static let textPrimary = Color(red: 0.925, green: 0.925, blue: 0.945)  // #ececf1
    static let textSecondary = Color(red: 0.557, green: 0.557, blue: 0.627) // #8e8ea0
    static let textTertiary = Color(red: 0.337, green: 0.345, blue: 0.412) // #565869
    
    // MARK: - Gradients
    static let accentGradient: [Color] = [
        Color(red: 0.063, green: 0.639, blue: 0.498), // #10a37f
        Color(red: 0.043, green: 0.478, blue: 0.380)  // darker green
    ]
    
    static let recordingGradient: [Color] = [
        Color(red: 0.082, green: 0.800, blue: 0.569), // bright recording green
        Color(red: 0.043, green: 0.600, blue: 0.400)
    ]
    
    static let dangerGradient: [Color] = [
        Color(red: 0.937, green: 0.267, blue: 0.267), // #ef4444
        Color(red: 0.800, green: 0.200, blue: 0.200)
    ]
}
