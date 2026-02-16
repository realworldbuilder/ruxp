import SwiftUI

struct TrainerSoulEditor: View {
    @Binding var soul: TrainerSoul
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TrainerSoul = .default

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Goal
                Section {
                    Picker("Primary Goal", selection: $draft.fitnessGoal) {
                        ForEach(TrainerSoul.FitnessGoal.allCases) { goal in
                            Text(goal.rawValue).tag(goal)
                        }
                    }
                } header: {
                    Text("What are you training for?")
                } footer: {
                    Text(draft.fitnessGoal.promptFragment.prefix(80) + "...")
                        .font(.caption2)
                }

                // MARK: - Experience
                Section("Experience Level") {
                    Picker("Level", selection: $draft.experienceLevel) {
                        ForEach(TrainerSoul.ExperienceLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: - Training Style
                Section("Training Style") {
                    Picker("Style", selection: $draft.trainingStyle) {
                        ForEach(TrainerSoul.TrainingStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: - Coaching Tone
                Section {
                    ForEach(TrainerSoul.CoachingTone.allCases) { tone in
                        Button {
                            draft.coachingTone = tone
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tone.rawValue)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(tonePreview(tone))
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if draft.coachingTone == tone {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Coaching Voice")
                }

                // MARK: - Custom Prompt
                Section {
                    TextEditor(text: $draft.customPrompt)
                        .frame(minHeight: 100)
                        .font(.subheadline)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text("Custom Instructions")
                } footer: {
                    Text("Add anything specific — injuries to work around, favorite exercises, programming preferences, or your own coaching philosophy. This overrides everything above when set.")
                }

                // MARK: - Preview
                Section("Prompt Preview") {
                    Text(draft.systemPromptFragment)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }

                // MARK: - Reset
                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        draft = .default
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Trainer Soul")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        soul = draft
                        draft.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            draft = soul
        }
    }

    private func tonePreview(_ tone: TrainerSoul.CoachingTone) -> String {
        switch tone {
        case .drill: return "\"No excuses. Get under that bar.\""
        case .bro: return "\"Bro that PR was insane, let's go!\""
        case .science: return "\"Your volume is 12% above MRV this week.\""
        case .chill: return "\"Nice session. Rest up, you earned it.\""
        case .stoic: return "\"The iron doesn't lie. Neither should you.\""
        }
    }
}
