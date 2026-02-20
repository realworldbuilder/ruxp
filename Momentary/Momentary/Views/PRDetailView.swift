import SwiftUI

struct PRDetailView: View {
    let personalRecords: [String: PRRecord]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue
    @State private var showAllRecords = false
    
    private var sortedPRs: [PRRecord] {
        personalRecords.values.sorted { $0.weight > $1.weight }
    }
    
    private var compoundPRs: [PRRecord] {
        personalRecords.values.filter { $0.isCompound }.sorted { $0.weight > $1.weight }
    }
    
    private var topThreePRs: [PRRecord] {
        // Show top 3 compound PRs, or fall back to all PRs if no compounds
        let prsToUse = compoundPRs.isEmpty ? sortedPRs : compoundPRs
        return Array(prsToUse.prefix(3))
    }
    
    private var allRecordsForExpansion: [PRRecord] {
        sortedPRs
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Personal Records")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    
                    Text("\(personalRecords.count) achievements unlocked")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 40)
                
                // Podium - Top 3 PRs (Compound PRs or fallback to all)
                if !topThreePRs.isEmpty {
                    podiumSection
                        .padding(.horizontal)
                }
                
                // All Records Section (Expandable)
                if !allRecordsForExpansion.isEmpty {
                    allRecordsSection
                        .padding(.horizontal)
                }
                
                Spacer(minLength: 80)
            }
        }
        .background(Theme.background)
        .navigationBarHidden(true)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Theme.surface.opacity(0.8), in: Circle())
                    .backdrop(Material.ultraThinMaterial)
            }
            .padding(.top, 60)
            .padding(.trailing, 20)
        }
    }
    
    // MARK: - Podium Section
    
    private var podiumSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("🏆 Hall of Fame")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                
                if !compoundPRs.isEmpty {
                    Text("Top Compound Lifts")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            
            // Top 3 in podium arrangement: 2nd, 1st, 3rd
            HStack(alignment: .bottom, spacing: 12) {
                // 2nd Place (left)
                if topThreePRs.count > 1 {
                    podiumCard(pr: topThreePRs[1], position: 2, accentColor: Color(hex: "C0C0C0"))
                        .frame(maxWidth: .infinity)
                }
                
                // 1st Place (center, taller)
                if !topThreePRs.isEmpty {
                    podiumCard(pr: topThreePRs[0], position: 1, accentColor: Color(hex: "FFD700"))
                        .frame(maxWidth: .infinity)
                        .scaleEffect(1.1)
                        .zIndex(1)
                }
                
                // 3rd Place (right)
                if topThreePRs.count > 2 {
                    podiumCard(pr: topThreePRs[2], position: 3, accentColor: Color(hex: "CD7F32"))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    private func podiumCard(pr: PRRecord, position: Int, accentColor: Color) -> some View {
        VStack(spacing: 12) {
            // Medal
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                
                Text("\(position)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(accentColor)
            }
            
            // Weight - Main attraction
            Text("\(Int(pr.weight))")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            
            Text(weightUnit)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            
            // Exercise name
            Text(pr.exercise)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            // Reps if available
            if let reps = pr.reps {
                Text("\(reps) rep\(reps == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            
            // Date
            Text(pr.date, format: .dateTime.month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            
            // Improvement delta
            if let improvement = pr.improvement, improvement > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                    Text("+\(Int(improvement))")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.green)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.1),
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.radiusMedium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(accentColor.opacity(0.3), lineWidth: 2)
        )
    }
    
    // MARK: - All Records Section (Expandable)
    
    private var allRecordsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showAllRecords.toggle()
                }
            }) {
                HStack {
                    Text("All Records")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    
                    Spacer()
                    
                    Image(systemName: showAllRecords ? "chevron.up" : "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(showAllRecords ? 0 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            if showAllRecords {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(allRecordsForExpansion) { pr in
                        prCardWithCompoundIndicator(pr: pr)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
    
    private func prCard(pr: PRRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Exercise name
            Text(pr.exercise)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // Weight prominently displayed
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(pr.weight))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                
                Text(weightUnit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            
            // Reps and date
            VStack(alignment: .leading, spacing: 2) {
                if let reps = pr.reps {
                    Text("\(reps) rep\(reps == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                
                Text(pr.date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            
            // Improvement delta
            if let improvement = pr.improvement, improvement > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                    Text("+\(Int(improvement)) \(weightUnit)")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.green)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 120)
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.1),
                    Color.white.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.radiusMedium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func prCardWithCompoundIndicator(pr: PRRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Exercise name with compound indicator
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pr.exercise)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // Compound/Isolation indicator
                    Text(pr.isCompound ? "Compound" : "Isolation")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(pr.isCompound ? Theme.accent : Theme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            (pr.isCompound ? Theme.accent : Color.gray)
                                .opacity(0.15),
                            in: Capsule()
                        )
                }
                
                Spacer()
            }
            
            // Weight prominently displayed
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(pr.weight))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                
                Text(weightUnit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            
            // Reps and date
            VStack(alignment: .leading, spacing: 2) {
                if let reps = pr.reps {
                    Text("\(reps) rep\(reps == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                
                Text(pr.date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            
            // Improvement delta
            if let improvement = pr.improvement, improvement > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                    Text("+\(Int(improvement)) \(weightUnit)")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.green)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 130)
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(pr.isCompound ? 0.12 : 0.08),
                    Color.white.opacity(pr.isCompound ? 0.06 : 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.radiusMedium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(
                    pr.isCompound ? Theme.accent.opacity(0.3) : Color.white.opacity(0.2),
                    lineWidth: pr.isCompound ? 1.5 : 1
                )
        )
    }
}

#Preview {
    let samplePRs: [String: PRRecord] = [
        "Bench Press": PRRecord(
            exercise: "Bench Press",
            weight: 315,
            reps: 3,
            date: Date(),
            previousWeight: 295
        ),
        "Squat": PRRecord(
            exercise: "Squat",
            weight: 405,
            reps: 1,
            date: Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date(),
            previousWeight: 385
        ),
        "Deadlift": PRRecord(
            exercise: "Deadlift",
            weight: 495,
            reps: 1,
            date: Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? Date(),
            previousWeight: 475
        ),
        "Overhead Press": PRRecord(
            exercise: "Overhead Press",
            weight: 185,
            reps: 5,
            date: Calendar.current.date(byAdding: .day, value: -15, to: Date()) ?? Date(),
            previousWeight: 175
        ),
        "Pull-up": PRRecord(
            exercise: "Pull-up",
            weight: 45,
            reps: 8,
            date: Calendar.current.date(byAdding: .day, value: -20, to: Date()) ?? Date(),
            previousWeight: 25
        )
    ]
    
    return PRDetailView(personalRecords: samplePRs)
}