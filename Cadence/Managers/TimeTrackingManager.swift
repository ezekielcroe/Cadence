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

    private var backgroundEnteredTime: Date?
    private(set) var maxBackgroundDuration: TimeInterval = 900   // 15 min default

    /// Maximum pause duration before the activity is auto-stopped. (10 min)
    private let maxPauseDuration: TimeInterval = 600

    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notificationsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
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

        loadSettings()
        resumeActiveTimeBlock()
        startTimer()
        setupBackgroundTracking()
        checkAndApplyCurrentTimeBlockRule()
    }

    // MARK: - Settings

    private func loadSettings() {
        let saved = UserDefaults.standard.double(forKey: "maxBackgroundDuration")
        if saved > 0 { maxBackgroundDuration = saved }

        if let ts = UserDefaults.standard.object(forKey: "backgroundEnteredTime") as? Double {
            backgroundEnteredTime = Date(timeIntervalSince1970: ts)
        }
    }

    func saveMaxBackgroundDuration(_ duration: TimeInterval) {
        maxBackgroundDuration = duration
        UserDefaults.standard.set(duration, forKey: "maxBackgroundDuration")
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
    /// Reads the user preference and only keeps screen on when actively tracking.
    func updateIdleTimerState() {
        let keepScreenOn = UserDefaults.standard.bool(forKey: "keepScreenOnWhileTracking")
        let isTracking = currentTimeBlock != nil && currentTimeBlock?.endTime == nil
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && isTracking
    }

    // MARK: - Set Auto-Switching

    var shouldAutoSwitchSets: Bool {
        getActiveTimeBlockRule()?.trackingMode.autoSwitchesSets ?? false
    }

    func getActiveTimeBlockRule() -> TimeBlockRule? {
        let descriptor = FetchDescriptor<TimeBlockRule>(
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        guard let rules = try? modelContext.fetch(descriptor) else { return nil }
        return rules.first(where: { $0.isActiveNow() })
    }

    // MARK: - Activity Management

    /// Start tracking an activity.
    /// If the current block is paused, the pause is cleanly closed before switching.
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
            // Calculate how much time is remaining right now
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
        // Don't check while paused — the notification was already cancelled/deferred
        guard !current.isPaused else { return }

        if current.duration >= target {
            current.targetDuration = nil
            stopCurrentActivity()

            // Foreground completion feedback
            HapticManager.shared.notification(type: .success)
            playTimerCompletionSound()
        }
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

    /// Re-schedule the alarm when pausing/resuming changes the effective remaining time.
    private func rescheduleTargetAlarmIfNeeded() {
        guard let current = currentTimeBlock,
              let target = current.targetDuration,
              !current.isPaused else {
            // If paused, cancel — we'll reschedule on resume
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

    /// Plays a prominent alert sound when the timer completes while the app is foregrounded.
    private func playTimerCompletionSound() {
        // Try the tri-tone alert first, fall back to system sound
        if let url = findAlertSoundURL() {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
                return
            } catch { /* fall through */ }
        }
        // Fallback: system alert sound (1005 = "default alert")
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }

    /// Searches for a built-in alert tone.
    private func findAlertSoundURL() -> URL? {
        // tri-tone is the classic iOS timer sound
        let paths = [
            "/System/Library/Audio/UISounds/alarm.caf",
            "/System/Library/Audio/UISounds/nano/alarm_nightstand_haptic.caf",
            "/System/Library/Audio/UISounds/SIMToolkitCallDropped.caf"
        ]
        return paths.compactMap { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Pause / Resume

    /// Pause the current activity in-place.
    func pauseCurrentActivity() {
        guard let current = currentTimeBlock,
              !current.isPaused,
              current.endTime == nil else { return }

        current.isPaused = true
        current.pauseStartTime = Date()
        current.pauseCount += 1

        // Cancel alarm while paused — time isn't counting down
        if current.targetDuration != nil {
            cancelTargetAlarm()
        }

        clearBackgroundState()
        saveContext()
    }

    /// Resume from a pause. The same block continues; pause duration is recorded.
    func resumeFromPause() {
        guard let current = currentTimeBlock, current.isPaused else { return }

        closePause(on: current, at: Date())
        saveContext()

        // Reschedule alarm with corrected remaining time
        rescheduleTargetAlarmIfNeeded()
    }

    /// Stop the current activity.
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

    // MARK: - Pause Helpers

    /// Closes an in-progress pause: accumulates duration, resets pause state.
    private func closePause(on block: TimeBlock, at time: Date) {
        let elapsed = time.timeIntervalSince(block.pauseStartTime ?? time)
        block.totalPauseDuration += max(0, elapsed)
        block.isPaused = false
        block.pauseStartTime = nil
    }

    /// Called by the timer when a pause has exceeded the 10-minute limit.
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

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Only force a UI refresh when there's an active block whose
                // elapsed time is visibly ticking. Paused blocks and idle state
                // don't need per-second redraws.
                let isActivelyTracking = self.currentTimeBlock != nil
                    && self.currentTimeBlock?.endTime == nil

                if isActivelyTracking {
                    self.objectWillChange.send()
                }

                // These checks still run every tick — they are cheap guards
                // that bail out immediately when there's nothing to do.
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

    /// Enforce the 10-minute pause limit on every timer tick.
    private func checkPauseTimeout() {
        guard let current = currentTimeBlock,
              current.isPaused,
              let pauseStart = current.pauseStartTime,
              Date().timeIntervalSince(pauseStart) > maxPauseDuration else { return }
        autostopDueToPauseTimeout(current: current)
    }

    // MARK: - Background Tracking

    /// Background task identifier — lets us request extra seconds from iOS
    /// to finish saving state before the app is suspended.
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
        // Last-chance save before iOS terminates the app.
        // Not guaranteed to fire, but covers graceful termination.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        guard let current = currentTimeBlock, current.endTime == nil else { return }

        // Request extra time from iOS to finish saving (~5-30 seconds).
        // Without this, iOS can suspend us before saves complete.
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SaveTrackingState") {
            // Expiration handler — clean up if we run out of time
            self.endBackgroundTask()
        }

        backgroundEnteredTime = Date()
        saveBackgroundState()

        // CRITICAL: Save the SwiftData context so the TimeBlock's current state
        // (pause state, duration, etc.) survives app termination.
        saveContext()

        if !current.isPaused {
            scheduleBackgroundReminder()
        }

        endBackgroundTask()
    }

    @objc private func appWillTerminate() {
        // Last-chance: persist everything we can
        saveBackgroundState()
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

        // Reschedule target alarm with corrected remaining time after returning from background
        rescheduleTargetAlarmIfNeeded()
    }

    /// Caps the block at (backgroundTime + maxBackgroundDuration) and stops tracking.
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

    /// Called on init (cold launch). Finds any active TimeBlock and reconciles
    /// elapsed time — handles background timeout, pause timeout, AND target
    /// duration expiry that may have occurred while the app was terminated.
    private func resumeActiveTimeBlock() {
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

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

        // Check if the target duration was exceeded while the app was dead.
        // The UNNotification may have fired, but the block was never auto-stopped
        // because checkTargetDuration() only runs on the 1-second Timer tick.
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

            // Notify user that their timer completed while they were away
            notifyTimerCompletedWhileAway(activityName: activeBlock.activityName)
            cancelBackgroundReminder()
            return
        }

        cancelBackgroundReminder()
        updateIdleTimerState()

        // Ensure target alarm is accurate after app relaunch
        rescheduleTargetAlarmIfNeeded()
    }

    // MARK: - Time Block Rule Application

    func checkAndApplyCurrentTimeBlockRule() {
        let activeRule = getActiveTimeBlockRule()
        let previousRule = currentTimeBlockRule
        currentTimeBlockRule = activeRule

        guard let rule = activeRule,
              rule.trackingMode.autoSwitchesSets,
              let setID = rule.linkedSetID,
              previousRule?.id != rule.id else { return }

        let sets = try? modelContext.fetch(FetchDescriptor<ActivitySet>())
        let currentActiveSet = sets?.first { $0.isActive }

        if currentActiveSet?.id != setID,
           let targetSet = sets?.first(where: { $0.id == setID }) {
            switchToActivitySet(targetSet, ruleName: rule.name)
        }
    }

    private func switchToActivitySet(_ set: ActivitySet, ruleName: String) {
        let sets = try? modelContext.fetch(FetchDescriptor<ActivitySet>())
        sets?.forEach { $0.isActive = false }
        set.isActive = true
        activeSet = set
        saveContext()
        notifySetSwitch(setName: set.name, ruleName: ruleName)
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

    private func scheduleBackgroundReminder() {
        guard notificationsEnabled, maxBackgroundDuration > 300 else { return }
        let reminderTime = maxBackgroundDuration - 300
        let content = UNMutableNotificationContent()
        content.title = "Cadence Activity Tracking"
        content.body = "Your activity will stop in 5 minutes. Open the app to continue tracking."
        let request = UNNotificationRequest(
            identifier: "backgroundReminder",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: reminderTime, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
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

    /// Schedules a notification to remind the user they haven't logged any activity.
    /// Called whenever the user stops an activity (or a block is auto-stopped).
    private func scheduleInactivityReminder() {
        guard notificationsEnabled else { return }
        let enabled = UserDefaults.standard.bool(forKey: "inactivityReminderEnabled")
        guard enabled else { return }

        // Default 30 minutes; stored in seconds
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

    /// Saves the context and forces HistoryManager to recalculate the summary
    /// for the given date, so StatsView never serves stale cached numbers.
    private func saveAndInvalidate(date: Date) {
        saveContext()
        historyManager.invalidateDate(date, in: modelContext)
    }
}
