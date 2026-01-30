// MARK: - Refactored TimeTrackingManager
// Improved organization, notification preferences, and code clarity

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
    
    // Day boundaries (for reports)
    private(set) var startOfDayHour: Int = 6
    private(set) var endOfDayHour: Int = 23
    
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
        checkAndSwitchActivitySet()
    }
    
    // MARK: - Settings Management
    
    private func loadSettings() {
        loadBackgroundSettings()
        loadDayBoundarySettings()
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
    
    private func loadDayBoundarySettings() {
        let savedStart = UserDefaults.standard.integer(forKey: "startOfDayHour")
        startOfDayHour = savedStart > 0 ? savedStart : 6
        
        let savedEnd = UserDefaults.standard.integer(forKey: "endOfDayHour")
        endOfDayHour = savedEnd > 0 ? savedEnd : 23
    }
    
    func saveMaxBackgroundDuration(_ duration: TimeInterval) {
        maxBackgroundDuration = duration
        UserDefaults.standard.set(duration, forKey: "maxBackgroundDuration")
    }
    
    func saveDayBoundaries(start: Int, end: Int) {
        startOfDayHour = start
        endOfDayHour = end
        UserDefaults.standard.set(start, forKey: "startOfDayHour")
        UserDefaults.standard.set(end, forKey: "endOfDayHour")
    }
    
    private func saveBackgroundState() {
        UserDefaults.standard.set(
            backgroundEnteredTime?.timeIntervalSince1970,
            forKey: "backgroundEnteredTime"
        )
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
        
        let gap = TimeBlock.createGap(startTime: now)
        modelContext.insert(gap)
        currentTimeBlock = gap
        
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
        checkAndSwitchActivitySet()
    }
    
    private func handleBackgroundTimeout(current: TimeBlock, backgroundTime: Date) {
        let cappedEndTime = backgroundTime.addingTimeInterval(maxBackgroundDuration)
        current.endTime = cappedEndTime
        current.stopState = "stopped"
        
        let gap = TimeBlock.createGap(startTime: cappedEndTime)
        modelContext.insert(gap)
        currentTimeBlock = gap
        
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
    
    // MARK: - Activity Set Auto-Switching
    
    func checkAndSwitchActivitySet() {
        let descriptor = FetchDescriptor<TimeBlockRule>(
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        
        guard let rules = try? modelContext.fetch(descriptor),
              let activeRule = rules.first(where: { $0.isActiveNow() }),
              let setID = activeRule.linkedSetID else { return }
        
        currentTimeBlockRule = activeRule
        
        let sets = try? modelContext.fetch(FetchDescriptor<ActivitySet>())
        let currentActiveSet = sets?.first { $0.isActive }
        
        if currentActiveSet?.id != setID,
           let targetSet = sets?.first(where: { $0.id == setID }) {
            switchToActivitySet(targetSet)
        }
    }
    
    private func switchToActivitySet(_ set: ActivitySet) {
        let sets = try? modelContext.fetch(FetchDescriptor<ActivitySet>())
        sets?.forEach { $0.isActive = false }
        set.isActive = true
        activeSet = set
        
        saveContext()
        notifySetSwitch(setName: set.name)
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
    
    private func notifySetSwitch(setName: String) {
        guard notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Activity Set Changed"
        content.body = "Switched to \(setName) activities"
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
