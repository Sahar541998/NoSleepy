import Foundation
import HealthKit

protocol SleepDetectionManaging {
    func isUserLikelySleeping() async -> Bool
}

final class SleepDetectionManager: SleepDetectionManaging {
    private let healthStore = HKHealthStore()
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)

    func isUserLikelySleeping() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(), let sleepType else {
            return false
        }

        let windowStart = Date().addingTimeInterval(-5 * 60) // last 5 minutes
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: Date(), options: .strictEndDate)
        let descriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let samples: [HKCategorySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: 10,
                sortDescriptors: [descriptor]
            ) { _, results, _ in
                let sleepSamples = results as? [HKCategorySample] ?? []
                continuation.resume(returning: sleepSamples)
            }

            healthStore.execute(query)
        }

        #if DEBUG
        if let latest = samples.first {
            let formatter = ISO8601DateFormatter()
            let value = HKCategoryValueSleepAnalysis(rawValue: latest.value)
            print("[NoSleepy] Latest sleep sample: value=\(value) start=\(formatter.string(from: latest.startDate)) end=\(formatter.string(from: latest.endDate))")
        } else {
            print("[NoSleepy] No sleep samples found in the last 30 minutes.")
        }
        #endif

        guard let latestSample = samples.first else {
            return false
        }

        let asleepValues: Set<HKCategoryValueSleepAnalysis> = [
            .asleepUnspecified,
            .asleepCore,
            .asleepDeep,
            .asleepREM
        ]

        if let sleepValue = HKCategoryValueSleepAnalysis(rawValue: latestSample.value) {
            return asleepValues.contains(sleepValue) && latestSample.endDate >= Date().addingTimeInterval(-5 * 60)
        }

        return false
    }
}

