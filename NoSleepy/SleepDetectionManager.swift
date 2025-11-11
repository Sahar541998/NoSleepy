import Foundation
import HealthKit

// MARK: - Public Contract
protocol SleepDetectionManaging {
    func isUserLikelySleeping() async -> Bool
    func noteUserInteraction()
    func setMinCandidateProbability(_ value: Double)
    func registerHealthObservers()
    func lastEvaluationSnapshot() -> SleepEvaluationSnapshot?
}

extension SleepDetectionManaging {
    func noteUserInteraction() { /* default no-op */ }
    func setMinCandidateProbability(_ value: Double) { /* default no-op */ }
    func registerHealthObservers() { /* default no-op */ }
    func lastEvaluationSnapshot() -> SleepEvaluationSnapshot? { nil }
}

// MARK: - Sleep State Model
enum SleepState: Equatable {
    case awake
    case drowsy(probability: Double)
    case likelyAsleep(probability: Double)
}

// Snapshot of the last evaluation for logging/diagnostics
struct SleepEvaluationSnapshot {
    let timestamp: Date
    let probability: Double? // nil when missing data prevents calculation
    let state: SleepState
    let hadMissingData: Bool
}

// MARK: - Real-time Sleep Detection
final class SleepDetectionManager: SleepDetectionManaging {
    // Dependencies kept internal for testability and SOLID design
    private let healthStore: HKHealthStore
    private let estimator: SleepStateEstimating
    private let inactivityTracker: UserInactivityTracking

