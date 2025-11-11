import Foundation

protocol SleepStateEstimating {
    func estimateState(
        recentHeartRatesBPM: [Double],
        recentActiveEnergyKcals: [Double],
        inactivityDuration: TimeInterval
    ) -> SleepState
    // Returns both qualitative state and the raw probability used to derive it
    func estimate(
        recentHeartRatesBPM: [Double],
        recentActiveEnergyKcals: [Double],
        inactivityDuration: TimeInterval
    ) -> (state: SleepState, probability: Double)
}

final class SleepStateEstimator: SleepStateEstimating {
    // Tunable thresholds; chosen conservatively to avoid false positives.
    // - Heart rate below ~60 bpm for adults is common at rest; use median to reduce outliers.
    // - Very low active energy indicates limited motion at the phone level.
    // - Require 10+ minutes of no interaction to avoid misclassifying brief pauses.
    private let lowHeartRateThresholdBPM: Double = 60
    private let lowMotionEnergyThresholdKcalsPer10Min: Double = 3
    private let requiredInactivityWindow: TimeInterval = 10 * 60

    func estimateState(
        recentHeartRatesBPM: [Double],
        recentActiveEnergyKcals: [Double],
        inactivityDuration: TimeInterval
    ) -> SleepState {
        let result = estimate(
            recentHeartRatesBPM: recentHeartRatesBPM,
            recentActiveEnergyKcals: recentActiveEnergyKcals,
            inactivityDuration: inactivityDuration
        )
        return result.state
    }

    func estimate(
        recentHeartRatesBPM: [Double],
        recentActiveEnergyKcals: [Double],
        inactivityDuration: TimeInterval
    ) -> (state: SleepState, probability: Double) {
        // Compute robust features that are resilient to spikes/noise
        let heartRateMedian = median(recentHeartRatesBPM)
        let totalEnergy = recentActiveEnergyKcals.reduce(0, +)
        let hasSufficientInactivity = inactivityDuration >= requiredInactivityWindow

        let lowHeartRate = (heartRateMedian != nil) ? (heartRateMedian! < lowHeartRateThresholdBPM) : false
        // Consider "very low motion" only when we actually have motion samples
        let veryLowMotion = (!recentActiveEnergyKcals.isEmpty) && (totalEnergy < lowMotionEnergyThresholdKcalsPer10Min)

        // Combine signals into a probability-like score [0, 1]
        var probability: Double = 0
        if lowHeartRate { probability += 0.45 }
        if veryLowMotion { probability += 0.35 }
        if hasSufficientInactivity { probability += 0.35 }
        probability = min(1.0, probability)

        // Map probability and signals to qualitative state
        // - likelyAsleep: strong agreement across signals
        // - drowsy: partial agreement suggests risk
        // - awake: weak/no agreement
        if probability >= 0.9 && (lowHeartRate || veryLowMotion) && hasSufficientInactivity {
            return (.likelyAsleep(probability: probability), probability)
        } else if probability >= 0.55 {
            return (.drowsy(probability: probability), probability)
        } else {
            return (.awake, probability)
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            return sorted[mid]
        }
    }
}


