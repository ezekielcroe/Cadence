import Foundation
import SwiftData
import Combine
import UIKit
import UserNotifications

@MainActor
@Observable
class TimeTrackingManager {
    private var modelContext: ModelContext
    
    // Current state
    var currentTimeBlock: TimeBlock?
    var activeSet: ActivitySet?
    
    // Background tracking
    var backgroundEnteredTime: Date?
    var maxBackgroundDuration: TimeInterval = 3600 // Default: 1 hour (in seconds)
    
    // Timer for UI updates
    private var timer: Timer?
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        // Load saved settings
        loadBackgroundSettings()
        
        // Resume any active time block from previous session
        resumeActiveTimeBlock()
        
        // Start UI update timer
        startTimer()
        
        // Setup background tracking
        setupBackgroundTracking()
    }
    
    // MARK: - Timer Management
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Trigger UI update by reassigning property
                self.currentTimeBlock = self.currentTimeBlock
            }
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        // Can't access MainActor properties in deinit
        // Timer will be cleaned up automatically when object is deallocated
    }
    
    // MARK: - Background Tracking Setup
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
        guard currentTimeBlock != nil, !currentTimeBlock!.isPaused else { return }
        
        backgroundEnteredTime = Date()
        saveBackgroundState()
        
        // Schedule reminder notification
        scheduleBackgroundReminder()
    }
    
    @objc private func appWillEnterForeground() {
        guard let backgroundTime = backgroundEnteredTime,
              let current = currentTimeBlock,
              !current.isPaused else {
            backgroundEnteredTime = nil
            return
        }
        
        let elapsedTime = Date().timeIntervalSince(backgroundTime)
        
        // Check if exceeded max background duration
        if elapsedTime > maxBackgroundDuration {
            // Stop activity at max duration
            let cappedEndTime = backgroundTime.addingTimeInterval(maxBackgroundDuration)
            current.endTime = cappedEndTime
            currentTimeBlock = nil
            
            // Show notification that activity was stopped
            showActivityStoppedNotification(backgroundDuration: maxBackgroundDuration)
        }
        // Otherwise, time continues normally (already tracked via timestamps)
        
        backgroundEnteredTime = nil
        try? modelContext.save()
        
        // Cancel any pending reminder notifications
        cancelBackgroundReminder()
    }
    
    private func scheduleBackgroundReminder() {
        guard maxBackgroundDuration > 300 else { return } // Only if duration > 5 minutes
        
        let reminderTime = maxBackgroundDuration - 300 // 5 minutes before
        
        let content = UNMutableNotificationContent()
        content.title = "Cadence Activity Tracking"
        content.body = "Your activity will stop in 5 minutes. Open the app to continue tracking."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: reminderTime, repeats: false)
        let request = UNNotificationRequest(identifier: "backgroundReminder", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling reminder: \(error)")
            }
        }
    }
    
    private func cancelBackgroundReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["backgroundReminder"])
    }
    
    private func showActivityStoppedNotification(backgroundDuration: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Activity Stopped"
        content.body = "Your activity was stopped after \(backgroundDuration.formattedDuration) in background."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "activityStopped", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error)")
            }
        }
    }
    
    // MARK: - Settings Persistence
    private func saveBackgroundState() {
        UserDefaults.standard.set(backgroundEnteredTime?.timeIntervalSince1970, forKey: "backgroundEnteredTime")
    }
    
    private func loadBackgroundSettings() {
        // Load max background duration
        let savedDuration = UserDefaults.standard.double(forKey: "maxBackgroundDuration")
        if savedDuration > 0 {
            maxBackgroundDuration = savedDuration
        }
        
        // Load background entered time (in case of crash)
        if let savedTimestamp = UserDefaults.standard.object(forKey: "backgroundEnteredTime") as? Double {
            backgroundEnteredTime = Date(timeIntervalSince1970: savedTimestamp)
        }
    }
    
    func saveMaxBackgroundDuration(_ duration: TimeInterval) {
        maxBackgroundDuration = duration
        UserDefaults.standard.set(duration, forKey: "maxBackgroundDuration")
    }
    
    // MARK: - Core Actions
    
    func startActivity(_ activity: Activity) {
        // End current activity if exists
        if currentTimeBlock != nil {
            endCurrentActivity()
        }
        
        // Create new time block
        let newBlock = TimeBlock(
            activityID: activity.id,
            activityName: activity.name,
            activityColor: activity.color,
            startTime: Date()
        )
        
        modelContext.insert(newBlock)
        currentTimeBlock = newBlock
        
        // Clear background state when starting new activity
        backgroundEnteredTime = nil
        UserDefaults.standard.removeObject(forKey: "backgroundEnteredTime")
        
        try? modelContext.save()
    }
    
    func pauseCurrentActivity() {
        guard let current = currentTimeBlock, !current.isPaused else { return }
        
        current.isPaused = true
        current.pauseStartTime = Date()
        
        // Clear background tracking when paused
        backgroundEnteredTime = nil
        UserDefaults.standard.removeObject(forKey: "backgroundEnteredTime")
        
        try? modelContext.save()
    }
    
    func resumeCurrentActivity() {
        guard let current = currentTimeBlock, current.isPaused else { return }
        
        if let pauseStart = current.pauseStartTime {
            let pauseDuration = Date().timeIntervalSince(pauseStart)
            current.totalPauseDuration += pauseDuration
        }
        
        current.isPaused = false
        current.pauseStartTime = nil
        current.switchCount += 1
        
        try? modelContext.save()
    }
    
    func stopCurrentActivity() {
        guard let current = currentTimeBlock else { return }
        
        // If paused, add final pause duration
        if current.isPaused, let pauseStart = current.pauseStartTime {
            let pauseDuration = Date().timeIntervalSince(pauseStart)
            current.totalPauseDuration += pauseDuration
            current.isPaused = false
            current.pauseStartTime = nil
        }
        
        current.endTime = Date()
        currentTimeBlock = nil
        
        // Clear background state
        backgroundEnteredTime = nil
        UserDefaults.standard.removeObject(forKey: "backgroundEnteredTime")
        
        try? modelContext.save()
    }
    
    private func endCurrentActivity() {
        guard let current = currentTimeBlock else { return }
        
        // If paused, add final pause duration
        if current.isPaused, let pauseStart = current.pauseStartTime {
            let pauseDuration = Date().timeIntervalSince(pauseStart)
            current.totalPauseDuration += pauseDuration
            current.isPaused = false
            current.pauseStartTime = nil
        }
        
        current.endTime = Date()
        currentTimeBlock = nil
        
        try? modelContext.save()
    }
    
    // MARK: - Session Recovery
    
    private func resumeActiveTimeBlock() {
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        
        if let activeBlock = try? modelContext.fetch(descriptor).first {
            currentTimeBlock = activeBlock
            
            // Check if there was a background session that exceeded max duration
            if let backgroundTime = backgroundEnteredTime {
                let elapsedTime = Date().timeIntervalSince(backgroundTime)
                
                if elapsedTime > maxBackgroundDuration {
                    // Stop activity at max duration
                    let cappedEndTime = backgroundTime.addingTimeInterval(maxBackgroundDuration)
                    activeBlock.endTime = cappedEndTime
                    currentTimeBlock = nil
                    
                    backgroundEnteredTime = nil
                    UserDefaults.standard.removeObject(forKey: "backgroundEnteredTime")
                    
                    try? modelContext.save()
                }
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
}

// MARK: - Stats Model
struct DayStats {
    let totalDuration: TimeInterval
    let activityDurations: [String: TimeInterval]
    let totalSwitches: Int
    let blockCount: Int
    
    var sortedActivities: [(name: String, duration: TimeInterval)] {
        activityDurations.sorted { $0.value > $1.value }.map { (name: $0.key, duration: $0.value) }
    }
}