    // Health types we rely on for real-time estimation
    private let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)
    private let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)

    // Debounce controls "confirmation" of asleep state to reduce flapping
    private let asleepConfirmationWindow: TimeInterval = 12 * 60 // 12 minutes within 10–15 min guidance
    private var provisionalAsleepStart: Date?
    private var lastComputedState: SleepState = .awake
    private var minCandidateProbability: Double = 0.7
    private var heartRateObserver: HKObserverQuery?
    private var energyObserver: HKObserverQuery?
    private var lastSnapshot: SleepEvaluationSnapshot?

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        estimator: SleepStateEstimating = SleepStateEstimator(),
        inactivityTracker: UserInactivityTracking = UserInactivityTracker()
    ) {
        self.healthStore = healthStore
        self.estimator = estimator
        self.inactivityTracker = inactivityTracker

        // Best-effort background delivery: The system may wake the app for new data.
        // This complements our periodic polling loop in the view model.
        enableBackgroundDeliveryIfPossible()
    }

    func noteUserInteraction() {
        inactivityTracker.noteUserInteraction()
    }

    func setMinCandidateProbability(_ value: Double) {
        // Clamp to supported range with a sensible default band [0.1, 1.0]
        let clamped = max(0.1, min(1.0, value))
        minCandidateProbability = clamped
    }

    // MARK: - Background Observers
    func registerHealthObservers() {
        guard let heartRateType, let activeEnergyType else { return }
        #if DEBUG
        print("[NoSleepy][HK] Registering background observers for heartRate and activeEnergy")
        #endif

        // Heart rate observer
        let hrObserver = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] _, completion, _ in
            guard let self else { completion(); return }
            #if DEBUG
            print("[NoSleepy][HK] HeartRate observer triggered")
            #endif
            Task {
                let isSleeping = await self.isUserLikelySleeping()
                if isSleeping {
                    // Notify promptly even if app is backgrounded
                    await MainActor.run {
                        NotificationManager.shared.notifySleepDetected()
                    }
                }
                completion()
            }
        }
        healthStore.execute(hrObserver)
        heartRateObserver = hrObserver

        // Active energy observer
        let enObserver = HKObserverQuery(sampleType: activeEnergyType, predicate: nil) { [weak self] _, completion, _ in
            guard let self else { completion(); return }
            #if DEBUG
            print("[NoSleepy][HK] ActiveEnergy observer triggered")
            #endif
            Task {
                let isSleeping = await self.isUserLikelySleeping()
                if isSleeping {
                    await MainActor.run {
                        NotificationManager.shared.notifySleepDetected()
                    }
                }
                completion()
            }
        }
        healthStore.execute(enObserver)
        energyObserver = enObserver

        // Ensure background delivery is enabled (best effort)
        enableBackgroundDeliveryIfPossible()
    }

    func lastEvaluationSnapshot() -> SleepEvaluationSnapshot? {
        lastSnapshot
    }

    func isUserLikelySleeping() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        // Read a "recent" window to smooth noise and let trends emerge
        let now = Date()
        let windowStart = now.addingTimeInterval(-15 * 60) // last 15 minutes
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: now, options: .strictEndDate)

        // Run heart-rate and energy queries concurrently for efficiency
        async let heartRateBPMs = fetchHeartRates(predicate: predicate)
        async let energyKcals = fetchActiveEnergy(predicate: predicate)

        let recentHeartRates = await heartRateBPMs
        let recentEnergy = await energyKcals
        let inactivity = inactivityTracker.currentInactivityDuration()
        let hadMissingData = recentHeartRates.isEmpty && recentEnergy.isEmpty
        #if DEBUG
        let hrAvg = recentHeartRates.isEmpty ? nil : (recentHeartRates.reduce(0, +) / Double(recentHeartRates.count))
        let energySum = recentEnergy.reduce(0, +)
        print("[NoSleepy][Eval] HR count=\(recentHeartRates.count) avg=\(hrAvg?.rounded() ?? -1) bpm, Energy samples=\(recentEnergy.count) total=\(String(format: "%.2f", energySum)) kcal, Inactivity=\(Int(inactivity))s, MissingData=\(hadMissingData)")
        #endif

        let (state, rawProbability) = estimator.estimate(
            recentHeartRatesBPM: recentHeartRates,
            recentActiveEnergyKcals: recentEnergy,
            inactivityDuration: inactivity
        )
        lastComputedState = state
        #if DEBUG
        switch state {
        case .awake:
            print("[NoSleepy][Eval] State=awake probability=\(String(format: "%.2f", rawProbability))")
        case .drowsy(let p):
            print("[NoSleepy][Eval] State=drowsy probability=\(String(format: "%.2f", p)) threshold>=\(String(format: "%.2f", minCandidateProbability))")
        case .likelyAsleep(let p):
            print("[NoSleepy][Eval] State=likelyAsleep probability=\(String(format: "%.2f", p)) threshold>=\(String(format: "%.2f", minCandidateProbability))")
        }
        #endif

        // Debouncing: Only confirm "likely asleep" after a sustained period
        // Use configurable probability threshold: treat both high-prob drowsy and likelyAsleep
        // as candidates if they exceed the configured minimum. This allows tuning sensitivity
        // while still requiring sustained confirmation to reduce false positives.
        let candidateProbability: Double? = {
            switch state {
            case .likelyAsleep(let p): return p
            case .drowsy(let p): return p
            case .awake: return nil
            }
        }()

        // Record snapshot for UI logs
        lastSnapshot = SleepEvaluationSnapshot(
            timestamp: now,
            probability: rawProbability,
            state: state,
            hadMissingData: hadMissingData
        )

        guard let probability = candidateProbability, probability >= minCandidateProbability, !hadMissingData else {
            #if DEBUG
            if hadMissingData {
                print("[NoSleepy][Eval] Decision=awake (missing data: no HR and no energy)")
            } else if let p = candidateProbability {
                print("[NoSleepy][Eval] Decision=awake (below threshold \(String(format: "%.2f", p)) < \(String(format: "%.2f", minCandidateProbability)))")
            } else {
                print("[NoSleepy][Eval] Decision=awake (state=awake no candidate probability)")
            }
            #endif
            provisionalAsleepStart = nil
            return false
        }

        switch state {
        case .likelyAsleep, .drowsy:
            if provisionalAsleepStart == nil {
                provisionalAsleepStart = now
                #if DEBUG
                print("[NoSleepy][Eval] Debounce started at \(now)")
                #endif
            }
            let sustained = now.timeIntervalSince(provisionalAsleepStart ?? now)
            if sustained >= asleepConfirmationWindow {
                #if DEBUG
                print("[NoSleepy][Eval] Decision=asleep (debounce satisfied \(Int(sustained))s >= \(Int(asleepConfirmationWindow))s)")
                #endif
                return true
            } else {
                #if DEBUG
                print("[NoSleepy][Eval] Decision=pending (debouncing \(Int(sustained))s / \(Int(asleepConfirmationWindow))s)")
                #endif
                return false
            }
        case .awake:
            provisionalAsleepStart = nil
            #if DEBUG
            print("[NoSleepy][Eval] Decision=awake (explicit)")
            #endif
            return false
        }
    }

    // MARK: - Private: HealthKit queries
    private func fetchHeartRates(predicate: NSPredicate) async -> [Double] {
        guard let heartRateType else { return [] }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                guard let quantitySamples = results as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                // Heart rate is stored in count/min (bpm)
                let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
                let values = quantitySamples.map { $0.quantity.doubleValue(for: unit) }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    private func fetchActiveEnergy(predicate: NSPredicate) async -> [Double] {
        guard let activeEnergyType else { return [] }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: activeEnergyType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                guard let quantitySamples = results as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                // Active energy is measured in kilocalories
                let unit = HKUnit.kilocalorie()
                let values = quantitySamples.map { $0.quantity.doubleValue(for: unit) }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    private func enableBackgroundDeliveryIfPossible() {
        // This is a best-effort background nudge; the app must also be properly configured
        // with HealthKit capability and background processing allowances. iPhone-only support.
        guard let heartRateType, let activeEnergyType else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate) { _, _ in
                    continuation.resume()
                }
            }
            try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.healthStore.enableBackgroundDelivery(for: activeEnergyType, frequency: .hourly) { _, _ in
                    continuation.resume()
                }
            }
        }
    }
}

