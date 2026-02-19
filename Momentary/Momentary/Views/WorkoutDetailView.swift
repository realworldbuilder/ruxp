import SwiftUI

struct WorkoutDetailView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(WorkoutProcessor.self) private var processor
    let workoutID: UUID

    @State private var session: WorkoutSession?
    @State private var copyFeedbackTrigger = false
    @State private var isEditing = false
    @AppStorage("weightUnit") private var weightUnit: String = WeightUnit.lbs.rawValue

    private var isProcessing: Bool {
        if case .processing = processor.state { return true }
        return false
    }

    private var isFailed: Bool {
        if case .failed = processor.state { return true }
        return false
    }

    private var canAnalyze: Bool {
        guard let session else { return false }
        return !session.moments.isEmpty && session.structuredLog == nil && !isProcessing && !isFailed
    }

    var body: some View {
        Group {
            if let session { detailContent(session) }
            else { ProgressView() }
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .onAppear { session = workoutManager.workoutStore.loadSession(id: workoutID) }
        .onChange(of: processor.state) {
            if processor.state == .completed || isFailed {
                session = workoutManager.workoutStore.loadSession(id: workoutID)
            }
        }
        .toolbar {
            if canAnalyze {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await analyzeWorkout() } } label: {
                        Label("Analyze", systemImage: "sparkles")
                    }
                }
            }
            if session?.structuredLog != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if isEditing { saveEdits() }
                        withAnimation { isEditing.toggle() }
                    } label: { Text(isEditing ? "Done" : "Edit") }
                }
            }
        }
        .sensoryFeedback(.success, trigger: copyFeedbackTrigger)
    }

    // MARK: - Detail Content

    private func detailContent(_ session: WorkoutSession) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                heroSection(session)
                aiStatusSection()
                if let log = session.structuredLog {
                    exerciseCards(log.exercises)
                    if !log.summary.isEmpty { summaryCard(log.summary) }
                    if !log.highlights.isEmpty { highlightsCard(log.highlights) }
                    if !log.ambiguities.isEmpty { ambiguitiesCard(log.ambiguities) }
                }
                if let pack = session.contentPack { contentPackCards(pack) }
                if !session.stories.isEmpty { insightsCards(session.stories) }
                if !session.moments.isEmpty { transcriptCard(session.moments) }
            }
            .padding(.horizontal).padding(.bottom, 24)
        }
        .background(Theme.background)
    }

    // MARK: - Hero

    private func heroSection(_ session: WorkoutSession) -> some View {
        VStack(spacing: 12) {
            Text(session.startedAt, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.title3.bold())
            HStack(spacing: 20) {
                if let duration = session.duration {
                    statPill(icon: "clock", value: formatDuration(duration), label: "Duration")
                }
                let exercises = session.structuredLog?.exercises ?? []
                if !exercises.isEmpty {
                    statPill(icon: "figure.strengthtraining.traditional", value: "\(exercises.count)", label: "Exercises")
                    statPill(icon: "repeat", value: "\(exercises.reduce(0) { $0 + $1.sets.count })", label: "Sets")
                }
            }
            let volume = computeVolume(session)
            if volume > 0 {
                Text("\(formatVolume(volume)) \(weightUnit) total volume")
                    .font(.subheadline.bold()).foregroundStyle(Theme.accent)
            }

            // Apple Health data
            let hasHealth = session.averageHeartRate != nil || session.activeCalories != nil
            if hasHealth {
                Divider().overlay(Theme.divider)
                HStack(spacing: 24) {
                    if let hr = session.averageHeartRate, hr > 0 {
                        VStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text("\(Int(hr))")
                                .font(.headline.monospacedDigit())
                            Text("Avg BPM")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let cal = session.activeCalories, cal > 0 {
                        VStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("\(Int(cal))")
                                .font(.headline.monospacedDigit())
                            Text("Calories")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .themeCard(cornerRadius: Theme.radiusLarge)
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - AI Status

    @ViewBuilder
    private func aiStatusSection() -> some View {
        if isProcessing, case .processing(let stage) = processor.state {
            HStack(spacing: 10) {
                ProgressView()
                Text(stage).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).themeCard()
        }

        if case .failed(let message) = processor.state {
            VStack(alignment: .leading, spacing: 8) {
                Label("Analysis Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold()).foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button { Task { await analyzeWorkout() } } label: {
                    Label("Retry", systemImage: "arrow.clockwise").font(.subheadline.bold()).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red)
            }
            .themeCard()
        }

        if processor.state == .queued {
            HStack(spacing: 10) {
                Image(systemName: "clock.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Queued for Processing").font(.subheadline.bold())
                    Text("Will process automatically when back online.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).themeCard()
        }
    }

    // MARK: - Exercise Cards

    @ViewBuilder
    private func exerciseCards(_ exercises: [ExerciseGroup]) -> some View {
        if isEditing { editableExerciseCards() }
        else { readOnlyExerciseCards(exercises) }
    }

    private func readOnlyExerciseCards(_ exercises: [ExerciseGroup]) -> some View {
        ForEach(exercises) { exercise in
            VStack(alignment: .leading, spacing: 10) {
                Text(exercise.exerciseName).font(.headline)
                setsTableHeader
                ForEach(exercise.sets) { set in
                    HStack {
                        Text("\(set.setNumber)").frame(width: 36, alignment: .leading)
                        Text(set.reps.map { "\($0)" } ?? "—").frame(width: 50, alignment: .center)
                            .foregroundStyle(set.reps == nil ? .tertiary : .primary)
                        Text(set.weight.map { "\($0, specifier: "%.0f") \(set.weightUnit.rawValue)" } ?? "—")
                            .frame(minWidth: 60, alignment: .center)
                            .foregroundStyle(set.weight == nil ? .tertiary : .primary)
                        Spacer()
                        if let notes = set.notes {
                            Text(notes).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .font(.subheadline)
                }
                if let notes = exercise.notes {
                    Text(notes).font(.caption).foregroundStyle(.secondary)
                }
            }
            .themeCard()
        }
    }

    private var setsTableHeader: some View {
        HStack {
            Text("Set").frame(width: 36, alignment: .leading)
            Text("Reps").frame(width: 50, alignment: .center)
            Text("Weight").frame(minWidth: 60, alignment: .center)
            Spacer()
        }
        .font(.caption.bold()).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func editableExerciseCards() -> some View {
        let exerciseCount = session?.structuredLog?.exercises.count ?? 0
        ForEach(0..<exerciseCount, id: \.self) { exerciseIndex in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Exercise Name", text: Binding(
                        get: { session?.structuredLog?.exercises[exerciseIndex].exerciseName ?? "" },
                        set: { session?.structuredLog?.exercises[exerciseIndex].exerciseName = $0 }
                    ))
                    .font(.headline).textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        withAnimation { deleteExercise(at: exerciseIndex) }
                    } label: { Image(systemName: "trash").font(.caption) }
                    .buttonStyle(.borderless)
                }

                setsTableHeader

                let setCount = session?.structuredLog?.exercises[exerciseIndex].sets.count ?? 0
                ForEach(0..<setCount, id: \.self) { setIndex in
                    HStack(spacing: 8) {
                        Text("\(setIndex + 1)").frame(width: 36, alignment: .leading).font(.subheadline)
                        TextField("—", text: Binding(
                            get: { session?.structuredLog?.exercises[exerciseIndex].sets[setIndex].reps.map { "\($0)" } ?? "" },
                            set: { session?.structuredLog?.exercises[exerciseIndex].sets[setIndex].reps = Int($0) }
                        ))
                        .frame(width: 50).multilineTextAlignment(.center).textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad).font(.subheadline)

                        TextField("—", text: Binding(
                            get: { session?.structuredLog?.exercises[exerciseIndex].sets[setIndex].weight.map { String(format: "%.0f", $0) } ?? "" },
                            set: { session?.structuredLog?.exercises[exerciseIndex].sets[setIndex].weight = Double($0) }
                        ))
                        .frame(width: 70).multilineTextAlignment(.center).textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad).font(.subheadline)

                        Spacer()

                        Button(role: .destructive) {
                            withAnimation { deleteSet(exerciseIndex: exerciseIndex, setIndex: setIndex) }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red).font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button { withAnimation { addSet(exerciseIndex: exerciseIndex) } } label: {
                    Label("Add Set", systemImage: "plus.circle").font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .themeCard()
        }
    }

    // MARK: - Summary / Highlights / Ambiguities

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Summary", systemImage: "text.quote").font(.subheadline.bold()).foregroundStyle(.secondary)
            Text(summary).font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading).themeCard()
    }

    private func highlightsCard(_ highlights: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Highlights", systemImage: "star.fill").font(.subheadline.bold()).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(highlights, id: \.self) { highlight in
                    Text(highlight).font(.caption)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.accentSubtle, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).themeCard()
    }

    private func ambiguitiesCard(_ ambiguities: [Ambiguity]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ambiguities) { ambiguity in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ambiguity.field).font(.caption.bold())
                        Text("Heard: \"\(ambiguity.rawTranscript)\"").font(.caption).foregroundStyle(.secondary)
                        Text("Best guess: \(ambiguity.bestGuess)").font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Ambiguities (\(ambiguities.count))", systemImage: "questionmark.circle")
                .font(.subheadline.bold()).foregroundStyle(.orange)
        }
        .themeCard()
    }

    // MARK: - Content Pack

    private func contentPackCards(_ pack: ContentPack) -> some View {
        VStack(spacing: 12) {
            if !pack.igCaptions.isEmpty { contentDisclosure("Instagram Captions", icon: "camera", items: pack.igCaptions) }
            if !pack.tweetThread.isEmpty { contentDisclosure("Tweet Thread", icon: "bubble.left", items: pack.tweetThread) }
            if !pack.reelScript.isEmpty { contentDisclosure("Reel Script", icon: "film", items: [pack.reelScript]) }
            if !pack.storyCards.isEmpty { storyCardsDisclosure(pack.storyCards) }
            if !pack.hooks.isEmpty { contentDisclosure("Hooks", icon: "link", items: pack.hooks) }
            if !pack.takeaways.isEmpty { contentDisclosure("Takeaways", icon: "lightbulb", items: pack.takeaways) }
        }
    }

    private func contentDisclosure(_ title: String, icon: String, items: [String]) -> some View {
        DisclosureGroup {
            ForEach(items, id: \.self) { item in
                Text(item).font(.caption).textSelection(.enabled)
                    .contextMenu {
                        Button { UIPasteboard.general.string = item; copyFeedbackTrigger.toggle() } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        ShareLink(item: item)
                    }
                    .padding(.vertical, 2)
            }
        } label: { Label(title, systemImage: icon).font(.subheadline.bold()) }
        .themeCard()
    }

    private func storyCardsDisclosure(_ cards: [StoryCard]) -> some View {
        DisclosureGroup {
            ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title).font(.subheadline.bold())
                    Text(card.body).font(.caption)
                }
                .padding(.vertical, 4)
            }
        } label: { Label("Story Cards", systemImage: "rectangle.stack").font(.subheadline.bold()) }
        .themeCard()
    }

    // MARK: - Insights / Transcript

    private func insightsCards(_ stories: [InsightStory]) -> some View {
        ForEach(stories) { story in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(story.title).font(.subheadline.bold())
                    Spacer()
                    Text(story.type.rawValue).font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.accentSubtle, in: Capsule())
                }
                Text(story.body).font(.caption).foregroundStyle(.secondary)
            }
            .themeCard()
        }
    }

    private func transcriptCard(_ moments: [Moment]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(moments) { moment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(moment.transcript).font(.body)
                        HStack(spacing: 4) {
                            Text(moment.timestamp, style: .time).font(.caption).foregroundStyle(.secondary)
                            if moment.source == .watch {
                                Image(systemName: "applewatch").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    if moment.id != moments.last?.id {
                        Divider().overlay(Theme.divider)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Transcript (\(moments.count) \(moments.count == 1 ? "moment" : "moments"))", systemImage: "waveform").font(.subheadline.bold())
        }
        .themeCard()
    }

    // MARK: - Actions

    private func analyzeWorkout() async {
        guard let session = workoutManager.workoutStore.loadSession(id: workoutID) else { return }
        await processor.processWorkout(session)
    }

    private func saveEdits() {
        guard var updated = session else { return }
        if var log = updated.structuredLog {
            for i in log.exercises.indices {
                for j in log.exercises[i].sets.indices {
                    log.exercises[i].sets[j].setNumber = j + 1
                }
            }
            updated.structuredLog = log
        }
        workoutManager.workoutStore.saveSession(updated)
        session = updated
    }

    private func addSet(exerciseIndex: Int) {
        guard var log = session?.structuredLog else { return }
        log.exercises[exerciseIndex].sets.append(ExerciseSet(setNumber: log.exercises[exerciseIndex].sets.count + 1))
        session?.structuredLog = log
    }

    private func deleteExercise(at index: Int) {
        session?.structuredLog?.exercises.remove(at: index)
    }

    private func deleteSet(exerciseIndex: Int, setIndex: Int) {
        guard var log = session?.structuredLog else { return }
        log.exercises[exerciseIndex].sets.remove(at: setIndex)
        for i in log.exercises[exerciseIndex].sets.indices {
            log.exercises[exerciseIndex].sets[i].setNumber = i + 1
        }
        session?.structuredLog = log
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        return hrs > 0 ? "\(hrs)h \(mins)m" : "\(mins)m"
    }

    private func computeVolume(_ session: WorkoutSession) -> Double {
        (session.structuredLog?.exercises ?? []).reduce(0.0) { total, group in
            total + group.sets.reduce(0.0) { $0 + Double($1.reps ?? 0) * ($1.weight ?? 0) }
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        volume >= 1000 ? String(format: "%.1fk", volume / 1000) : String(format: "%.0f", volume)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let fitWidth = min(subview.sizeThatFits(.unspecified).width, maxWidth)
            let size = subview.sizeThatFits(ProposedViewSize(width: fitWidth, height: nil))
            if x + fitWidth > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(width: fitWidth, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += fitWidth + spacing
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let fitWidth = min(subview.sizeThatFits(.unspecified).width, maxWidth)
            let size = subview.sizeThatFits(ProposedViewSize(width: fitWidth, height: nil))
            if x + fitWidth > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += fitWidth + spacing
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
