import SwiftUI

/// The moment that matters: XP earned, level progress, and the reminder that
/// thousands of other people trained tonight too. Details live below the fold.
struct WorkoutCompletionSheet: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WorkoutProcessor.self) private var processor
    @Environment(ProgressionService.self) private var progression
    @Environment(\.livePresence) private var presence
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue

    let workoutID: UUID
    @State private var session: WorkoutSession?
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?

    // Reveal choreography
    @State private var revealedAwards = 0
    @State private var showTotal = false
    @State private var displayedSeasonXP: Int?
    @State private var showLevelUp = false
    @State private var revealTask: Task<Void, Never>?

    private var reward: WorkoutRewardSummary? {
        guard let last = progression.lastReward, last.workoutID == workoutID else { return nil }
        return last
    }

    var body: some View {
        ZStack {
            HUDBackground(glow: true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    completionHeader
                    rewardSection
                    PrimaryButton(title: "CONTINUE") {
                        revealTask?.cancel()
                        workoutManager.completedWorkoutID = nil
                    }
                    .padding(.top, 4)

                    if let session {
                        detailsDivider
                        processingStatus
                        if let log = session.structuredLog {
                            exerciseList(log.exercises)
                            if let plan = session.plannedWorkout {
                                adherenceSection(plan: plan, log: log)
                            }
                            if !log.highlights.isEmpty { highlightsSection(log.highlights) }
                        }
                        healthRow(session)
                        shareButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            loadSession()
            runReveal()
        }
        .onChange(of: reward?.awards.count) { runReveal() }
        .onChange(of: processor.state) {
            if processor.state == .completed { loadSession() }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareImage {
                WorkoutShareSheet(items: [shareImage])
            }
        }
    }

    // MARK: - Header

    private var completionHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workout complete")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 10) {
                if let duration = session?.duration {
                    Text(formatDuration(duration)).font(Theme.Fonts.mono(12))
                }
                if let started = session?.startedAt {
                    Text(started, format: .dateTime.weekday(.wide).hour().minute()).font(Theme.Fonts.label)
                }
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Reward

    @ViewBuilder
    private var rewardSection: some View {
        if let reward {
            if reward.awards.isEmpty {
                noXPCard
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(reward.awards.enumerated()), id: \.element.id) { idx, award in
                        if idx < revealedAwards {
                            awardRow(award)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }

                    if showTotal {
                        totalBlock(reward)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                if processor.state.isProcessing && reward.prCount == 0 {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.accent).controlSize(.small)
                        Text("Checking your notes for PRs…")
                            .font(Theme.Fonts.ui(.caption))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("SAVED").eyebrow().foregroundStyle(Theme.textSecondary)
                Text("This workout is in your history.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard(cornerRadius: Theme.radiusLarge)
        }
    }

    private var noXPCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO XP THIS TIME").eyebrow().foregroundStyle(Theme.warning)
            Text("Sessions of \(Int(ProgressionRules.minimumWorkoutDuration / 60))+ minutes earn +\(ProgressionRules.workoutCompleteXP) XP, up to \(ProgressionRules.maxRewardedWorkoutsPerDay) a day.")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.textSecondary)
            Text("The workout is still saved.")
                .font(Theme.Fonts.ui(.caption))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(cornerRadius: Theme.radiusLarge)
    }

    private func awardRow(_ award: XPAward) -> some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: icon(for: award.reason))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.xp)
                    .frame(width: 30, height: 30)
                    .background(Theme.xpSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(award.label)
                    .font(Theme.Fonts.title(16))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Text("+\(award.amount.grouped) XP")
                .font(Theme.Fonts.mono(16, weight: .heavy))
                .foregroundStyle(Theme.xp)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    private func icon(for reason: XPReason) -> String {
        switch reason {
        case .workoutComplete: return "checkmark"
        case .eventBonus: return "bolt.fill"
        case .weeklyBonus: return "calendar"
        case .personalRecord: return "trophy.fill"
        }
    }

    private func totalBlock(_ reward: WorkoutRewardSummary) -> some View {
        let xp = displayedSeasonXP ?? reward.seasonXPAfter
        let p = LevelCurve.progress(seasonXP: xp)
        let live = presence?.snapshot ?? .unavailable
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("+\(reward.totalXP.grouped) XP")
                    .font(Theme.Fonts.number(36))
                    .foregroundStyle(Theme.xp)
                    .contentTransition(.numericText(value: Double(reward.totalXP)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                if reward.didLevelUp && showLevelUp {
                    SlantTag(text: "Level up")
                        .transition(.scale.combined(with: .opacity))
                }
            }

            XPBar(level: p.level, xpIntoLevel: p.xpIntoLevel, xpToNext: p.xpToNext)

            if reward.didLevelUp {
                HStack(spacing: 8) {
                    Text("LVL \(reward.levelBefore)").font(Theme.Fonts.title(18)).foregroundStyle(Theme.textSecondary)
                    Image(systemName: "arrow.right").font(Theme.Fonts.ui(.caption, weight: .bold)).foregroundStyle(Theme.textTertiary)
                    Text("LVL \(reward.levelAfter)")
                        .font(Theme.Fonts.title(18))
                        .foregroundStyle(Theme.accent)
                        .scaleEffect(showLevelUp ? 1 : 0.8)
                }
            }

            if reward.didLevelUp, showLevelUp {
                let unlocked = SeasonPassCatalog.newlyUnlocked(from: reward.levelBefore, to: reward.levelAfter, season: progression.season)
                if !unlocked.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(unlocked) { r in
                            HStack(spacing: 8) {
                                Image(systemName: "lock.open.fill")
                                    .font(Theme.Fonts.ui(.caption, weight: .bold))
                                    .foregroundStyle(Theme.violet)
                                Text("TIER \(r.tier) UNLOCKED").eyebrow().foregroundStyle(Theme.violet)
                                Spacer()
                                Text(r.name)
                                    .font(Theme.Fonts.mono(12))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                        Text("Equip it in Profile → Season Pass.")
                            .font(Theme.Fonts.ui(.caption))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if live.isAvailable {
                Divider().overlay(Theme.divider)
                HStack(spacing: 8) {
                    LiveDot(label: nil, size: 7)
                    Text(live.workoutsToday <= 1 ? "You're the first to train today." : live.trainedTodayLine)
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .stroke(Theme.borderNeon, lineWidth: 1)
        )
    }

    // MARK: - Reveal choreography

    private func runReveal() {
        guard let reward, !reward.awards.isEmpty else { return }
        let target = reward.awards.count
        guard revealedAwards < target || !showTotal else { return }
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            while revealedAwards < target, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(revealedAwards == 0 ? 200 : 380))
                withAnimation(Theme.Motion.reveal) { revealedAwards += 1 }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            guard !Task.isCancelled else { return }
            if !showTotal {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(Theme.Motion.reveal) {
                    showTotal = true
                    displayedSeasonXP = reward.seasonXPBefore
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            withAnimation(.easeOut(duration: 0.9)) { displayedSeasonXP = reward.seasonXPAfter }
            if reward.didLevelUp, !showLevelUp {
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(Theme.Motion.pop) { showLevelUp = true }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    // MARK: - Details

    private var detailsDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.divider).frame(height: 1)
            Text("DETAILS").eyebrow().foregroundStyle(Theme.textTertiary)
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var processingStatus: some View {
        switch processor.state {
        case .processing(let stage):
            HStack(spacing: 12) {
                ProgressView().tint(Theme.accent)
                Text(stage).font(Theme.Fonts.ui(.subheadline)).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Couldn't parse your notes", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Fonts.ui(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.error)
                Text(message).font(Theme.Fonts.ui(.caption)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()

        case .queued:
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash").foregroundStyle(Theme.warning)
                Text("Queued — your notes will be parsed when online")
                    .font(Theme.Fonts.ui(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeCard()

        default:
            if let session, session.moments.isEmpty {
                Text("No voice notes this session. Talk through your sets next time and RUXP writes the log.")
                    .font(Theme.Fonts.ui(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func exerciseList(_ exercises: [ExerciseGroup]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXERCISES").eyebrow().foregroundStyle(Theme.textSecondary)

            ForEach(exercises) { exercise in
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.exerciseName)
                        .font(Theme.Fonts.title(15))
                        .foregroundStyle(Theme.textPrimary)

                    ForEach(Array(exercise.sets.enumerated()), id: \.offset) { idx, set in
                        HStack {
                            Text("Set \(idx + 1)")
                                .font(Theme.Fonts.ui(.caption))
                                .foregroundStyle(Theme.textTertiary)
                                .frame(width: 44, alignment: .leading)
                            if let reps = set.reps {
                                Text("\(reps) reps").font(Theme.Fonts.ui(.caption, mono: true)).foregroundStyle(Theme.textSecondary)
                            }
                            if let weight = set.weight, weight > 0 {
                                Text("@ \(formatWeight(weight)) \(weightUnit)").font(Theme.Fonts.ui(.caption, mono: true)).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                        }
                    }

                    if exercises.last?.id != exercise.id {
                        Divider().overlay(Theme.divider)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    private func adherenceSection(plan: PlannedWorkout, log: StructuredLog) -> some View {
        let result = PlanAdherenceCalculator.compute(plan: plan, log: log)
        return VStack(alignment: .leading, spacing: 8) {
            Text("PLAN CHECK").eyebrow().foregroundStyle(Theme.textSecondary)

            ForEach(result.entries) { entry in
                HStack(spacing: 8) {
                    Image(systemName: adherenceIcon(entry.status))
                        .font(Theme.Fonts.ui(.caption))
                        .foregroundStyle(adherenceColor(entry.status))
                    Text(entry.plannedName).font(Theme.Fonts.ui(.subheadline)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let target = entry.targetSets {
                        Text("\(entry.actualSets)/\(target) sets").font(Theme.Fonts.ui(.caption, mono: true)).foregroundStyle(Theme.textSecondary)
                    } else if entry.actualSets > 0 {
                        Text("\(entry.actualSets) sets").font(Theme.Fonts.ui(.caption, mono: true)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            if !result.extras.isEmpty {
                Text("Off-plan: \(result.extras.joined(separator: ", "))")
                    .font(Theme.Fonts.ui(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    private func adherenceIcon(_ status: PlanAdherenceStatus) -> String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .skipped: "circle"
        }
    }

    private func adherenceColor(_ status: PlanAdherenceStatus) -> Color {
        switch status {
        case .completed: Theme.accent
        case .partial: Theme.warning
        case .skipped: Theme.textSecondary
        }
    }

    private func highlightsSection(_ highlights: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HIGHLIGHTS").eyebrow().foregroundStyle(Theme.textSecondary)
            ForEach(highlights, id: \.self) { highlight in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(Theme.accent)
                    Text(highlight).font(Theme.Fonts.ui(.subheadline)).foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    @ViewBuilder
    private func healthRow(_ session: WorkoutSession) -> some View {
        let hr = session.averageHeartRate ?? 0
        let cal = session.activeCalories ?? 0
        let volume = computeVolume(session)
        if hr > 0 || cal > 0 || volume > 0 {
            HStack(spacing: 10) {
                if volume > 0 { StatTile(title: "Volume", value: "\(formatVolume(volume)) \(weightUnit)", accent: true) }
                if hr > 0 { StatTile(title: "Avg BPM", value: "\(Int(hr))") }
                if cal > 0 { StatTile(title: "Calories", value: "\(Int(cal))") }
            }
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if session?.structuredLog != nil {
            SecondaryButton(title: "SHARE WORKOUT", icon: "square.and.arrow.up") {
                generateShareImage()
                showShareSheet = true
            }
        }
    }

    // MARK: - Helpers

    private func generateShareImage() {
        guard let session else { return }
        let renderer = ImageRenderer(content:
            ShareableWorkoutCard(session: session, weightUnit: weightUnit, reward: reward,
                                 title: SeasonPassCatalog.loadout(for: progression.progress, season: progression.season).title)
                .frame(width: 390)
        )
        renderer.scale = 3.0
        shareImage = renderer.uiImage
    }

    private func loadSession() {
        session = workoutManager.workoutStore.loadSession(id: workoutID)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hrs = total / 3600, mins = (total % 3600) / 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }

    private func computeVolume(_ session: WorkoutSession) -> Double {
        session.structuredLog?.exercises.reduce(0.0) { total, group in
            total + group.sets.reduce(0.0) { $0 + (($1.weight ?? 0) * Double($1.reps ?? 0)) }
        } ?? 0
    }

    private func formatVolume(_ volume: Double) -> String {
        volume >= 1000 ? String(format: "%.1fk", volume / 1000) : "\(Int(volume))"
    }

    private func formatWeight(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(weight))" : String(format: "%.1f", weight)
    }
}

extension WorkoutProcessingState {
    var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }
}

// MARK: - Shareable Card (rendered to image)

private struct ShareableWorkoutCard: View {
    let session: WorkoutSession
    let weightUnit: String
    let reward: WorkoutRewardSummary?
    let title: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                RUXPWordmark(size: 22, color: Theme.textPrimary, glitch: false)
                Spacer()
                Text(session.startedAt, format: .dateTime.month(.wide).day().year())
                    .font(Theme.Fonts.label)
                    .foregroundStyle(.white.opacity(0.6))
            }

            if let reward, reward.totalXP > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("+\(reward.totalXP.grouped) XP").font(Theme.Fonts.number(30)).foregroundStyle(Theme.xp)
                    Text("LVL \(reward.levelAfter)").font(Theme.Fonts.title(16)).foregroundStyle(.white.opacity(0.7))
                    if let title {
                        Text(title).font(Theme.Fonts.mono(12)).foregroundStyle(Theme.violet)
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.15))

            if let duration = session.duration {
                HStack(spacing: 20) {
                    shareStatItem(value: formatDuration(duration), label: "Duration")
                    if let exercises = session.structuredLog?.exercises {
                        shareStatItem(value: "\(exercises.count)", label: "Exercises")
                        shareStatItem(value: "\(exercises.reduce(0) { $0 + $1.sets.count })", label: "Sets")
                    }
                }
            }

            if let exercises = session.structuredLog?.exercises {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(exercises) { exercise in
                        HStack {
                            Text(exercise.exerciseName).font(Theme.Fonts.ui(.subheadline)).foregroundStyle(.white)
                            Spacer()
                            Text("\(exercise.sets.count) sets").font(Theme.Fonts.ui(.caption)).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.accent.opacity(0.3), lineWidth: 1))
    }

    private func shareStatItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.Fonts.ui(.headline, mono: true)).foregroundStyle(.white)
            Text(label).font(Theme.Fonts.ui(.caption2)).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hrs = total / 3600, mins = (total % 3600) / 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }
}

// MARK: - Activity Sheet

private struct WorkoutShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
