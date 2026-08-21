import Foundation

// Sample workout data for testing/demo purposes. Debug builds only.
#if DEBUG

enum SampleDataGenerator {
    static func generate() -> [WorkoutSession] {
        let calendar = Calendar.current
        let now = Date()

        return [
            chestDay(date: calendar.date(byAdding: .day, value: -1, to: now)!, duration: 3420, avgHR: 142, cal: 385),
            pullDay(date: calendar.date(byAdding: .day, value: -2, to: now)!, duration: 3780, avgHR: 138, cal: 410),
            legDay(date: calendar.date(byAdding: .day, value: -3, to: now)!, duration: 4200, avgHR: 155, cal: 520),
            pushDay(date: calendar.date(byAdding: .day, value: -5, to: now)!, duration: 3060, avgHR: 135, cal: 340),
            backAndBiceps(date: calendar.date(byAdding: .day, value: -6, to: now)!, duration: 3600, avgHR: 148, cal: 430),
            fullBody(date: calendar.date(byAdding: .day, value: -8, to: now)!, duration: 4500, avgHR: 152, cal: 510),
            shoulderDay(date: calendar.date(byAdding: .day, value: -9, to: now)!, duration: 2700, avgHR: 128, cal: 280),
        ]
    }

    // MARK: - Workouts

    private static func chestDay(date: Date, duration: TimeInterval, avgHR: Double, cal: Double) -> WorkoutSession {
        makeSession(date: date, duration: duration, moments: [
            "Bench press, warmed up with 135 for 10, then 185 for 8, 205 for 6, 225 for 4",
            "Incline dumbbell press, 70s for 4 sets of 10",
            "Cable flyes, 3 sets of 15 at 30 each side",
            "Dips, 3 sets to failure, got 12, 10, 8"
        ], exercises: [
            exercise("Bench Press", sets: [
                set(1, reps: 10, weight: 135), set(2, reps: 8, weight: 185),
                set(3, reps: 6, weight: 205), set(4, reps: 4, weight: 225),
            ]),
            exercise("Incline Dumbbell Press", sets: [
                set(1, reps: 10, weight: 70), set(2, reps: 10, weight: 70),
                set(3, reps: 10, weight: 70), set(4, reps: 10, weight: 70),
            ]),
            exercise("Cable Flyes", sets: [
                set(1, reps: 15, weight: 30), set(2, reps: 15, weight: 30),
                set(3, reps: 15, weight: 30),
            ]),
            exercise("Dips", sets: [
                set(1, reps: 12, weight: 0), set(2, reps: 10, weight: 0),
                set(3, reps: 8, weight: 0),
            ], notes: "Bodyweight, to failure"),
        ], summary: "Solid chest session. Hit a strong 225 on bench for 4. Pump was crazy after cable flyes.", highlights: ["225 lb bench press for 4 reps", "15 total sets"], avgHR: avgHR, cal: cal)
    }

    private static func pullDay(date: Date, duration: TimeInterval, avgHR: Double, cal: Double) -> WorkoutSession {
        makeSession(date: date, duration: duration, moments: [
            "Barbell rows, worked up to 185 for 5 sets of 5",
            "Pull-ups, 4 sets, got 10, 8, 8, 6",
            "Face pulls 3 sets of 20 at 40 pounds",
            "Hammer curls 3 sets of 12 with 35s"
        ], exercises: [
            exercise("Barbell Row", sets: [
                set(1, reps: 5, weight: 185), set(2, reps: 5, weight: 185),
                set(3, reps: 5, weight: 185), set(4, reps: 5, weight: 185),
                set(5, reps: 5, weight: 185),
            ]),
            exercise("Pull-ups", sets: [
                set(1, reps: 10, weight: 0), set(2, reps: 8, weight: 0),
                set(3, reps: 8, weight: 0), set(4, reps: 6, weight: 0),
            ]),
            exercise("Face Pulls", sets: [
                set(1, reps: 20, weight: 40), set(2, reps: 20, weight: 40),
                set(3, reps: 20, weight: 40),
            ]),
            exercise("Hammer Curls", sets: [
                set(1, reps: 12, weight: 35), set(2, reps: 12, weight: 35),
                set(3, reps: 12, weight: 35),
            ]),
        ], summary: "Heavy pull day. Rows felt strong at 185. Pull-up numbers coming up.", highlights: ["185 lb barbell rows 5x5", "32 total pull-ups"], avgHR: avgHR, cal: cal)
    }

