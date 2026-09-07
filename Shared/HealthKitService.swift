import Foundation
import HealthKit
import os

@Observable
@MainActor
final class HealthKitService: NSObject {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "HealthKitService")

    private let healthStore = HKHealthStore()
    #if os(watchOS)
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    #endif

    var heartRate: Double = 0
    var activeCalories: Double = 0
    var averageHeartRate: Double = 0
    var totalActiveCalories: Double = 0
    var isAuthorized = false
    var workoutUUID: UUID?

    /// DEBUG-only: launch with `-RUXPSkipHealthKit` to bypass HealthKit entirely in simulators,
    /// where the permission sheet cannot be automated. Never true in release builds.
    nonisolated static var isDisabledForTesting: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-RUXPSkipHealthKit")
        #else
        return false
        #endif
    }

    var isHealthKitAvailable: Bool {
        !Self.isDisabledForTesting && HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async {
        guard isHealthKitAvailable else { return }

        let typesToWrite: Set<HKSampleType> = [
            HKQuantityType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate)
        ]

        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            isAuthorized = true
        } catch {
            Self.logger.error("HealthKit authorization failed: \(error)")
        }
    }

    /// When the workout actually began (the phone's start when the watch joined late), so the
    /// Health workout spans the whole session, not just the part this device saw.
    private var workoutStartDate: Date?

    /// A start date may come from the other device's clock; never let it sit in the future.
    private static func clampedStart(_ date: Date) -> Date {
        min(date, Date())
    }

    #if os(watchOS)
    /// True while a live HKWorkoutSession is collecting for the current workout.
    var hasLiveSession: Bool { workoutSession != nil }

    /// Starts a live workout session. Pass the workout's true start (the phone's, when the
    /// watch joins a phone-started workout) so duration, energy and heart rate cover it all.
    func startWorkout(at start: Date = Date()) async {
        guard isHealthKitAvailable else {
            Self.logger.warning("HealthKit not available on this device")
            return
        }
        // Joining twice (message + context) must not open a second session.
        guard workoutSession == nil else { return }

        if !isAuthorized {
            await requestAuthorization()
        }

        // Reset metrics
        heartRate = 0
        activeCalories = 0
        averageHeartRate = 0
        totalActiveCalories = 0
        let startDate = Self.clampedStart(start)
        workoutStartDate = startDate

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            builder.delegate = self

            self.workoutSession = session
            self.workoutBuilder = builder

            session.delegate = self
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            workoutUUID = session.currentActivity.uuid

            Self.logger.info("HealthKit workout started at \(startDate), UUID: \(self.workoutUUID?.uuidString ?? "nil")")
        } catch {
            Self.logger.error("Failed to start HealthKit workout: \(error)")
            // Reset so we know it didn't start
            workoutSession = nil
            workoutBuilder = nil
        }
    }

    func endWorkout() async {
        guard let session = workoutSession, let builder = workoutBuilder else {
            Self.logger.warning("No active HealthKit session to end — saving manual workout")
            await saveManualWorkout(start: workoutStartDate, end: Date())
            return
        }

        let endDate = Date()

        // Capture final stats before cleanup
        let hrType = HKQuantityType(.heartRate)
        let calType = HKQuantityType(.activeEnergyBurned)

        if let avgHR = builder.statistics(for: hrType)?.averageQuantity() {
            averageHeartRate = avgHR.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        if let totalCal = builder.statistics(for: calType)?.sumQuantity() {
            totalActiveCalories = totalCal.doubleValue(for: .kilocalorie())
        }

        Self.logger.info("Ending workout — avgHR: \(self.averageHeartRate), totalCal: \(self.totalActiveCalories)")

        session.end()

        do {
            try await builder.endCollection(at: endDate)
            try await Task.sleep(for: .milliseconds(500)) // Give HealthKit a moment to finalize
            let workout = try await builder.finishWorkout()
            if let workout {
                Self.logger.info("HealthKit workout saved: \(workout.uuid)")
                workoutUUID = workout.uuid
            } else {
                Self.logger.warning("finishWorkout returned nil — saving manual workout")
                await saveManualWorkout(start: workoutStartDate, end: endDate)
            }
        } catch {
            Self.logger.error("Failed to finish HealthKit workout: \(error) — saving manual workout")
            await saveManualWorkout(start: workoutStartDate, end: endDate)
        }

        workoutSession = nil
        workoutBuilder = nil
        workoutStartDate = nil
    }
    #else
    /// iPhone: no live session. Remembers the start so a phone-only workout can be saved
    /// manually; when the watch joined, the watch owns the Health workout and this is skipped.
    func startWorkout(at start: Date = Date()) async {
        guard isHealthKitAvailable else { return }
        if !isAuthorized { await requestAuthorization() }
        workoutStartDate = Self.clampedStart(start)
    }

    /// Saves a manual workout so a phone-only session still appears in Apple Health.
    /// `start` wins over the remembered start (which is lost if the app relaunched mid-workout).
    func endWorkout(start: Date? = nil, end: Date = Date()) async {
        await saveManualWorkout(start: start ?? workoutStartDate, end: end)
        workoutStartDate = nil
    }
    #endif

    /// Fallback: write a workout with HKWorkoutBuilder (the non-deprecated path on both platforms).
    /// Accepts a past start so a late-joined or relaunched session still spans the whole workout.
    private func saveManualWorkout(start: Date?, end: Date) async {
        guard isHealthKitAvailable, let rawStart = start else { return }
        let startDate = Self.clampedStart(rawStart)
        let endDate = max(end, startDate.addingTimeInterval(1))

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())

        do {
            try await builder.beginCollection(at: startDate)
            if totalActiveCalories > 0 {
                let energy = HKCumulativeQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: totalActiveCalories),
                    start: startDate,
                    end: endDate
                )
                try await builder.addSamples([energy])
            }
            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()
            workoutUUID = workout?.uuid
            Self.logger.info("Manual workout saved to HealthKit: \(workout?.uuid.uuidString ?? "nil")")
        } catch {
            Self.logger.error("Failed to save manual workout: \(error)")
        }
    }

    // MARK: - Query Health Data for a Completed Workout

    /// Fetches average heart rate and active calories for a time range from HealthKit
    func fetchWorkoutHealthData(start: Date, end: Date) async -> (avgHeartRate: Double?, activeCalories: Double?) {
        guard isHealthKitAvailable, isAuthorized else { return (nil, nil) }

        async let hr = fetchAverageHeartRate(start: start, end: end)
        async let cal = fetchActiveCalories(start: start, end: end)

        return await (hr, cal)
    }

    private func fetchAverageHeartRate(start: Date, end: Date) async -> Double? {
        let hrType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: hrType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, _ in
                let avg = stats?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: avg)
            }
            healthStore.execute(query)
        }
    }

    private func fetchActiveCalories(start: Date, end: Date) async -> Double? {
        let calType = HKQuantityType(.activeEnergyBurned)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: calType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let total = stats?.sumQuantity()?.doubleValue(for: .kilocalorie())
                continuation.resume(returning: total)
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

#if os(watchOS)
extension HealthKitService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            Self.logger.info("HealthKit session state: \(String(describing: fromState.rawValue)) → \(String(describing: toState.rawValue))")
        }
    }
    
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            Self.logger.error("HealthKit session failed: \(error.localizedDescription)")
        }
    }
}

extension HealthKitService: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // No-op: we don't track workout events
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        let calType = HKQuantityType(.activeEnergyBurned)

        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            switch quantityType {
            case hrType:
                if let mostRecent = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity() {
                    let bpm = mostRecent.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    Task { @MainActor in
                        self.heartRate = bpm
                    }
                }
            case calType:
                if let sum = workoutBuilder.statistics(for: calType)?.sumQuantity() {
                    let kcal = sum.doubleValue(for: .kilocalorie())
                    Task { @MainActor in
                        self.activeCalories = kcal
                    }
                }
            default:
                break
            }
        }
    }
}
#endif
