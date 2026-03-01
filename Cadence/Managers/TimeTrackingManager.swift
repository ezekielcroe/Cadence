// TimeTrackingManager.swift
// Cadence

import Foundation
import SwiftData
import Combine
import UIKit
import UserNotifications
import AudioToolbox

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
        saveAndInvalidate(date: now)

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
        
        if current.duration >= target {
            current.targetDuration = nil
            stopCurrentActivity()
            
            HapticManager.shared.notification(type: .success)
            AudioServicesPlayAlertSound(SystemSoundID(1304))
        }
    }

    private func scheduleTargetAlarm(duration: TimeInterval, activityName: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["targetAlarm"])

        let content = UNMutableNotificationContent()
        content.title = "Time is up!"
        content.body = "Your session for \(activityName) has ended."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: duration, repeats: false)
        let request = UNNotificationRequest(identifier: "targetAlarm", content: content, trigger: trigger)
        center.add(request)
    }

    private func cancelTargetAlarm() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["targetAlarm"])
    }

    /// Pause the current activity in-place.
    /// The block remains active; only `isPaused`, `pauseStartTime`, and `pauseCount` change.
    func pauseCurrentActivity() {
        guard let current = currentTimeBlock,
              !current.isPaused,
              current.endTime == nil else { return }

        current.isPaused = true
        current.pauseStartTime = Date()
        current.pauseCount += 1

        clearBackgroundState()
        saveContext()
    }

    /// Resume from a pause. The same block continues; pause duration is recorded.
    func resumeFromPause() {
        guard let current = currentTimeBlock, current.isPaused else { return }

        closePause(on: current, at: Date())
        saveContext()
    }

    /// Stop the current activity. No gap block is created.
    /// Any gap that results will appear as a computed gap in RecordsView.
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
    /// The block is ended at (pauseStart + maxPauseDuration). The elapsed time
    /// between that point and now will surface as a computed gap.
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
                self.objectWillChange.send()
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
    }

    @objc private func appDidEnterBackground() {
        // Track background entry for both active and paused blocks.
        // For paused blocks the pause timeout still applies.
        guard let current = currentTimeBlock, current.endTime == nil else { return }
        backgroundEnteredTime = Date()
        saveBackgroundState()
        if !current.isPaused {
            scheduleBackgroundReminder()
        }
    }

    @objc private func appWillEnterForeground() {
        defer {
            backgroundEnteredTime = nil
            cancelBackgroundReminder()
        }

        guard let backgroundTime = backgroundEnteredTime,
              let current = currentTimeBlock else { return }

        let elapsed = Date().timeIntervalSince(backgroundTime)

        if current.isPaused {
            let totalPauseElapsed = Date().timeIntervalSince(current.pauseStartTime ?? backgroundTime)
            if totalPauseElapsed > maxPauseDuration {
                // autostopDueToPauseTimeout handles its own saveAndInvalidate
                autostopDueToPauseTimeout(current: current)
            }
            // If still within limit, resume normally — user comes back to paused state.
        } else if elapsed > maxBackgroundDuration {
            handleBackgroundTimeout(current: current, backgroundTime: backgroundTime)
            // cappedEnd is the date the block actually ended — invalidate that day
            let cappedEnd = backgroundTime.addingTimeInterval(maxBackgroundDuration)
            saveAndInvalidate(date: cappedEnd)
            checkAndApplyCurrentTimeBlockRule()
            return
        }

        // No block ended — persist any state changes (e.g. resumed from pause within limit)
        saveContext()
        checkAndApplyCurrentTimeBlockRule()
    }

    /// Caps the block at (backgroundTime + maxBackgroundDuration) and stops tracking.
    /// The time between the cap and now will be a computed gap — no untracked block needed.
    private func handleBackgroundTimeout(current: TimeBlock, backgroundTime: Date) {
        let cappedEnd = backgroundTime.addingTimeInterval(maxBackgroundDuration)
        current.endTime = cappedEnd
        current.stopState = "stopped"
        currentTimeBlock = nil
        notifyActivityStopped()
    }

    // MARK: - Session Recovery

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
                }
            } else {
                let elapsed = Date().timeIntervalSince(backgroundTime)
                if elapsed > maxBackgroundDuration {
                    handleBackgroundTimeout(current: activeBlock, backgroundTime: backgroundTime)
                    let cappedEnd = backgroundTime.addingTimeInterval(maxBackgroundDuration)
                    saveAndInvalidate(date: cappedEnd)
                }
            }
            clearBackgroundState()
        }
        
        cancelBackgroundReminder()
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