    private static func legDay(date: Date, duration: TimeInterval, avgHR: Double, cal: Double) -> WorkoutSession {
        makeSession(date: date, duration: duration, moments: [
            "Squats, worked up to 275 for 3. Hit 225 for 3 sets of 5 after",
            "Romanian deadlifts, 225 for 4 sets of 8",
            "Leg press 4 plates each side for 3 sets of 12",
            "Calf raises on the leg press, 3 sets of 20"
        ], exercises: [
            exercise("Squat", sets: [
                set(1, reps: 5, weight: 135), set(2, reps: 3, weight: 225),
                set(3, reps: 3, weight: 275), set(4, reps: 5, weight: 225),
                set(5, reps: 5, weight: 225), set(6, reps: 5, weight: 225),
            ]),
            exercise("Romanian Deadlift", sets: [
                set(1, reps: 8, weight: 225), set(2, reps: 8, weight: 225),
                set(3, reps: 8, weight: 225), set(4, reps: 8, weight: 225),
            ]),
            exercise("Leg Press", sets: [
                set(1, reps: 12, weight: 360), set(2, reps: 12, weight: 360),
                set(3, reps: 12, weight: 360),
            ]),
            exercise("Calf Raises", sets: [
                set(1, reps: 20, weight: 360), set(2, reps: 20, weight: 360),
                set(3, reps: 20, weight: 360),
            ]),
        ], summary: "Brutal leg day. 275 squat for a triple felt heavy but clean. RDLs smoked the hamstrings.", highlights: ["275 lb squat for 3", "17 total sets"], avgHR: avgHR, cal: cal)
    }

    private static func pushDay(date: Date, duration: TimeInterval, avgHR: Double, cal: Double) -> WorkoutSession {
        makeSession(date: date, duration: duration, moments: [
            "Overhead press 135 for 4 sets of 6",
            "Incline bench 185 for 3 sets of 8",
            "Lateral raises 25s for 4 sets of 15",
            "Tricep pushdowns 3 sets of 15"
        ], exercises: [
            exercise("Overhead Press", sets: [
                set(1, reps: 6, weight: 135), set(2, reps: 6, weight: 135),
                set(3, reps: 6, weight: 135), set(4, reps: 6, weight: 135),
            ]),
            exercise("Incline Bench Press", sets: [
                set(1, reps: 8, weight: 185), set(2, reps: 8, weight: 185),
                set(3, reps: 8, weight: 185),
            ]),
            exercise("Lateral Raises", sets: [
                set(1, reps: 15, weight: 25), set(2, reps: 15, weight: 25),
                set(3, reps: 15, weight: 25), set(4, reps: 15, weight: 25),
            ]),
            exercise("Tricep Pushdowns", sets: [
                set(1, reps: 15, weight: 60), set(2, reps: 15, weight: 60),
                set(3, reps: 15, weight: 60),
            ]),
        ], summary: "Good push day. OHP at 135 for sets of 6 is progressing nicely.", highlights: ["135 lb OHP 4x6", "14 total sets"], avgHR: avgHR, cal: cal)
    }

    private static func backAndBiceps(date: Date, duration: TimeInterval, avgHR: Double, cal: Double) -> WorkoutSession {
        makeSession(date: date, duration: duration, moments: [
            "Deadlifts, worked up to 315 for 3, then 275 for 2 sets of 5",
            "Lat pulldowns 4 sets of 10 at 150",
            "Seated cable rows 3 sets of 12 at 135",
            "Barbell curls 3 sets of 10 at 75"
        ], exercises: [
            exercise("Deadlift", sets: [
                set(1, reps: 5, weight: 225), set(2, reps: 3, weight: 315),
                set(3, reps: 5, weight: 275), set(4, reps: 5, weight: 275),
            ]),
            exercise("Lat Pulldown", sets: [
                set(1, reps: 10, weight: 150), set(2, reps: 10, weight: 150),
                set(3, reps: 10, weight: 150), set(4, reps: 10, weight: 150),
            ]),
            exercise("Cable Row", sets: [
                set(1, reps: 12, weight: 135), set(2, reps: 12, weight: 135),
                set(3, reps: 12, weight: 135),
            ]),
            exercise("Barbell Curls", sets: [
                set(1, reps: 10, weight: 75), set(2, reps: 10, weight: 75),
                set(3, reps: 10, weight: 75),
            ]),
        ], summary: "Heavy back day. 315 deadlift triple felt solid. Back pump was insane after pulldowns.", highlights: ["315 lb deadlift for 3", "14 total sets"], avgHR: avgHR, cal: cal)
    }

