import ActivityKit
import AudioToolbox
import AVFoundation
import Foundation
import SwiftUI
import UIKit

@MainActor
final class ContentViewModel: ObservableObject {
    enum MonitoringPhase: Equatable {
        case idle
        case watching(start: Date)
        case sleepDetected(start: Date, detectedAt: Date)

        var startDate: Date? {
            switch self {
            case .idle:
                return nil
            case .watching(let start):
                return start
            case .sleepDetected(let start, _):
                return start
            }
        }

        var isMonitoringActive: Bool {
            switch self {
            case .idle:
                return false
            case .watching, .sleepDetected:
                return true
            }
        }

        var isSleepDetected: Bool {
            if case .sleepDetected = self { return true }
            return false
        }

        var primaryEmoji: String {
            switch self {
            case .idle:
                return "😴"
            case .watching:
                return "🕵️"
            case .sleepDetected:
                return "😡"
            }
        }

        var headline: String {
            switch self {
            case .idle:
                return "Monitoring Paused"
            case .watching:
                return "Eyes Wide Open"
            case .sleepDetected:
                return "Wake Up!"
            }
        }
    }

    @Published var isMonitoringEnabled = false
    @Published var healthPermissionStatus: PermissionStatus = .pending
    @Published var liveActivityPermissionStatus: PermissionStatus = .pending
    @Published var heartRatePermissionStatus: PermissionStatus = .pending
    @Published var activeEnergyPermissionStatus: PermissionStatus = .pending
    @Published var isRunningTest = false
    @Published var testStatusMessage = "Turn monitoring on to run the demo."
    @Published var isSoundEnabled = true
    @Published private(set) var monitoringPhase: MonitoringPhase = .idle
    @Published private(set) var monitoringStatusMessage: String = "Monitoring is currently paused."
    @Published var minSleepProbability: Double = 0.7
    @Published var checkIntervalMinutes: Double = 3.0
    @Published var sleepLogs: [SleepCheckLogEntry] = []

    var primaryEmoji: String { monitoringPhase.primaryEmoji }
    var monitoringHeadline: String { monitoringPhase.headline }
    var monitoringStartDate: Date? { monitoringPhase.startDate }
    var isSleepAlertActive: Bool { monitoringPhase.isSleepDetected }

    private let healthPermissionManager: HealthPermissionManaging
    private let sleepDetectionManager: SleepDetectionManaging
    private let defaults: UserDefaults
    private let monitoringStateKey = "com.nosleepy.monitoring.enabled"
    private let soundPreferenceKey = "com.nosleepy.settings.soundEnabled"
    private let minProbabilityKey = "com.nosleepy.settings.minProbability"
    private let checkIntervalKey = "com.nosleepy.settings.checkIntervalMinutes"
    private var shouldRestoreMonitoring = false

    private var monitoringLoopTask: Task<Void, Never>?
    private var hapticsTask: Task<Void, Never>?
    private var testSimulationTask: Task<Void, Never>?
    private var soundLoopTask: Task<Void, Never>?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var audioSessionConfigured = false
    private var liveActivity: Activity<NoSleepyLiveActivityWidgetAttributes>?

