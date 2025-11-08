//
//  HealthPermissionManager.swift
//  NoSleepy
//
//  Created by GPT-5 Codex on 08/11/2025.
//

import Foundation
import HealthKit

protocol HealthPermissionManaging {
    func currentSleepPermissionStatus() async -> PermissionStatus
    func requestSleepPermission() async -> PermissionStatus
}

final class HealthPermissionManager: HealthPermissionManaging {
    private let healthStore = HKHealthStore()
    private let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)

    func currentSleepPermissionStatus() async -> PermissionStatus {
        // isHealthDataAvailable() only checks if HealthKit exists on device, not permissions
        guard HKHealthStore.isHealthDataAvailable(), let sleepType else {
            return .denied
        }
        
        // Check if user has been prompted yet
        let needsPrompt = await needsAuthorizationPrompt(for: sleepType)
        if needsPrompt {
            return .pending
        }
        
        // The actual query is the most reliable way to check READ permission
        // authorizationStatus(for:) is more about write/share, not read
        return await verifyReadAccess(for: sleepType)
    }

    func requestSleepPermission() async -> PermissionStatus {
        guard HKHealthStore.isHealthDataAvailable(), let sleepType else {
            return .denied
        }

        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: [sleepType]) { _, _ in
                Task {
                    // Give the system a tick to finalize state after dismissal
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    let status = await self.currentSleepPermissionStatus()
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func verifyReadAccess(for type: HKCategoryType) async -> PermissionStatus {
        // Execute actual query - this is the ONLY reliable way to check READ permission
        // authorizationStatus(for:) reflects write/share, not read access
        return await withCheckedContinuation { continuation in
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
            ) { _, results, error in
                // The query error is the definitive source for read permission
                if let hkError = error as? HKError {
                    switch hkError.code {
                    case .errorAuthorizationDenied:
                        // User explicitly denied read access
                        continuation.resume(returning: .denied)
                        return
                    case .errorAuthorizationNotDetermined:
                        // Haven't asked yet
                        continuation.resume(returning: .pending)
                        return
                    default:
                        // Other errors - treat as pending to be safe
                        continuation.resume(returning: .pending)
                        return
                    }
                }
                
                // Query succeeded (even with 0 results) = read permission granted
                continuation.resume(returning: .granted)
            }

            healthStore.execute(query)
        }
    }

    private func needsAuthorizationPrompt(for type: HKCategoryType) async -> Bool {
        await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: [type]) { status, _ in
                let needsPrompt = (status == .shouldRequest)
                continuation.resume(returning: needsPrompt)
            }
        }
    }
}

extension HealthPermissionManager: @unchecked Sendable {}