    private static func fullBody(date: Date, duration: TimeInterval, avgHR: Double, cal: Double) -> WorkoutSession {
        makeSession(date: date, duration: duration, moments: [
            "Started with squats, 225 for 3 sets of 5",
            "Then bench 185 for 3 sets of 8",
            "Barbell rows 155 for 3 sets of 10",
            "Finished with overhead press 115 for 3 sets of 8 and some ab work"
        ], exercises: [
            exercise("Squat", sets: [
                set(1, reps: 5, weight: 225), set(2, reps: 5, weight: 225),
                set(3, reps: 5, weight: 225),
            ]),
            exercise("Bench Press", sets: [
                set(1, reps: 8, weight: 185), set(2, reps: 8, weight: 185),
                set(3, reps: 8, weight: 185),
            ]),
            exercise("Barbell Row", sets: [
                set(1, reps: 10, weight: 155), set(2, reps: 10, weight: 155),
                set(3, reps: 10, weight: 155),
            ]),
            exercise("Overhead Press", sets: [
                set(1, reps: 8, weight: 115), set(2, reps: 8, weight: 115),
                set(3, reps: 8, weight: 115),
            ]),
        ], summary: "Full body compound day. All the big lifts hit. Good volume session.", highlights: ["225 squat 3x5", "12 total sets across 4 compounds"], avgHR: avgHR, cal: cal)
    }

    private static func shoulderDay(date: Date, duration: TimeInterval, avgHR: Double, cal: Double) -> WorkoutSession {
        makeSession(date: date, duration: duration, moments: [
            "Seated dumbbell press 60s for 4 sets of 8",
            "Lateral raises 20s for 5 sets of 15",
            "Rear delt flyes 25s for 3 sets of 15",
            "Shrugs with 225 on the bar for 3 sets of 12"
        ], exercises: [
            exercise("Dumbbell Shoulder Press", sets: [
                set(1, reps: 8, weight: 60), set(2, reps: 8, weight: 60),
                set(3, reps: 8, weight: 60), set(4, reps: 8, weight: 60),
            ]),
            exercise("Lateral Raises", sets: [
                set(1, reps: 15, weight: 20), set(2, reps: 15, weight: 20),
                set(3, reps: 15, weight: 20), set(4, reps: 15, weight: 20),
                set(5, reps: 15, weight: 20),
            ]),
            exercise("Rear Delt Flyes", sets: [
                set(1, reps: 15, weight: 25), set(2, reps: 15, weight: 25),
                set(3, reps: 15, weight: 25),
            ]),
            exercise("Barbell Shrugs", sets: [
                set(1, reps: 12, weight: 225), set(2, reps: 12, weight: 225),
                set(3, reps: 12, weight: 225),
            ]),
        ], summary: "Shoulder isolation day. Lateral raises at 5x15 had the delts screaming.", highlights: ["60 lb DB press 4x8", "5 sets of lateral raises"], avgHR: avgHR, cal: cal)
    }

    // MARK: - Helpers

    private static func makeSession(
        date: Date, duration: TimeInterval, moments: [String],
        exercises: [ExerciseGroup], summary: String, highlights: [String],
        avgHR: Double? = nil, cal: Double? = nil
    ) -> WorkoutSession {
        let start = date
        let end = date.addingTimeInterval(duration)
        let interval = duration / Double(moments.count + 1)

        let momentObjs = moments.enumerated().map { idx, text in
            Moment(
                timestamp: start.addingTimeInterval(interval * Double(idx + 1)),
                transcript: text,
                source: .phone
            )
        }

        let log = StructuredLog(
            exercises: exercises,
            summary: summary,
            highlights: highlights
        )

        return WorkoutSession(
            startedAt: start,
            endedAt: end,
            moments: momentObjs,
            structuredLog: log,
            averageHeartRate: avgHR,
            activeCalories: cal
        )
    }

    private static func exercise(_ name: String, sets: [ExerciseSet], notes: String? = nil) -> ExerciseGroup {
        ExerciseGroup(exerciseName: name, sets: sets, notes: notes)
    }

    private static func set(_ num: Int, reps: Int, weight: Double) -> ExerciseSet {
        ExerciseSet(setNumber: num, reps: reps, weight: weight)
    }
}

#endif
