// TimeTrackingManager.swift
// Cadence
//

import Foundation
import SwiftData
import Combine
import UIKit
import UserNotifications
import AudioToolbox
import AVFoundation

// MARK: - TimeTrackingManager

@MainActor
class TimeTrackingManager: ObservableObject {

    // MARK: - Properties

    private var modelContext: ModelContext

    @Published var currentTimeBlock: TimeBlock?
    @Published var activeSet: ActivitySet?
    @Published var currentTimeBlockRule: TimeBlockRule?
    
    // MARK: Retrospective State
    
    /// In retrospective mode, this is the "zero point" — the start of unlabeled time.
    @Published var retrospectiveAnchorTime: Date?
    
    /// Accumulated pause duration within the current unlabeled period.
    @Published var retrospectivePauseDuration: TimeInterval = 0
    
    /// Pause state for retrospective mode
    @Published var retrospectiveIsPaused: Bool = false
    @Published var retrospectivePauseStart: Date?

    private var backgroundEnteredTime: Date?
    var maxBackgroundDuration: TimeInterval {
        let saved = UserDefaults.standard.double(forKey: "maxBackgroundDuration")
        return saved > 0 ? saved : 900 // Default to 15 mins (900 seconds)
    }

    /// Maximum pause duration before the activity is auto-stopped. (15 min)
    private let maxPauseDuration: TimeInterval = 900

    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notificationsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
    }
    
    /// The entry mode of the currently active set.
    @Published var currentEntryMode: EntryMode = .prospective {
        didSet { UserDefaults.standard.set(currentEntryMode.rawValue, forKey: "savedEntryMode") }
    }
    
    /// Elapsed unlabeled time in retrospective mode.
    var unlabeledDuration: TimeInterval {
        guard let anchor = retrospectiveAnchorTime else { return 0 }
        let raw = Date().timeIntervalSince(anchor)
        let currentPause = retrospectiveIsPaused
            ? Date().timeIntervalSince(retrospectivePauseStart ?? Date())
            : 0
        return max(0, raw - retrospectivePauseDuration - currentPause)
    }
    
    private var timer: Timer?
    private let historyManager = HistoryManager.shared

    /// Audio player for foreground timer completion sound
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext

        if UserDefaults.standard.object(forKey: "notificationsEnabled") == nil {
            notificationsEnabled = true
        }
        
        let savedMode = UserDefaults.standard.string(forKey: "savedEntryMode") ?? EntryMode.prospective.rawValue
        self.currentEntryMode = EntryMode(rawValue: savedMode) ?? .prospective

        loadSettings()
        loadRetrospectiveState()
        resumeActiveTimeBlock()
        startTimer()
        setupBackgroundTracking()
        checkAndApplyCurrentTimeBlockRule()
    }

    // MARK: - Settings

    private func loadSettings() {
        if let ts = UserDefaults.standard.object(forKey: "backgroundEnteredTime") as? Double {
            backgroundEnteredTime = Date(timeIntervalSince1970: ts)
        }
    }

    private func saveBackgroundState() {
        UserDefaults.standard.set(
            backgroundEnteredTime?.timeIntervalSince1970,
            forKey: "backgroundEnteredTime"
        )
    }

    private func clearBackgroundState() {
        backgroundEnteredTime = nil
        UserDefaults.standard.removeObject(forKey: "backgroundEnteredTime")
    }

    // MARK: - Keep Screen On

    /// Call this whenever tracking state changes to update idle timer.
    func updateIdleTimerState() {
        let keepScreenOn = UserDefaults.standard.bool(forKey: "keepScreenOnWhileTracking")
        
        let isProspectiveTracking = currentTimeBlock != nil && currentTimeBlock?.endTime == nil
        let isRetrospectiveTracking = currentEntryMode == .retrospective && retrospectiveAnchorTime != nil && !retrospectiveIsPaused
        
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && (isProspectiveTracking || isRetrospectiveTracking)
    }

    // MARK: - Set Auto-Switching

    func getActiveTimeBlockRule() -> TimeBlockRule? {
        let descriptor = FetchDescriptor<TimeBlockRule>(
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        guard let rules = try? modelContext.fetch(descriptor) else { return nil }
        return rules.first(where: { $0.isActiveNow() })
    }
    
    /// Called by the UI when the user manually picks a new set from the dropdown.
    func manualSwitchToSet(_ set: ActivitySet) {
        executeSetSwitch(to: set)
    }

    /// The core engine for changing the active set and handling mode transitions.
    private func executeSetSwitch(to targetSet: ActivitySet) {
        let sets = try? modelContext.fetch(FetchDescriptor<ActivitySet>())
        sets?.forEach { $0.isActive = false }
        targetSet.isActive = true
        activeSet = targetSet
        saveContext()
    }
    
    func toggleEntryMode(to newMode: EntryMode) {
        let previousMode = currentEntryMode
        guard previousMode != newMode else { return }

        currentEntryMode = newMode

        if previousMode == .prospective && newMode == .retrospective {
            let anchorTime: Date
            if let current = currentTimeBlock, current.endTime == nil {
                let now = Date()
                if current.isPaused { closePause(on: current, at: now) }
                current.endTime = now
                current.stopState = "switched"
                currentTimeBlock = nil
                anchorTime = now
                cancelTargetAlarm()
            } else {
                anchorTime = Date()
            }
            startRetrospectiveAnchor(at: anchorTime)

        } else if previousMode == .retrospective && newMode == .prospective {
            clearRetrospectiveAnchor()
        }

        if newMode == .retrospective && retrospectiveAnchorTime == nil {
            startRetrospectiveAnchor(at: Date())
        }

        updateIdleTimerState()
    }

    // MARK: - Unified Activity Management Handlers
    
    /// Called when the user taps an activity button.
    /// Routes to the correct behavior based on the active set's entry mode.
    func handleActivityTap(_ activity: Activity) {
        switch currentEntryMode {
        case .prospective:
            startActivity(activity)

        case .retrospective:
            // If there's no anchor yet, initialize from midnight
            if retrospectiveAnchorTime == nil {
                let midnight = Calendar.current.startOfDay(for: Date())
                startRetrospectiveAnchor(at: midnight)
            }
            labelRetrospectiveBlock(activity: activity)
        }
    }

    /// Called when the user taps pause.
    func handlePauseTap() {
        switch currentEntryMode {
        case .prospective:
            pauseCurrentActivity()
        case .retrospective:
            pauseRetrospective()
        }
    }

    /// Called when the user taps resume.
    func handleResumeTap() {
        switch currentEntryMode {
        case .prospective:
            resumeFromPause()
        case .retrospective:
            resumeRetrospective()
        }
    }

    /// Called when the user taps stop.
    func handleStopTap() {
        switch currentEntryMode {
        case .prospective:
            stopCurrentActivity()
        case .retrospective:
            // In retrospective mode, "stop" discards the unlabeled time
            // and clears the anchor. The user is saying "I'm done tracking."
            clearRetrospectiveAnchor()
            updateIdleTimerState()
        }
    }

    // MARK: - Prospective Tracking

    /// Start tracking an activity prospectively.
    func startActivity(_ activity: Activity, targetDuration: TimeInterval? = nil) {
        let now = Date()

        if let current = currentTimeBlock, current.isPaused {
            closePause(on: current, at: now)
        }

        endCurrentActivityIfNeeded(at: now, state: "switched")

        let newBlock = TimeBlock(activity: activity, startTime: now)
        newBlock.targetDuration = targetDuration
        modelContext.insert(newBlock)
        currentTimeBlock = newBlock

        clearBackgroundState()
        cancelInactivityReminder()
        saveAndInvalidate(date: now)
        updateIdleTimerState()

        if let target = targetDuration {
            scheduleTargetAlarm(duration: target, activityName: activity.name)
        } else {
            cancelTargetAlarm()
        }
    }

    func setTargetDuration(for block: TimeBlock, duration: TimeInterval?) {
        block.targetDuration = duration
        saveContext()

        if let target = duration {
            let remaining = max(0, target - block.duration)
            if remaining > 0 {
                scheduleTargetAlarm(duration: remaining, activityName: block.activityName)
            }
        } else {
            cancelTargetAlarm()
        }
    }

    private func checkTargetDuration() {
        guard let current = currentTimeBlock, let target = current.targetDuration else { return }
        guard !current.isPaused else { return }

        if current.duration >= target {
            current.targetDuration = nil
            stopCurrentActivity()

            HapticManager.shared.notification(type: .success)
            playTimerCompletionSound()
        }
    }
    
    // MARK: - Retrospective Tracking
    
    /// Retrospective mode: label the unlabeled period as the given activity.
    func labelRetrospectiveBlock(activity: Activity) {
        let now = Date()

        guard let anchor = retrospectiveAnchorTime else {
            let midnight = Calendar.current.startOfDay(for: now)
            startRetrospectiveAnchor(at: midnight)
            labelRetrospectiveBlock(activity: activity)
            return
        }

        if retrospectiveIsPaused {
            closeRetrospectivePause(at: now)
        }

        let block = TimeBlock(activity: activity, startTime: anchor)
        block.endTime = now
        block.stopState = "stopped"
        block.totalPauseDuration = retrospectivePauseDuration
        modelContext.insert(block)

        retrospectiveAnchorTime = now
        retrospectivePauseDuration = 0
        retrospectiveIsPaused = false
        retrospectivePauseStart = nil

        saveRetrospectiveState()
        saveAndInvalidate(date: now)
        updateIdleTimerState()
    }
    
    func startRetrospectiveAnchor(at time: Date) {
        retrospectiveAnchorTime = time
        retrospectivePauseDuration = 0
        retrospectiveIsPaused = false
        retrospectivePauseStart = nil
        saveRetrospectiveState()
    }

    func clearRetrospectiveAnchor() {
        clearRetrospectiveState()
        retrospectiveIsPaused = false
        retrospectivePauseStart = nil
    }
    
    func getLastCompletedBlock() -> TimeBlock? {
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.endTime != nil },
            sortBy: [SortDescriptor(\.endTime, order: .reverse)]
        )
        var fetchDescriptor = descriptor
        fetchDescriptor.fetchLimit = 1
        return try? modelContext.fetch(fetchDescriptor).first
    }

    // MARK: - Target Alarm Notification

    private func scheduleTargetAlarm(duration: TimeInterval, activityName: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["targetAlarm"])

        guard duration > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time's Up!"
        content.body = "Your \(activityName) session has ended."
        content.sound = UNNotificationSound.defaultCritical
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: duration, repeats: false)
        let request = UNNotificationRequest(identifier: "targetAlarm", content: content, trigger: trigger)
        center.add(request)
    }

    private func cancelTargetAlarm() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["targetAlarm"])
    }

    private func rescheduleTargetAlarmIfNeeded() {
        guard let current = currentTimeBlock,
              let target = current.targetDuration,
              !current.isPaused else {
            if currentTimeBlock?.targetDuration != nil {
                cancelTargetAlarm()
            }
            return
        }

        let remaining = max(0, target - current.duration)
        if remaining > 0 {
            scheduleTargetAlarm(duration: remaining, activityName: current.activityName)
        }
    }

    // MARK: - Foreground Timer Completion Sound

    private func playTimerCompletionSound() {
        if let url = findAlertSoundURL() {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
                return
            } catch { /* fall through */ }
        }
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }

    private func findAlertSoundURL() -> URL? {
        let paths = [
            "/System/Library/Audio/UISounds/alarm.caf",
            "/System/Library/Audio/UISounds/nano/alarm_nightstand_haptic.caf",
            "/System/Library/Audio/UISounds/SIMToolkitCallDropped.caf"
        ]
        return paths.compactMap { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Pause / Resume (Prospective)

    func pauseCurrentActivity() {
        guard let current = currentTimeBlock,
              !current.isPaused,
              current.endTime == nil else { return }

        current.isPaused = true
        current.pauseStartTime = Date()
        current.pauseCount += 1

        if current.targetDuration != nil {
            cancelTargetAlarm()
        }

        clearBackgroundState()
        saveContext()
        updateIdleTimerState()
    }

    func resumeFromPause() {
        guard let current = currentTimeBlock, current.isPaused else { return }

        closePause(on: current, at: Date())
        saveContext()
        updateIdleTimerState()
        rescheduleTargetAlarmIfNeeded()
    }

    func stopCurrentActivity() {
        guard let current = currentTimeBlock else { return }
        let now = Date()
        if current.isPaused { closePause(on: current, at: now) }

        current.endTime = now
        current.stopState = "stopped"
        currentTimeBlock = nil

        clearBackgroundState()
        saveAndInvalidate(date: now)
        cancelTargetAlarm()
        updateIdleTimerState()
        scheduleInactivityReminder()
    }

    private func closePause(on block: TimeBlock, at time: Date) {
        let elapsed = time.timeIntervalSince(block.pauseStartTime ?? time)
        block.totalPauseDuration += max(0, elapsed)
        block.isPaused = false
        block.pauseStartTime = nil
    }

    private func autostopDueToPauseTimeout(current: TimeBlock) {
        guard let pauseStart = current.pauseStartTime else { return }

        let cappedPauseEnd = pauseStart.addingTimeInterval(maxPauseDuration)
        current.totalPauseDuration += maxPauseDuration
        current.isPaused = false
        current.pauseStartTime = nil
        current.endTime = cappedPauseEnd
        current.stopState = "stopped"
        currentTimeBlock = nil

        saveAndInvalidate(date: cappedPauseEnd)
        notifyPauseTimeout()
        cancelTargetAlarm()
        updateIdleTimerState()
        scheduleInactivityReminder()
    }

    private func endCurrentActivityIfNeeded(at time: Date, state: String) {
        guard let current = currentTimeBlock else { return }
        current.endTime = time
        current.stopState = state
    }
    
    // MARK: - Pause / Resume (Retrospective)

    func pauseRetrospective() {
        guard !retrospectiveIsPaused, retrospectiveAnchorTime != nil else { return }
        retrospectiveIsPaused = true
        retrospectivePauseStart = Date()
        saveRetrospectiveState()
        updateIdleTimerState()
    }

    func resumeRetrospective() {
        guard retrospectiveIsPaused else { return }
        closeRetrospectivePause(at: Date())
        saveRetrospectiveState()
        updateIdleTimerState()
    }

    private func closeRetrospectivePause(at time: Date) {
        let elapsed = time.timeIntervalSince(retrospectivePauseStart ?? time)
        retrospectivePauseDuration += max(0, elapsed)
        retrospectiveIsPaused = false
        retrospectivePauseStart = nil
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }

                let isActivelyTrackingProspective = self.currentTimeBlock != nil && self.currentTimeBlock?.endTime == nil
                let isActivelyTrackingRetrospective = self.currentEntryMode == .retrospective && self.retrospectiveAnchorTime != nil

                if isActivelyTrackingProspective || isActivelyTrackingRetrospective {
                    self.objectWillChange.send()
                }

                self.checkPauseTimeout()
                self.checkAndApplyCurrentTimeBlockRule()
                self.checkTargetDuration()
            }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// Enforce the 15-minute pause limit on every timer tick.
    private func checkPauseTimeout() {
        // Prospective
        if let current = currentTimeBlock,
              current.isPaused,
              let pauseStart = current.pauseStartTime,
              Date().timeIntervalSince(pauseStart) > maxPauseDuration {
            autostopDueToPauseTimeout(current: current)
        }
        
        // Retrospective
        if retrospectiveIsPaused,
           let pauseStart = retrospectivePauseStart,
           Date().timeIntervalSince(pauseStart) > maxPauseDuration {
            
            // Clear the abandoned anchor to avoid accumulating invisible pause time
            clearRetrospectiveAnchor()
            notifyPauseTimeout()
            updateIdleTimerState()
            scheduleInactivityReminder()
        }
    }

    // MARK: - Background Tracking

    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private func setupBackgroundTracking() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        // Handle retrospective save implicitly if needed, mostly it just carries over as long as UserDefaults is updated.
        saveRetrospectiveState()
        
        guard let current = currentTimeBlock, current.endTime == nil else { return }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SaveTrackingState") {
            self.endBackgroundTask()
        }

        backgroundEnteredTime = Date()
        saveBackgroundState()
        saveContext()

        if !current.isPaused {
            scheduleBackgroundReminder {
                self.endBackgroundTask()
            }
        } else {
            endBackgroundTask()
        }
    }

    @objc private func appWillTerminate() {
        saveBackgroundState()
        saveRetrospectiveState()
        saveContext()
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    @objc private func appWillEnterForeground() {
        defer {
            backgroundEnteredTime = nil
            clearBackgroundState()
            cancelBackgroundReminder()
        }
        
        loadRetrospectiveState()

        guard let backgroundTime = backgroundEnteredTime,
              let current = currentTimeBlock else { return }

        let elapsed = Date().timeIntervalSince(backgroundTime)

        if current.isPaused {
            let totalPauseElapsed = Date().timeIntervalSince(current.pauseStartTime ?? backgroundTime)
            if totalPauseElapsed > maxPauseDuration {
                autostopDueToPauseTimeout(current: current)
            }
        } else if elapsed > maxBackgroundDuration {
            handleBackgroundTimeout(current: current, backgroundTime: backgroundTime)
            let cappedEnd = backgroundTime.addingTimeInterval(maxBackgroundDuration)
            saveAndInvalidate(date: cappedEnd)
            checkAndApplyCurrentTimeBlockRule()
            return
        }

        saveContext()
        checkAndApplyCurrentTimeBlockRule()
        rescheduleTargetAlarmIfNeeded()
    }

    private func handleBackgroundTimeout(current: TimeBlock, backgroundTime: Date) {
        let cappedEnd = backgroundTime.addingTimeInterval(maxBackgroundDuration)
        current.endTime = cappedEnd
        current.stopState = "stopped"
        currentTimeBlock = nil
        notifyActivityStopped()
        cancelTargetAlarm()
        updateIdleTimerState()
        scheduleInactivityReminder()
    }

    // MARK: - Session Recovery

    private func resumeActiveTimeBlock() {
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        // Retrospective anchor recovery check is already handled by loadRetrospectiveState in init
        // If app was killed while in retrospective mode without an anchor, we just wait for the first tap.

        guard let activeBlock = try? modelContext.fetch(descriptor).first else {
            cancelBackgroundReminder()
            return
        }
        currentTimeBlock = activeBlock

        if let backgroundTime = backgroundEnteredTime {
            if activeBlock.isPaused {
                let totalPauseElapsed = Date().timeIntervalSince(activeBlock.pauseStartTime ?? backgroundTime)
                if totalPauseElapsed > maxPauseDuration {
                    autostopDueToPauseTimeout(current: activeBlock)
                    clearBackgroundState()
                    cancelBackgroundReminder()
                    return
                }
            } else {
                let elapsed = Date().timeIntervalSince(backgroundTime)
                if elapsed > maxBackgroundDuration {
                    handleBackgroundTimeout(current: activeBlock, backgroundTime: backgroundTime)
                    let cappedEnd = backgroundTime.addingTimeInterval(maxBackgroundDuration)
                    saveAndInvalidate(date: cappedEnd)
                    clearBackgroundState()
                    cancelBackgroundReminder()
                    return
                }
            }
            clearBackgroundState()
        }

        if let target = activeBlock.targetDuration,
           !activeBlock.isPaused,
           activeBlock.duration >= target {
            activeBlock.targetDuration = nil
            activeBlock.endTime = activeBlock.startTime.addingTimeInterval(
                target + activeBlock.totalPauseDuration
            )
            activeBlock.stopState = "stopped"
            currentTimeBlock = nil
            saveAndInvalidate(date: activeBlock.endTime ?? Date())
            cancelTargetAlarm()
            updateIdleTimerState()
            scheduleInactivityReminder()

            notifyTimerCompletedWhileAway(activityName: activeBlock.activityName)
            cancelBackgroundReminder()
            return
        }

        cancelBackgroundReminder()
        updateIdleTimerState()
        rescheduleTargetAlarmIfNeeded()
    }

    // MARK: - Time Block Rule Application
    
    func checkAndApplyCurrentTimeBlockRule() {
        let activeRule = getActiveTimeBlockRule()
        let previousRule = currentTimeBlockRule
        currentTimeBlockRule = activeRule

        // Automatically switch if the rule is active and it's a new rule
        guard let rule = activeRule,
              let setID = rule.linkedSetID,
              previousRule?.id != rule.id else { return }

        let sets = try? modelContext.fetch(FetchDescriptor<ActivitySet>())
        let currentActiveSet = sets?.first { $0.isActive }

        if currentActiveSet?.id != setID,
           let targetSet = sets?.first(where: { $0.id == setID }) {
            
            // This safely transitions the modes!
            executeSetSwitch(to: targetSet)
            notifySetSwitch(setName: targetSet.name, ruleName: rule.name)
        }
    }

    private func switchToActivitySet(_ set: ActivitySet, ruleName: String) {
        let sets = try? modelContext.fetch(FetchDescriptor<ActivitySet>())
        
        sets?.forEach { $0.isActive = false }
        set.isActive = true
        activeSet = set
        saveContext()
        notifySetSwitch(setName: set.name, ruleName: ruleName)
        updateIdleTimerState()
    }
    
    // MARK: - Retrospective State Persistence
    
    private func saveRetrospectiveState() {
        UserDefaults.standard.set(
            retrospectiveAnchorTime?.timeIntervalSince1970,
            forKey: "retrospectiveAnchorTime"
        )
        UserDefaults.standard.set(
            retrospectivePauseDuration,
            forKey: "retrospectivePauseDuration"
        )
        UserDefaults.standard.set(
            retrospectiveIsPaused,
            forKey: "retrospectiveIsPaused"
        )
        UserDefaults.standard.set(
            retrospectivePauseStart?.timeIntervalSince1970,
            forKey: "retrospectivePauseStart"
        )
    }

    private func loadRetrospectiveState() {
        if let ts = UserDefaults.standard.object(forKey: "retrospectiveAnchorTime") as? Double {
            retrospectiveAnchorTime = Date(timeIntervalSince1970: ts)
        }
        retrospectivePauseDuration = UserDefaults.standard.double(forKey: "retrospectivePauseDuration")
        retrospectiveIsPaused = UserDefaults.standard.bool(forKey: "retrospectiveIsPaused")
        if let ps = UserDefaults.standard.object(forKey: "retrospectivePauseStart") as? Double {
            retrospectivePauseStart = Date(timeIntervalSince1970: ps)
        }
    }

    private func clearRetrospectiveState() {
        retrospectiveAnchorTime = nil
        retrospectivePauseDuration = 0
        retrospectiveIsPaused = false
        retrospectivePauseStart = nil
        
        UserDefaults.standard.removeObject(forKey: "retrospectiveAnchorTime")
        UserDefaults.standard.removeObject(forKey: "retrospectivePauseDuration")
        UserDefaults.standard.removeObject(forKey: "retrospectiveIsPaused")
        UserDefaults.standard.removeObject(forKey: "retrospectivePauseStart")
    }

    // MARK: - Data Queries

    func getTodaysTimeBlocks() -> [TimeBlock] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end   = calendar.date(byAdding: .day, value: 1, to: start)!

        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.startTime >= start && $0.startTime < end },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func getTodaysStats() -> DayStats {
        let blocks = getTodaysTimeBlocks()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())

        var activityDurations: [String: TimeInterval] = [:]
        var totalDuration: TimeInterval = 0
        var totalSwitches: Int = 0

        for block in blocks {
            let d = block.duration
            totalDuration += d
            totalSwitches += block.switchCount
            activityDurations[block.activityName, default: 0] += d
        }

        let unaccounted = GapCalculator.totalUnaccountedDuration(
            in: blocks, from: dayStart, to: Date()
        )

        return DayStats(
            totalDuration: totalDuration,
            activityDurations: activityDurations,
            totalSwitches: totalSwitches,
            blockCount: blocks.count,
            unaccountedDuration: unaccounted
        )
    }

    // MARK: - Notifications

    private func scheduleBackgroundReminder(completion: (() -> Void)? = nil) {
        guard notificationsEnabled, maxBackgroundDuration > 300 else {
            completion?()
            return
        }
        let reminderTime = maxBackgroundDuration - 300
        let content = UNMutableNotificationContent()
        content.title = "Cadence Activity Tracking"
        content.body  = "Your activity will stop in 5 minutes. Open the app to continue tracking."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(
            identifier: "backgroundReminder",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: reminderTime, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { _ in
            completion?()
        }
    }

    private func cancelBackgroundReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["backgroundReminder"]
        )
    }

    private func notifyActivityStopped() {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Activity Stopped"
        content.body = "Your activity was stopped after \(maxBackgroundDuration.formattedDuration) in the background."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "activityStopped",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func notifyPauseTimeout() {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Activity Stopped"
        content.body = "Your activity was stopped after a \(maxPauseDuration.formattedDuration) pause."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "pauseTimeout",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func notifySetSwitch(setName: String, ruleName: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Activity Set Changed"
        content.body = "\(ruleName): Switched to \(setName)"
        let request = UNNotificationRequest(
            identifier: "setSwitch",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func notifyTimerCompletedWhileAway(activityName: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Timer Completed"
        content.body = "Your \(activityName) session ended while the app was closed."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "timerCompletedWhileAway",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Inactivity Reminder

    private func scheduleInactivityReminder() {
        guard notificationsEnabled else { return }
        let enabled = UserDefaults.standard.bool(forKey: "inactivityReminderEnabled")
        guard enabled else { return }

        let interval = UserDefaults.standard.double(forKey: "inactivityReminderInterval")
        let reminderInterval = interval > 0 ? interval : 1800

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["inactivityReminder"])

        let content = UNMutableNotificationContent()
        content.title = "Still there?"
        content.body = "You haven't logged any activity in \(reminderInterval.formattedDuration). Tap to start tracking."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: reminderInterval, repeats: false)
        let request = UNNotificationRequest(identifier: "inactivityReminder", content: content, trigger: trigger)
        center.add(request)
    }

    private func cancelInactivityReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["inactivityReminder"])
    }

    // MARK: - Persistence

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("[Cadence] Failed to save context: \(error)")
        }
    }

    private func saveAndInvalidate(date: Date) {
        saveContext()
        historyManager.invalidateDate(date, in: modelContext)
    }
}
