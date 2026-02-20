import Foundation

/// The Trainer's "soul" — user-editable persona and fitness context that shapes
/// all AI responses (Trainer chat, Insights, workout analysis).
/// Think of it like SOUL.md for the AI coach living inside Mind2Muscle.
struct TrainerSoul: Codable, Equatable {
    var fitnessGoal: FitnessGoal
    var experienceLevel: ExperienceLevel
    var trainingStyle: TrainingStyle
    var coachingTone: CoachingTone
    var trainingSplit: TrainingSplit
    var customPrompt: String  // free-text "soul" override — the power-user field

    // MARK: - Enums

    enum FitnessGoal: String, Codable, CaseIterable, Identifiable {
        case buildMuscle = "Build Muscle"
        case loseFat = "Lose Fat"
        case buildStrength = "Build Strength"
        case recomp = "Body Recomposition"
        case athletic = "Athletic Performance"
        case general = "General Fitness"

        var id: String { rawValue }

        var promptFragment: String {
            switch self {
            case .buildMuscle: return "focused on hypertrophy and muscle growth — prioritize volume, progressive overload, and time under tension"
            case .loseFat: return "focused on fat loss while preserving muscle — emphasize caloric expenditure, metabolic conditioning, and maintaining strength"
            case .buildStrength: return "focused on maximal strength — prioritize compound lifts, low rep ranges, and peaking strategies"
            case .recomp: return "focused on body recomposition — balance hypertrophy training with smart nutrition timing and progressive overload"
            case .athletic: return "focused on athletic performance — blend strength, power, mobility, and sport-specific conditioning"
            case .general: return "focused on overall health and fitness — balance strength, cardio, mobility, and sustainable habits"
            }
        }
    }

    enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
        case elite = "Elite"

        var id: String { rawValue }

        var promptFragment: String {
            switch self {
            case .beginner: return "The user is a beginner — explain concepts clearly, suggest conservative progressions, and focus on form fundamentals."
            case .intermediate: return "The user is intermediate — they know the basics. Focus on programming nuance, periodization, and breaking plateaus."
            case .advanced: return "The user is advanced — skip the basics. Discuss advanced programming, weak point analysis, and peaking strategies."
            case .elite: return "The user is elite-level — be precise and technical. They want data-driven feedback, micro-adjustments, and competition prep insights."
            }
        }
    }

    enum TrainingStyle: String, Codable, CaseIterable, Identifiable {
        case bodybuilding = "Bodybuilding"
        case powerlifting = "Powerlifting"
        case crossfit = "CrossFit"
        case calisthenics = "Calisthenics"
        case hybrid = "Hybrid"
        case custom = "Custom"

        var id: String { rawValue }
    }

    enum CoachingTone: String, Codable, CaseIterable, Identifiable {
        case drill = "Drill Sergeant"
        case bro = "Gym Bro"
        case science = "Science-Based"
        case chill = "Chill Coach"
        case stoic = "Stoic Mentor"

        var id: String { rawValue }

        var promptFragment: String {
            switch self {
            case .drill: return "Be direct and intense. No excuses, no fluff. Push the user hard. Short, punchy sentences."
            case .bro: return "Be hyped and supportive like a gym bro. Use casual language, get excited about PRs, keep it real."
            case .science: return "Be evidence-based and precise. Cite mechanisms, reference training principles, explain the 'why' behind recommendations."
            case .chill: return "Be calm, encouraging, and patient. Focus on sustainability and enjoyment. No pressure."
            case .stoic: return "Be measured and philosophical. Connect training to discipline, consistency, and long-term growth. Minimal words, maximum impact."
            }
        }
    }

    enum TrainingSplit: String, Codable, CaseIterable, Identifiable {
        case pushPullLegs = "Push/Pull/Legs"
        case upperLower = "Upper/Lower"
        case fullBody = "Full Body"
        case broSplit = "Bro Split"
        case arnoldSplit = "Arnold Split"
        case phat = "PHAT"
        case custom = "Custom"
        
        var id: String { rawValue }
        
        var promptFragment: String {
            switch self {
            case .pushPullLegs: return "Running a Push/Pull/Legs split — suggest exercises that fit the current day's push, pull, or leg focus."
            case .upperLower: return "Running an Upper/Lower split — alternate between upper body and lower body days."
            case .fullBody: return "Running a Full Body split — hit all major muscle groups each session."
            case .broSplit: return "Running a Bro Split — one major muscle group per day (chest day, back day, etc)."
            case .arnoldSplit: return "Running an Arnold Split — Chest/Back, Shoulders/Arms, Legs rotation."
            case .phat: return "Running PHAT — alternating power and hypertrophy days."
            case .custom: return "Running a custom split."
            }
        }
    }

    // MARK: - Defaults

    static let `default` = TrainerSoul(
        fitnessGoal: .buildMuscle,
        experienceLevel: .intermediate,
        trainingStyle: .bodybuilding,
        coachingTone: .bro,
        trainingSplit: .pushPullLegs,
        customPrompt: ""
    )

    // MARK: - Build System Prompt Fragment

    var systemPromptFragment: String {
        var parts: [String] = []

        parts.append("TRAINER PERSONA:")
        parts.append("You are \(fitnessGoal.promptFragment).")
        parts.append(experienceLevel.promptFragment)
        parts.append("Training style: \(trainingStyle.rawValue).")
        parts.append("Training split: \(trainingSplit.promptFragment)")
        parts.append(coachingTone.promptFragment)

        if !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("\nCUSTOM INSTRUCTIONS FROM USER:")
            parts.append(customPrompt)
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Persistence

    private static let storageKey = "trainer_soul"

    static func load() -> TrainerSoul {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let soul = try? JSONDecoder().decode(TrainerSoul.self, from: data) else {
            return .default
        }
        return soul
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
