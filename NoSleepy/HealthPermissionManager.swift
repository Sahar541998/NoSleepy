import Foundation
import HealthKit

protocol HealthPermissionManaging {
    func currentSleepPermissionStatus() async -> PermissionStatus
    func requestSleepPermission() async -> PermissionStatus
    // Per-signal queries for granular UI
    func currentHeartRatePermissionStatus() async -> PermissionStatus
    func currentActiveEnergyPermissionStatus() async -> PermissionStatus
    func requestHeartRatePermission() async -> PermissionStatus
    func requestActiveEnergyPermission() async -> PermissionStatus
}

final class HealthPermissionManager: HealthPermissionManaging {
    private let healthStore = HKHealthStore()
    // We no longer rely on sleepAnalysis; instead we read heart rate and motion-related energy.
    private let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)
    private let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)

    func currentSleepPermissionStatus() async -> PermissionStatus {
        // isHealthDataAvailable() only checks if HealthKit exists on device, not permissions
        guard HKHealthStore.isHealthDataAvailable() else {
            return .denied
        }

        let readableTypes = [heartRateType, activeEnergyType].compactMap { $0 }
        guard !readableTypes.isEmpty else { return .denied }

        // If ANY type suggests we should request, surface Pending to prompt the user.
        let shouldRequestAny = await needsAuthorizationPrompt(for: readableTypes)
        if shouldRequestAny { return .pending }

        // Consider status granted if we have read access to at least one data type,
        // because we can operate with partial signals (e.g., motion only).
        let statuses = await verifyReadAccess(for: readableTypes)
        if statuses.contains(.granted) { return .granted }
        if statuses.contains(.pending) { return .pending }
        return .denied
    }

    // MARK: - Per-signal APIs
    func currentHeartRatePermissionStatus() async -> PermissionStatus {
        guard HKHealthStore.isHealthDataAvailable(), let heartRateType else { return .denied }
        if await needsAuthorizationPrompt(for: [heartRateType]) { return .pending }
        return await verifyReadAccess(for: heartRateType)
    }

    func currentActiveEnergyPermissionStatus() async -> PermissionStatus {
        guard HKHealthStore.isHealthDataAvailable(), let activeEnergyType else { return .denied }
        if await needsAuthorizationPrompt(for: [activeEnergyType]) { return .pending }
        return await verifyReadAccess(for: activeEnergyType)
    }

    func requestHeartRatePermission() async -> PermissionStatus {
        guard HKHealthStore.isHealthDataAvailable(), let heartRateType else { return .denied }
        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: [heartRateType]) { _, _ in
                Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    let status = await self.currentHeartRatePermissionStatus()
                    continuation.resume(returning: status)
                }
            }
        }
    }

    func requestActiveEnergyPermission() async -> PermissionStatus {
        guard HKHealthStore.isHealthDataAvailable(), let activeEnergyType else { return .denied }
        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: [activeEnergyType]) { _, _ in
                Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    let status = await self.currentActiveEnergyPermissionStatus()
                    continuation.resume(returning: status)
                }
            }
        }
    }

    func requestSleepPermission() async -> PermissionStatus {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .denied
        }

        return await withCheckedContinuation { continuation in
            let readableTypes = Set([heartRateType, activeEnergyType].compactMap { $0 })
            healthStore.requestAuthorization(toShare: [], read: readableTypes) { _, _ in
                Task {
                    // Give the system a tick to finalize state after dismissal
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    let status = await self.currentSleepPermissionStatus()
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func verifyReadAccess(for types: [HKSampleType]) async -> [PermissionStatus] {
        await withTaskGroup(of: PermissionStatus.self, returning: [PermissionStatus].self) { group in
            for type in types {
                group.addTask { await self.verifyReadAccess(for: type) }
            }
            var results: [PermissionStatus] = []
            for await status in group {
                results.append(status)
            }
            return results
        }
    }

    private func verifyReadAccess(for type: HKSampleType) async -> PermissionStatus {
        // Execute actual query - this is the ONLY reliable way to check READ permission
        // authorizationStatus(for:) reflects write/share, not read access
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: Date(timeIntervalSince1970: 0),
                end: Date(),
                options: []
            )
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, _, error in
                if let hkError = error as? HKError {
                    switch hkError.code {
                    case .errorAuthorizationDenied:
                        continuation.resume(returning: .denied)
                        return
                    case .errorAuthorizationNotDetermined:
                        continuation.resume(returning: .pending)
                        return
                    default:
                        continuation.resume(returning: .pending)
                        return
                    }
                }
                continuation.resume(returning: .granted)
            }
            healthStore.execute(query)
        }
    }

    private func needsAuthorizationPrompt(for types: [HKSampleType]) async -> Bool {
        await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for type in types {
                group.addTask {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                        self.healthStore.getRequestStatusForAuthorization(toShare: [], read: [type]) { status, _ in
                            continuation.resume(returning: status == .shouldRequest)
                        }
                    }
                }
            }
            for await should in group {
                if should { return true }
            }
            return false
        }
    }
}

extension HealthPermissionManager: @unchecked Sendable {}