    struct SleepCheckLogEntry: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let probability: Double?
        let isSleeping: Bool
        let isError: Bool
    }

    init(
        healthPermissionManager: HealthPermissionManaging = HealthPermissionManager(),
        sleepDetectionManager: SleepDetectionManaging = SleepDetectionManager(),
        defaults: UserDefaults = .standard
    ) {
        self.healthPermissionManager = healthPermissionManager
        self.sleepDetectionManager = sleepDetectionManager
        self.defaults = defaults
        self.shouldRestoreMonitoring = defaults.bool(forKey: monitoringStateKey)

        if defaults.object(forKey: soundPreferenceKey) != nil {
            self.isSoundEnabled = defaults.bool(forKey: soundPreferenceKey)
        } else {
            self.isSoundEnabled = true
            defaults.set(true, forKey: soundPreferenceKey)
        }

        if defaults.object(forKey: minProbabilityKey) != nil {
            let saved = defaults.double(forKey: minProbabilityKey)
            self.minSleepProbability = max(0.1, min(1.0, saved))
        } else {
            self.minSleepProbability = 0.7
            defaults.set(0.7, forKey: minProbabilityKey)
        }
        sleepDetectionManager.setMinCandidateProbability(minSleepProbability)

        if defaults.object(forKey: checkIntervalKey) != nil {
            let saved = defaults.double(forKey: checkIntervalKey)
            self.checkIntervalMinutes = max(1.0, min(10.0, saved))
        } else {
            self.checkIntervalMinutes = 3.0
            defaults.set(3.0, forKey: checkIntervalKey)
        }

        setDefaultTestMessage()
        if shouldRestoreMonitoring {
            testStatusMessage = "Restoring monitoring…"
        }

        Task { [weak self] in
            await self?.refreshHealthPermissionStatus(animated: false)
        }
    }

    // MARK: - Settings
    func updateMinSleepProbability(_ value: Double) {
        let clamped = max(0.1, min(1.0, value))
        if abs(clamped - minSleepProbability) > .ulpOfOne {
            minSleepProbability = clamped
            defaults.set(clamped, forKey: minProbabilityKey)
            sleepDetectionManager.setMinCandidateProbability(clamped)
#if DEBUG
            print("[NoSleepy][VM] Min probability updated to \(String(format: "%.2f", clamped))")
#endif
        }
    }

    func updateCheckIntervalMinutes(_ value: Double) {
        let clamped = max(1.0, min(10.0, value))
        if abs(clamped - checkIntervalMinutes) > .ulpOfOne {
            checkIntervalMinutes = clamped
            defaults.set(clamped, forKey: checkIntervalKey)
#if DEBUG
            print("[NoSleepy][VM] Interval updated to \(Int(clamped))m")
#endif
            if monitoringPhase.isMonitoringActive {
                startMonitoringLoop()
            }
        }
    }

    // MARK: - Logging
    private func appendSleepLog(isSleeping: Bool) {
        let snapshot = sleepDetectionManager.lastEvaluationSnapshot()
        let entry = SleepCheckLogEntry(
            timestamp: snapshot?.timestamp ?? Date(),
            probability: snapshot?.probability,
            isSleeping: isSleeping,
            isError: (snapshot == nil) || (snapshot?.hadMissingData == true)
        )
        sleepLogs.append(entry)
        pruneOldLogs()
#if DEBUG
        if entry.isError {
            print("[NoSleepy][Log] \(entry.timestamp) Partial data")
        } else {
            let p = entry.probability ?? 0
            print("[NoSleepy][Log] \(entry.timestamp) Sleep probability \(String(format: "%.2f", p)) -> \(entry.isSleeping ? "Sleepy!" : "No Sleepy")")
        }
#endif
    }

    private func pruneOldLogs() {
        let cutoff = Date().addingTimeInterval(-3600) // last 1 hour
        sleepLogs = sleepLogs.filter { $0.timestamp >= cutoff }
        // Keep UI performant
        if sleepLogs.count > 240 {
            sleepLogs.removeFirst(sleepLogs.count - 240)
        }
    }

    func onAppear() async {
        await refreshHealthPermissionStatus(animated: false)
        await requestSleepPermissionIfNeeded()
        await NotificationManager.shared.prepareIfNeeded()
        refreshLiveActivityPermissionStatus(animated: false)

        if shouldRestoreMonitoring {
            shouldRestoreMonitoring = false
            await handleMonitoringToggle(true)
        }
    }

    func handleMonitoringToggle(_ isOn: Bool) async {
        if isOn {
            let prerequisitesSatisfied = await ensureMonitoringPrerequisites()
            guard prerequisitesSatisfied else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isMonitoringEnabled = false
                }
                persistMonitoringState(false)
                setDefaultTestMessage()
                return
            }
            await startMonitoring()
        } else {
            await stopMonitoring()
        }
    }

    func handleHealthPermissionAction() {
        switch healthPermissionStatus {
        case .pending:
            Task { await requestSleepPermission() }
        case .denied:
            openSettings()
        case .granted:
            break
        }
    }

    func handleHeartRatePermissionAction() {
        switch heartRatePermissionStatus {
        case .pending:
            Task { await requestHeartRatePermission() }
        case .denied:
            openSettings()
        case .granted:
            break
        }
    }

    func handleActiveEnergyPermissionAction() {
        switch activeEnergyPermissionStatus {
        case .pending:
            Task { await requestActiveEnergyPermission() }
        case .denied:
            openSettings()
        case .granted:
            break
        }
    }

    func sceneDidBecomeActive() async {
        await refreshHealthPermissionStatus()
        await refreshSpecificHealthPermissionStatuses()
        refreshLiveActivityPermissionStatus()
    }

    private func startMonitoring() async {
        let startDate = Date()
        withAnimation(.easeInOut(duration: 0.3)) {
            isMonitoringEnabled = true
        }
#if DEBUG
        print("[NoSleepy][VM] Monitoring started at \(startDate). Interval=\(Int(checkIntervalMinutes))m, MinProb=\(String(format: "%.2f", minSleepProbability))")
#endif
        persistMonitoringState(true)
        setDefaultTestMessage()
        setMonitoringPhase(.watching(start: startDate), message: "Watching for drowsiness patterns...")
        await startLiveActivity(startedAt: startDate)
        startMonitoringLoop()
    }

    private func stopMonitoring() async {
        monitoringLoopTask?.cancel()
        monitoringLoopTask = nil
#if DEBUG
        print("[NoSleepy][VM] Monitoring stopped")
#endif
        stopHapticsLoop()
        stopSoundLoop()
        cancelTestSimulation(resetMessage: false)

        withAnimation(.easeInOut(duration: 0.3)) {
            isMonitoringEnabled = false
        }
        persistMonitoringState(false)
        setDefaultTestMessage()
        setMonitoringPhase(.idle, message: "Monitoring is currently paused.")

        let finalState = NoSleepyLiveActivityWidgetAttributes.ContentState(
            isMonitoring: false,
            isSleepDetected: false,
            monitoringStartTime: nil,
            statusMessage: "Monitoring paused."
        )
        let finalContent = ActivityContent(state: finalState, staleDate: nil)
        await liveActivity?.end(finalContent, dismissalPolicy: .immediate)
        liveActivity = nil
        refreshLiveActivityPermissionStatus()
    }

    private func startMonitoringLoop() {
        monitoringLoopTask?.cancel()
        monitoringLoopTask = Task { [weak self] in
            guard let strongSelf = self else { return }
#if DEBUG
            print("[NoSleepy][VM] Loop started with interval \(Int(strongSelf.checkIntervalMinutes))m")
#endif
            while !Task.isCancelled {
                let isSleeping = await strongSelf.sleepDetectionManager.isUserLikelySleeping()
                await MainActor.run {
                    strongSelf.processDetectionResult(isSleeping)
                    strongSelf.appendSleepLog(isSleeping: isSleeping)
                }
                // Poll at the configured interval (1–10 minutes) to balance latency and battery.
                let seconds = max(60, min(600, Int(strongSelf.checkIntervalMinutes * 60)))
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            }
        }
    }

    private func processDetectionResult(_ isSleeping: Bool) {
        if isRunningTest {
            cancelTestSimulation(resetMessage: false)
        }

        switch (monitoringPhase, isSleeping) {
        case (.idle, _):
            break
        case (.watching(let start), true):
            setMonitoringPhase(.sleepDetected(start: start, detectedAt: Date()), message: "Wake up! Sleep signature detected.")
            startHapticsLoop()
            startSoundLoop()
            NotificationManager.shared.notifySleepDetected()
            testStatusMessage = "Live alert active."
        case (.sleepDetected(let start, _), false):
            stopHapticsLoop()
            stopSoundLoop()
            setMonitoringPhase(.watching(start: start), message: "Back on watch. Stay focused!")
            setDefaultTestMessage()
        case (.sleepDetected, true):
            // Continue alerting
            startSoundLoop()
            break
        case (.watching, false):
            stopSoundLoop()
            setMonitoringPhase(monitoringPhase, message: "Watching for drowsiness patterns...")
            setDefaultTestMessage()
        }
    }

    private func setMonitoringPhase(_ phase: MonitoringPhase, message: String) {
        monitoringPhase = phase
        monitoringStatusMessage = message
        updateLiveActivity(for: phase, message: message)
    }

    private func startLiveActivity(startedAt startDate: Date) async {
        let authorizationInfo = ActivityAuthorizationInfo()
        guard authorizationInfo.areActivitiesEnabled else {
            let message = "Live Activities are disabled. Turn them on in Settings ▸ Face ID & Passcode ▸ Live Activities."
            setMonitoringPhase(.watching(start: startDate), message: message)
            withAnimation(.easeInOut(duration: 0.3)) {
                liveActivityPermissionStatus = .denied
            }
            if !isRunningTest {
                testStatusMessage = "Enable Live Activities in Settings to run the demo."
            }
            return
        }

        let attributes = NoSleepyLiveActivityWidgetAttributes(title: "NoSleepy")
        let contentState = NoSleepyLiveActivityWidgetAttributes.ContentState(
            isMonitoring: true,
            isSleepDetected: false,
            monitoringStartTime: startDate,
            statusMessage: "Watching for drowsiness patterns..."
        )

        do {
            liveActivity = try Activity<NoSleepyLiveActivityWidgetAttributes>.request(
                attributes: attributes,
                contentState: contentState
            )
            withAnimation(.easeInOut(duration: 0.3)) {
                liveActivityPermissionStatus = .granted
            }
        } catch {
            let message = "Couldn't start Live Activity (\(error.localizedDescription)). Check capabilities and try again."
            setMonitoringPhase(.watching(start: startDate), message: message)
            withAnimation(.easeInOut(duration: 0.3)) {
                liveActivityPermissionStatus = .denied
            }
            if !isRunningTest {
                testStatusMessage = "Enable Live Activities in Settings to run the demo."
            }
        }
    }

    private func updateLiveActivity(for phase: MonitoringPhase, message: String) {
        let contentState = NoSleepyLiveActivityWidgetAttributes.ContentState(
            isMonitoring: phase.isMonitoringActive,
            isSleepDetected: phase.isSleepDetected,
            monitoringStartTime: phase.startDate,
            statusMessage: message
        )

        Task {
            let activityContent = ActivityContent(state: contentState, staleDate: nil)
            await liveActivity?.update(activityContent)
        }
    }

    private func startHapticsLoop() {
        guard hapticsTask == nil else { return }
        hapticsTask = Task.detached(priority: .high) {
            while !Task.isCancelled {
                let burstEnd = Date().addingTimeInterval(3)
                while Date() < burstEnd && !Task.isCancelled {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopHapticsLoop() {
        hapticsTask?.cancel()
        hapticsTask = nil
    }

    private func ensureMonitoringPrerequisites() async -> Bool {
        await refreshHealthPermissionStatus()
        refreshLiveActivityPermissionStatus()
        switch healthPermissionStatus {
        case .granted:
            return true
        case .pending:
            await requestSleepPermission()
            return healthPermissionStatus == .granted
        case .denied:
            setMonitoringPhase(.idle, message: "Enable sleep access in Settings to start monitoring.")
            testStatusMessage = "Enable sleep access in Settings to run the demo."
            return false
        }
    }

    private func refreshHealthPermissionStatus(animated: Bool = true) async {
        let status = await healthPermissionManager.currentSleepPermissionStatus()
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                healthPermissionStatus = status
            }
        } else {
            healthPermissionStatus = status
        }
    }

    private func refreshSpecificHealthPermissionStatuses(animated: Bool = true) async {
        async let hr = healthPermissionManager.currentHeartRatePermissionStatus()
        async let ae = healthPermissionManager.currentActiveEnergyPermissionStatus()
        let (hrStatus, aeStatus) = await (hr, ae)
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                heartRatePermissionStatus = hrStatus
                activeEnergyPermissionStatus = aeStatus
            }
        } else {
            heartRatePermissionStatus = hrStatus
            activeEnergyPermissionStatus = aeStatus
        }
    }

    private func requestSleepPermissionIfNeeded() async {
        guard healthPermissionStatus == .pending else { return }
        await requestSleepPermission()
    }

    private func requestSleepPermission() async {
        let status = await healthPermissionManager.requestSleepPermission()
        withAnimation(.easeInOut(duration: 0.45)) {
            healthPermissionStatus = status
        }
        guard status == .granted else {
            setMonitoringPhase(.idle, message: "Sleep access is required to monitor. Update permissions in Settings.")
            persistMonitoringState(false)
            testStatusMessage = "Sleep access is required to run the demo."
            return
        }
        // Register background observers after permission is granted
        sleepDetectionManager.registerHealthObservers()
        await refreshSpecificHealthPermissionStatuses(animated: true)
    }

    private func requestHeartRatePermission() async {
        let status = await healthPermissionManager.requestHeartRatePermission()
        withAnimation(.easeInOut(duration: 0.45)) {
            heartRatePermissionStatus = status
        }
        await refreshHealthPermissionStatus(animated: true)
    }

    private func requestActiveEnergyPermission() async {
        let status = await healthPermissionManager.requestActiveEnergyPermission()
        withAnimation(.easeInOut(duration: 0.45)) {
            activeEnergyPermissionStatus = status
        }
        await refreshHealthPermissionStatus(animated: true)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshLiveActivityPermissionStatus(animated: Bool = true) {
        let authorizationInfo = ActivityAuthorizationInfo()
        let status: PermissionStatus = authorizationInfo.areActivitiesEnabled ? .granted : .denied
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                liveActivityPermissionStatus = status
            }
        } else {
            liveActivityPermissionStatus = status
        }

        if status == .denied && !isRunningTest {
            testStatusMessage = "Enable Live Activities in Settings to run the demo."
        } else if status == .granted && !isRunningTest {
            setDefaultTestMessage()
        }
    }

    func runSleepDetectionTest() {
        guard !isRunningTest else { return }
        guard isMonitoringEnabled else {
            setDefaultTestMessage()
            return
        }

        cancelTestSimulation(resetMessage: false)
        isRunningTest = true
        testStatusMessage = "Test running… wake-up alert in 5 seconds."

        let start = monitoringPhase.startDate ?? Date()
        let currentPhase: MonitoringPhase
        switch monitoringPhase {
        case .idle:
            currentPhase = .watching(start: start)
        default:
            currentPhase = monitoringPhase
        }
        setMonitoringPhase(currentPhase, message: "Test running… wake-up alert in 5 seconds.")

        testSimulationTask?.cancel()
        testSimulationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            guard let strongSelf = self else { return }
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.triggerTestAlarm(from: start)
            }

            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            guard let strongSelf = self else { return }
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.stopHapticsLoop()
                strongSelf.stopSoundLoop()
                if strongSelf.isMonitoringEnabled {
                    strongSelf.setMonitoringPhase(.watching(start: start), message: "Test complete. Monitoring resumed.")
                } else {
                    strongSelf.setMonitoringPhase(.idle, message: "Monitoring is currently paused.")
                }
                strongSelf.isRunningTest = false
                strongSelf.testStatusMessage = "Test complete. You're ready!"
            }

            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            guard let strongSelf = self else { return }
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let strongSelf = self else { return }
                if !strongSelf.isRunningTest {
                    strongSelf.setDefaultTestMessage()
                }
                strongSelf.testSimulationTask = nil
            }
        }
    }

    private func triggerTestAlarm(from start: Date) {
        setMonitoringPhase(.sleepDetected(start: start, detectedAt: Date()), message: "Wake up! Test alert triggered.")
        startHapticsLoop()
        startSoundLoop()
        NotificationManager.shared.notifySleepDetected()
        testStatusMessage = "Wake up! Test alert triggered."
    }

    private func cancelTestSimulation(resetMessage: Bool = true) {
        testSimulationTask?.cancel()
        testSimulationTask = nil
        if isRunningTest {
            isRunningTest = false
        }
        if resetMessage {
            setDefaultTestMessage()
        }
        if !monitoringPhase.isSleepDetected {
            stopSoundLoop()
        }
    }

    func updateSoundPreference(_ isOn: Bool) {
        isSoundEnabled = isOn
        defaults.set(isOn, forKey: soundPreferenceKey)
        if isOn {
            if monitoringPhase.isSleepDetected {
                startSoundLoop()
            }
        } else {
            stopSoundLoop()
        }
    }

    private func setDefaultTestMessage() {
        if liveActivityPermissionStatus == .denied && !isRunningTest {
            testStatusMessage = "Enable Live Activities in Settings to run the demo."
        } else if isMonitoringEnabled {
            testStatusMessage = "Tap Run Test to experience the wake-up alert."
        } else {
            testStatusMessage = "Turn monitoring on to run the demo."
        }
    }

    private func persistMonitoringState(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: monitoringStateKey)
    }

    private func startSoundLoop() {
        guard isSoundEnabled else { return }
        guard soundLoopTask == nil else { return }

        configureAudioSessionIfNeeded()

        soundLoopTask = Task.detached(priority: .high) { [weak self] in
            while !Task.isCancelled {
                guard let strongSelf = self else { return }
                if Task.isCancelled { return }
                await strongSelf.speakWakeUpCue()
                AudioServicesPlaySystemSound(1304)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopSoundLoop() {
        soundLoopTask?.cancel()
        soundLoopTask = nil

        Task { @MainActor [weak self] in
            guard let strongSelf = self else { return }
            if strongSelf.speechSynthesizer.isSpeaking {
                strongSelf.speechSynthesizer.stopSpeaking(at: .immediate)
            }
        }

        deactivateAudioSessionIfPossible()
    }

    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.audioSessionConfigured else { return }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                if (try? session.setActive(true, options: [])) != nil {
                    self.audioSessionConfigured = true
                }
            } catch {
                #if DEBUG
                print("[NoSleepy] Failed to configure audio session category: \(error)")
                #endif
            }
        }
    }

    private func deactivateAudioSessionIfPossible() {
        guard audioSessionConfigured else { return }
        guard soundLoopTask == nil else { return }
        DispatchQueue.main.async {
            do {
                let session = AVAudioSession.sharedInstance()
                _ = try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                #if DEBUG
                print("[NoSleepy] Failed to deactivate audio session category: \(error)")
                #endif
            }
        }
        audioSessionConfigured = false
    }

    @MainActor
    private func speakWakeUpCue() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: "Wake up now!")
        if let voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode()) {
            utterance.voice = voice
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.7
        utterance.volume = 1.0
        speechSynthesizer.speak(utterance)
    }

    // MARK: - User Activity
    func noteUserInteraction() {
        sleepDetectionManager.noteUserInteraction()
    }
}
