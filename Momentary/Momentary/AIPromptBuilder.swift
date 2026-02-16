import Foundation

enum AIPromptBuilder {

    static func buildSystemPrompt() -> String {
        let soul = TrainerSoul.load()

        return """
        You are a fitness AI assistant that processes voice-recorded workout moments into structured data.

        \(soul.systemPromptFragment)

        Your job is to analyze voice transcripts from a strength training session and produce:
        1. A structured workout log (exercises, sets, reps, weights)
        2. Training insights and stories
        3. An insight pack with takeaways, form cues, and PR notes

        RULES FOR STRUCTURED LOG:
        - Normalize exercise names (e.g., "bench" → "Barbell Bench Press", "squats" → "Barbell Back Squat")
        - Use the user's preferred weight unit (specified below) as the default unless the user explicitly says otherwise
        - If a rep count or weight is ambiguous, provide your best guess and list it as an ambiguity
        - Group consecutive mentions of the same exercise together
        - Number sets sequentially within each exercise

        RULES FOR INSIGHTS:
        - progressNote: Observations about progress, PRs, volume changes
        - formReminder: Form cues or technique notes the user mentioned
        - motivational: Encouraging notes based on effort or consistency
        - recovery: Notes about fatigue, soreness, or recovery needs
        - Each story should have multi-page content when there's enough detail
        - Pages should include actionable items where relevant

        RULES FOR INSIGHT PACK:
        - takeaways: Key lessons or observations from this session (2-3 items)
        - formCues: Specific form or technique reminders mentioned (1-2 items, or empty)
        - prNotes: Any personal records or notable weight milestones (or empty)

        Respond with valid JSON matching the schema exactly.
        """
    }

    static func buildUserPrompt(
        moments: [Moment],
        workoutDate: Date,
        duration: TimeInterval,
        preferredUnit: String = UserDefaults.standard.string(forKey: "weightUnit") ?? "lbs"
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        let durationMinutes = Int(duration / 60)

        var prompt = """
        WORKOUT SESSION
        Date: \(dateFormatter.string(from: workoutDate))
        Duration: \(durationMinutes) minutes
        Total moments recorded: \(moments.count)
        Preferred weight unit: \(preferredUnit)

        VOICE TRANSCRIPTS (in chronological order):
        """

        for (index, moment) in moments.enumerated() {
            let relativeTime = moment.timestamp.timeIntervalSince(workoutDate)
            let minutesIn = Int(relativeTime / 60)
            prompt += "\n[\(minutesIn)min] Moment \(index + 1): \"\(moment.transcript)\""
        }

        prompt += """

        \n
        Please analyze these voice transcripts and produce a JSON response with this structure:
        {
          "structuredLog": {
            "exercises": [
              {
                "exerciseName": "Exercise Name",
                "sets": [
                  {
                    "setNumber": 1,
                    "reps": 10,
                    "weight": 135.0,
                    "weightUnit": "lbs",
                    "duration": null,
                    "notes": null
                  }
                ],
                "notes": null
              }
            ],
            "summary": "Brief workout summary",
            "highlights": ["Notable achievements"],
            "ambiguities": [
              {
                "field": "weight",
                "rawTranscript": "the original text",
                "bestGuess": "135 lbs",
                "alternatives": ["135 kg", "185 lbs"]
              }
            ]
          },
          "insightPack": {
            "takeaways": ["Key takeaway 1", "Key takeaway 2"],
            "formCues": ["Form cue if mentioned"],
            "prNotes": ["PR note if applicable"]
          },
          "stories": [
            {
              "title": "Story Title",
              "body": "Story body text",
              "tags": ["strength", "chest"],
              "type": "progressNote",
              "pages": [
                {
                  "title": "Page Title",
                  "content": "Page content text",
                  "actionable": "Optional action item"
                }
              ],
              "preview": "Short preview text"
            }
          ]
        }

        Note: The "contentPack" field is no longer needed. Focus on insightPack and stories instead.
        """

        return prompt
    }

    static func buildInsightPrompt(
        storyType: InsightType,
        workoutSummary: String,
        timePeriod: String
    ) -> String {
        let typeDescription: String
        switch storyType {
        case .weeklyReview:
            typeDescription = "a weekly training review highlighting consistency, volume trends, and notable sessions"
        case .newPRs:
            typeDescription = "celebrating new personal records with context about how far the lifter has come"
        case .trendingUp:
            typeDescription = "noting positive trends in exercise performance and progressive overload"
        case .nextGoals:
            typeDescription = "suggesting specific, achievable next targets based on current performance"
        case .progressNote:
            typeDescription = "an observation about training progress"
        case .formReminder:
            typeDescription = "a form or technique reminder"
        case .motivational:
            typeDescription = "an encouraging note about effort and consistency"
        case .recovery:
            typeDescription = "a note about recovery needs"
        }

        return """
        Write \(typeDescription) for a strength training athlete.

        TRAINING DATA (\(timePeriod)):
        \(workoutSummary)

        Write 2-3 concise, specific sentences. Be direct and personalized based on the data. No generic fitness cliches.
        """
    }
}
