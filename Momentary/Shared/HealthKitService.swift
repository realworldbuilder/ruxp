import Foundation
import HealthKit
import os

@Observable
@MainActor
final class HealthKitService: NSObject {
    private static let logger = Logger(subsystem: "com.whussey.momentary", category: "HealthKitService")

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

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async {
        guard isHealthKitAvailable else { return }

        let typesToWrite: Set<HKSampleType> = [
            HKQuantityType.workoutType()
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

    private var workoutStartDate: Date?

    #if os(watchOS)
    func startWorkout() async {
        guard isHealthKitAvailable else {
            Self.logger.warning("HealthKit not available on this device")
            return
        }

        if !isAuthorized {
            await requestAuthorization()
        }

        // Reset metrics
        heartRate = 0
        activeCalories = 0
        averageHeartRate = 0
        totalActiveCalories = 0
        workoutStartDate = Date()

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
            session.startActivity(with: workoutStartDate!)
            try await builder.beginCollection(at: workoutStartDate!)

            workoutUUID = session.currentActivity.uuid

            Self.logger.info("HealthKit workout started, UUID: \(self.workoutUUID?.uuidString ?? "nil")")
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
            await saveManualWorkout()
            return
        }

        // Capture final stats before cleanup
        let hrType = HKQuantityType(.heartRate)
        let calType = HKQuantityType(.activeEnergyBurned)

        if let avgHR = builder.statistics(for: hrType)?.averageQuantity() {
            averageHeartRate = avgHR.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        if let totalCal = builder.statistics(for: calType)?.sumQuantity() {
            totalActiveCalories = totalCal.doubleValue(for: .kilocalorie())
        }

        session.end()

        do {
            try await builder.endCollection(at: Date())
            let workout = try await builder.finishWorkout()
            if let workout {
                Self.logger.info("HealthKit workout saved: \(workout.uuid)")
                workoutUUID = workout.uuid
            } else {
                Self.logger.warning("finishWorkout returned nil — saving manual workout")
                await saveManualWorkout()
            }
        } catch {
            Self.logger.error("Failed to finish HealthKit workout: \(error) — saving manual workout")
            await saveManualWorkout()
        }

        workoutSession = nil
        workoutBuilder = nil
    }

    /// Fallback: manually save a workout to HealthKit if the live session fails
    private func saveManualWorkout() async {
        guard let startDate = workoutStartDate else { return }
        let endDate = Date()

        let workout = HKWorkout(
            activityType: .traditionalStrengthTraining,
            start: startDate,
            end: endDate,
            duration: endDate.timeIntervalSince(startDate),
            totalEnergyBurned: totalActiveCalories > 0 ? HKQuantity(unit: .kilocalorie(), doubleValue: totalActiveCalories) : nil,
            totalDistance: nil,
            metadata: nil
        )

        do {
            try await healthStore.save(workout)
            workoutUUID = workout.uuid
            Self.logger.info("Manual workout saved to HealthKit: \(workout.uuid)")
        } catch {
            Self.logger.error("Failed to save manual workout: \(error)")
        }
    }
    #else
    func startWorkout() async {
        guard isHealthKitAvailable else {
            if !isAuthorized { await requestAuthorization() }
            return
        }
    }

    func endWorkout() async {
        // On iPhone without watch, no live workout to end
    }
    #endif

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
