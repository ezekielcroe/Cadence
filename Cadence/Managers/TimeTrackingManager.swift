// MARK: - TimeTrackingManager (With Tracking Modes, Day Boundaries Removed)

import Foundation
import SwiftData
import Combine
import UIKit
import UserNotifications

@MainActor
class TimeTrackingManager: ObservableObject {
    
    // MARK: - Properties
    
    private var modelContext: ModelContext
    
    // Published properties for UI updates
    @Published var currentTimeBlock: TimeBlock?
    @Published var activeSet: ActivitySet?
    @Published var currentTimeBlockRule: TimeBlockRule?
    
    // Background tracking
    private var backgroundEnteredTime: Date?
    private(set) var maxBackgroundDuration: TimeInterval = 900
    
    // Default tracking mode (when not within any time block rule)
    private(set) var defaultTrackingMode: TrackingMode = .relaxed
    
    // Notification preferences
    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notificationsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
    }
    
    // Timer for UI updates
    private var timer: Timer?
    
    // MARK: - Initialization
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        // Set default notification preference if not set
        if UserDefaults.standard.object(forKey: "notificationsEnabled") == nil {
            notificationsEnabled = true
        }
        
        loadSettings()
        resumeActiveTimeBlock()
        startTimer()
        setupBackgroundTracking()
        checkAndApplyCurrentTimeBlockRule()
    }
    
    // MARK: - Settings Management
    
    private func loadSettings() {
        loadBackgroundSettings()
        loadDefaultTrackingMode()
    }
    
    private func loadBackgroundSettings() {
        let savedDuration = UserDefaults.standard.double(forKey: "maxBackgroundDuration")
        if savedDuration > 0 {
            maxBackgroundDuration = savedDuration
        }
        
        if let savedTimestamp = UserDefaults.standard.object(forKey: "backgroundEnteredTime") as? Double {
            backgroundEnteredTime = Date(timeIntervalSince1970: savedTimestamp)
        }
    }
    
    private func loadDefaultTrackingMode() {
        if let savedMode = UserDefaults.standard.string(forKey: "defaultTrackingMode"),
           let mode = TrackingMode(rawValue: savedMode) {
            defaultTrackingMode = mode
        }
    }
    
    func saveMaxBackgroundDuration(_ duration: TimeInterval) {
        maxBackgroundDuration = duration
        UserDefaults.standard.set(duration, forKey: "maxBackgroundDuration")
    }
    
    func saveDefaultTrackingMode(_ mode: TrackingMode) {
        defaultTrackingMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "defaultTrackingMode")
    }
    
    private func saveBackgroundState() {
        UserDefaults.standard.set(
            backgroundEnteredTime?.timeIntervalSince1970,
            forKey: "backgroundEnteredTime"
        )
    }
    
    // MARK: - Current Tracking Mode
    
    /// Get the current tracking mode based on active time block rule or default
    var currentTrackingMode: TrackingMode {
        // Find active time block rule
        if let activeRule = getActiveTimeBlockRule() {
            return activeRule.trackingMode
        }
        // Fall back to default
        return defaultTrackingMode
    }
    
    /// Whether gaps should be tracked right now
    var shouldTrackGaps: Bool {
        currentTrackingMode.tracksGaps
    }
    
    /// Whether auto-switching sets is enabled right now
    var shouldAutoSwitchSets: Bool {
        currentTrackingMode.autoSwitchesSets
    }
    
    /// Get the currently active time block rule (if any)
    func getActiveTimeBlockRule() -> TimeBlockRule? {
        let descriptor = FetchDescriptor<TimeBlockRule>(
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        
        guard let rules = try? modelContext.fetch(descriptor) else { return nil }
        return rules.first(where: { $0.isActiveNow() })
    }
    
    // MARK: - Activity Management
    
    func startActivity(_ activity: Activity) {
        let now = Date()
        
        endCurrentActivityIfNeeded(at: now, state: "switched")
        
        let newBlock = TimeBlock(activity: activity, startTime: now)
        modelContext.insert(newBlock)
        currentTimeBlock = newBlock
        
        clearBackgroundState()
        saveContext()
    }
    
    func pauseCurrentActivity() {
        guard let current = currentTimeBlock, !current.isPaused else { return }
        
        let now = Date()
        
        current.endTime = now
        current.stopState = "paused"
        
        let pauseBlock = TimeBlock.createPause(startTime: now)
        modelContext.insert(pauseBlock)
        currentTimeBlock = pauseBlock
        
        clearBackgroundState()
        saveContext()
    }
    
    func resumeFromPause(_ activity: Activity) {
        guard let current = currentTimeBlock, current.isPauseBlock else { return }
        
        let now = Date()
        
        current.endTime = now
        current.stopState = "switched"
        current.switchCount += 1
        
        let resumedBlock = TimeBlock(activity: activity, startTime: now)
        modelContext.insert(resumedBlock)
        currentTimeBlock = resumedBlock
        
        saveContext()
    }
    
    func stopCurrentActivity() {
        guard let current = currentTimeBlock else { return }
        
        let now = Date()
        
        current.endTime = now
        current.stopState = "stopped"
        
        // Only create gap if current tracking mode allows it
        if shouldTrackGaps {
            let gap = TimeBlock.createGap(startTime: now)
            modelContext.insert(gap)
            currentTimeBlock = gap
        } else {
            // No gap tracking - just end the activity
            currentTimeBlock = nil
        }
        
        clearBackgroundState()
        saveContext()
    }
    
    private func endCurrentActivityIfNeeded(at time: Date, state: String) {
        guard let current = currentTimeBlock else { return }
        current.endTime = time
        current.stopState = state
    }
    
    private func clearBackgroundState() {
        backgroundEnteredTime = nil
        UserDefaults.standard.removeObject(forKey: "backgroundEnteredTime")
    }
    
    // MARK: - Timer Management
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
                // Periodically check if time block rule has changed
                self?.checkAndApplyCurrentTimeBlockRule()
            }
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
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
            // 1. Force reload settings to ensure we have the latest duration
            loadBackgroundSettings()
            
            guard let current = currentTimeBlock,
                  !current.isPaused,
                  !current.isGap else { return }
            
            backgroundEnteredTime = Date()
            saveBackgroundState()
            scheduleBackgroundReminder()
        }
    
    @objc private func appWillEnterForeground() {
        defer {
            backgroundEnteredTime = nil
            cancelBackgroundReminder()
        }
        
        guard let backgroundTime = backgroundEnteredTime,
              let current = currentTimeBlock,
              !current.isPaused else { return }
        
        let elapsedTime = Date().timeIntervalSince(backgroundTime)
        
        if elapsedTime > maxBackgroundDuration {
            handleBackgroundTimeout(
                current: current,
                backgroundTime: backgroundTime
            )
        }
        
        saveContext()
        checkAndApplyCurrentTimeBlockRule()
    }
    
    private func handleBackgroundTimeout(current: TimeBlock, backgroundTime: Date) {
        let cappedEndTime = backgroundTime.addingTimeInterval(maxBackgroundDuration)
        current.endTime = cappedEndTime
        current.stopState = "stopped"
        
        // Check tracking mode at the capped end time to decide about gap
        // For simplicity, use current tracking mode
        if shouldTrackGaps {
            let gap = TimeBlock.createGap(startTime: cappedEndTime)
            modelContext.insert(gap)
            currentTimeBlock = gap
        } else {
            currentTimeBlock = nil
        }
        
        notifyActivityStopped()
    }
    
    // MARK: - Session Recovery
    
    private func resumeActiveTimeBlock() {
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        
        guard let activeBlock = try? modelContext.fetch(descriptor).first else { return }
        
        currentTimeBlock = activeBlock
        
        // Check if we need to handle a background timeout from previous session
        if let backgroundTime = backgroundEnteredTime {
            let elapsedTime = Date().timeIntervalSince(backgroundTime)
            
            if elapsedTime > maxBackgroundDuration {
                handleBackgroundTimeout(
                    current: activeBlock,
                    backgroundTime: backgroundTime
                )
                clearBackgroundState()
                saveContext()
            }
        }
    }
    
    // MARK: - Time Block Rule Application
        /// Check current time block rule and apply its settings
        func checkAndApplyCurrentTimeBlockRule() {
            let activeRule = getActiveTimeBlockRule()
            
            // Update current rule reference
            let previousRule = currentTimeBlockRule
            currentTimeBlockRule = activeRule
            
            // Only auto-switch if the mode allows it
            guard let rule = activeRule,
                  rule.trackingMode.autoSwitchesSets, // CHANGED: Access via trackingMode
                  let setID = rule.linkedSetID else { return }
            
            // Check if rule changed (to avoid repeated switches)
            if previousRule?.id != rule.id {
                let sets = try? modelContext.fetch(FetchDescriptor<ActivitySet>())
                let currentActiveSet = sets?.first { $0.isActive }
                
                if currentActiveSet?.id != setID,
                   let targetSet = sets?.first(where: { $0.id == setID }) {
                    switchToActivitySet(targetSet, ruleName: rule.name)
                }
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
    
    // MARK: - Notifications
    
    private func scheduleBackgroundReminder() {
        guard notificationsEnabled else { return }
        guard maxBackgroundDuration > 300 else { return }
        
        let reminderTime = maxBackgroundDuration - 300
        
        let content = UNMutableNotificationContent()
        content.title = "Cadence Activity Tracking"
        content.body = "Your activity will stop in 5 minutes. Open the app to continue tracking."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: reminderTime,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "backgroundReminder",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling reminder: \(error)")
            }
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
        content.body = "Your activity was stopped after \(maxBackgroundDuration.formattedDuration) in background."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "activityStopped",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error)")
            }
        }
    }
    
    private func notifySetSwitch(setName: String, ruleName: String) {
        guard notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Activity Set Changed"
        content.body = "\(ruleName): Switched to \(setName)"
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "setSwitch",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error)")
            }
        }
    }
    
    // MARK: - Data Queries
    
    func getTodaysTimeBlocks() -> [TimeBlock] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime >= startOfDay && block.startTime < endOfDay
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func getTodaysStats() -> DayStats {
        let blocks = getTodaysTimeBlocks()
        
        var activityDurations: [String: TimeInterval] = [:]
        var totalDuration: TimeInterval = 0
        var totalSwitches: Int = 0
        
        for block in blocks {
            let duration = block.duration
            activityDurations[block.activityName, default: 0] += duration
            totalDuration += duration
            totalSwitches += block.switchCount
        }
        
        return DayStats(
            totalDuration: totalDuration,
            activityDurations: activityDurations,
            totalSwitches: totalSwitches,
            blockCount: blocks.count
        )
    }
    
    // MARK: - Helper Methods
    
    private func saveContext() {
        try? modelContext.save()
    }
}

// MARK: - Stats Model

struct DayStats {
    let totalDuration: TimeInterval
    let activityDurations: [String: TimeInterval]
    let totalSwitches: Int
    let blockCount: Int
    
    var sortedActivities: [(name: String, duration: TimeInterval)] {
        activityDurations
            .sorted { $0.value > $1.value }
            .map { (name: $0.key, duration: $0.value) }
    }
}
