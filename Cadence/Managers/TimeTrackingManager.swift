// MARK: - TimeTrackingManager (Updated Gap Logic)

import Foundation
import SwiftData
import Combine
import UIKit
import UserNotifications

@MainActor
class TimeTrackingManager: ObservableObject {
    
    // MARK: - Properties
    
    private var modelContext: ModelContext
    
    @Published var currentTimeBlock: TimeBlock?
    @Published var activeSet: ActivitySet?
    @Published var currentTimeBlockRule: TimeBlockRule?
    
    private var backgroundEnteredTime: Date?
    private(set) var maxBackgroundDuration: TimeInterval = 900
    
    private(set) var defaultTrackingMode: TrackingMode = .on
    
    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notificationsEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "notificationsEnabled") }
    }
    
    private var timer: Timer?
    
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
    
    var currentTrackingMode: TrackingMode {
        if let activeRule = getActiveTimeBlockRule() {
            return activeRule.trackingMode
        }
        return defaultTrackingMode
    }
    
    var shouldTrackGaps: Bool {
        currentTrackingMode.tracksGaps
    }
    
    var shouldAutoSwitchSets: Bool {
        currentTrackingMode.autoSwitchesSets
    }
    
    func getActiveTimeBlockRule() -> TimeBlockRule? {
        let descriptor = FetchDescriptor<TimeBlockRule>(
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        guard let rules = try? modelContext.fetch(descriptor) else { return nil }
        return rules.first(where: { $0.isActiveNow() })
    }
    
    // MARK: - Helper: Historical Mode Checking
    
    private func getTrackingMode(at date: Date) -> TrackingMode {
        let descriptor = FetchDescriptor<TimeBlockRule>()
        guard let rules = try? modelContext.fetch(descriptor) else { return defaultTrackingMode }
        
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: date)
        let minuteOfDay = (timeComponents.hour ?? 0) * 60 + (timeComponents.minute ?? 0)
        
        let activeRule = rules.first { rule in
            guard rule.isEnabled else { return false }
            
            if !rule.daysOfWeek.isEmpty && !rule.daysOfWeek.contains(weekday) {
                return false
            }
            
            let startMinutes = calendar.component(.hour, from: rule.startTime) * 60 + calendar.component(.minute, from: rule.startTime)
            let endMinutes = calendar.component(.hour, from: rule.endTime) * 60 + calendar.component(.minute, from: rule.endTime)
            
            if endMinutes < startMinutes {
                return minuteOfDay >= startMinutes || minuteOfDay < endMinutes
            } else {
                return minuteOfDay >= startMinutes && minuteOfDay < endMinutes
            }
        }
        
        return activeRule?.trackingMode ?? defaultTrackingMode
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
        
        // Create a Pause block
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
        
        // CHECK: Pause Duration Logic
        // If pause > 15 mins (900s), convert it to a GAP
        if current.duration > 900 {
            current.blockType = "gap"
            current.activityName = "Gap"
            current.activityColor = "#FF5722" // Orange
            // We do not change the start/end time, just the classification
        }
        
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
        
        // Check current tracking mode
        let mode = getTrackingMode(at: now)
        
        if mode == .on {
            // Tracking ON: Create Gap
            let gap = TimeBlock.createGap(startTime: now)
            modelContext.insert(gap)
            currentTimeBlock = gap
        } else {
            // Tracking OFF: Create Untracked Block
            // This ensures the timeline is continuous but neutral
            let untracked = TimeBlock.createUntracked(startTime: now)
            modelContext.insert(untracked)
            currentTimeBlock = untracked
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
        loadBackgroundSettings()
        
        guard let current = currentTimeBlock,
              !current.isPaused,
              !current.isGap,
              !current.isUntrackedBlock else { return }
        
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
        let now = Date()
        
        current.endTime = cappedEndTime
        current.stopState = "stopped"
        
        // 1. Determine duration of the "missing time"
        let gapDuration = now.timeIntervalSince(cappedEndTime)
        
        // 2. Check rule at timeout
        let modeAtTimeout = getTrackingMode(at: cappedEndTime)
        
        if modeAtTimeout == .on {
            if gapDuration < 120 {
                // Micro-gap (< 2m): Ignore/Extend
                current.endTime = now
                // No gap created
            } else if gapDuration < 900 {
                // Short Gap (2-15m): Create Pause
                let pause = TimeBlock.createPause(startTime: cappedEndTime)
                pause.endTime = now
                pause.stopState = "stopped"
                modelContext.insert(pause)
                currentTimeBlock = nil // Or start a new gap? Standard behavior is stop.
            } else {
                // Long Gap (> 15m): Create Gap
                let gap = TimeBlock.createGap(startTime: cappedEndTime)
                gap.endTime = now
                gap.stopState = "stopped"
                modelContext.insert(gap)
                currentTimeBlock = nil
            }
        } else {
            // Mode OFF: Create Untracked
            let untracked = TimeBlock.createUntracked(startTime: cappedEndTime)
            untracked.endTime = now
            untracked.stopState = "stopped"
            modelContext.insert(untracked)
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
    
    func checkAndApplyCurrentTimeBlockRule() {
        let activeRule = getActiveTimeBlockRule()
        let previousRule = currentTimeBlockRule
        currentTimeBlockRule = activeRule
        
        guard let rule = activeRule,
              rule.trackingMode.autoSwitchesSets,
              let setID = rule.linkedSetID else { return }
        
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
    
    // MARK: - Notifications (Standard Implementation)
    
    private func scheduleBackgroundReminder() {
        guard notificationsEnabled else { return }
        guard maxBackgroundDuration > 300 else { return }
        let reminderTime = maxBackgroundDuration - 300
        let content = UNMutableNotificationContent()
        content.title = "Cadence Activity Tracking"
        content.body = "Your activity will stop in 5 minutes. Open the app to continue tracking."
        let request = UNNotificationRequest(identifier: "backgroundReminder", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: reminderTime, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
    
    private func cancelBackgroundReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["backgroundReminder"])
    }
    
    private func notifyActivityStopped() {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Activity Stopped"
        content.body = "Your activity was stopped after \(maxBackgroundDuration.formattedDuration) in background."
        let request = UNNotificationRequest(identifier: "activityStopped", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
    
    private func notifySetSwitch(setName: String, ruleName: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Activity Set Changed"
        content.body = "\(ruleName): Switched to \(setName)"
        let request = UNNotificationRequest(identifier: "setSwitch", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(request)
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
            var unaccountedDuration: TimeInterval = 0 // Replaces Fidelity Score
            var totalSwitches: Int = 0
            
            for block in blocks {
                let duration = block.duration
                totalDuration += duration
                totalSwitches += block.switchCount
                
                if block.isGap {
                    unaccountedDuration += duration
                    activityDurations["Gap", default: 0] += duration
                } else if block.isUntrackedBlock {
                    activityDurations["Untracked", default: 0] += duration
                } else {
                    activityDurations[block.activityName, default: 0] += duration
                }
            }
            
            return DayStats(
                totalDuration: totalDuration,
                activityDurations: activityDurations,
                totalSwitches: totalSwitches,
                blockCount: blocks.count,
                unaccountedDuration: unaccountedDuration // Neutral metric
            )
        }

        // MARK: - Helper Methods
        
        private func saveContext() {
            do {
                try modelContext.save()
            } catch {
                print("Failed to save context: \(error)")
            }
        }
}
