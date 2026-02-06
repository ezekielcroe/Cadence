import Foundation
import SwiftData

// MARK: - Activity Goal Enum
enum ActivityGoal: String, Codable, CaseIterable {
    case increase = "increase" // Keep High
    case decrease = "decrease" // Keep Low
    case neutral = "neutral"   // Neutral
    
    var displayName: String {
        switch self {
        case .increase: return "Keep High"
        case .decrease: return "Keep Low"
        case .neutral: return "Neutral"
        }
    }
    
    var icon: String {
        switch self {
        case .increase: return "arrow.up.circle"
        case .decrease: return "arrow.down.circle"
        case .neutral: return "minus.circle"
        }
    }
    
    var color: String {
        switch self {
        case .increase: return "#4CAF50" // Green
        case .decrease: return "#F44336" // Red (as in, limit it)
        case .neutral: return "#9E9E9E"  // Gray
        }
    }
}

// MARK: - Tracking Mode Enum
enum TrackingMode: String, Codable, CaseIterable {
    case on = "on"      // Track activities and gaps
    case off = "off"    // Tracker paused
    
    var displayName: String {
        switch self {
        case .on: return "Tracking"
        case .off: return "Paused"
        }
    }
    
    var description: String {
        switch self {
        case .on: return "Track activities and gaps"
        case .off: return "Tracker paused"
        }
    }
    
    var icon: String {
        switch self {
        case .on: return "clock.badge.checkmark"
        case .off: return "clock.badge.xmark"
        }
    }
    
    var tracksGaps: Bool {
        self == .on
    }
    
    var autoSwitchesSets: Bool {
        self == .on
    }
}

// MARK: - Activity Model
@Model
final class Activity {
    var id: UUID
    var name: String
    var emoji: String?
    var color: String
    var setID: UUID
    var createdAt: Date
    var sortOrder: Int
    
    // NEW: Goal property
    var goalRaw: String = "neutral"
    
    var goal: ActivityGoal {
        get { ActivityGoal(rawValue: goalRaw) ?? .neutral }
        set { goalRaw = newValue.rawValue }
    }
    
    init(name: String, color: String, setID: UUID, sortOrder: Int = 0, emoji: String? = nil, goal: ActivityGoal = .neutral) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.color = color
        self.setID = setID
        self.createdAt = Date()
        self.sortOrder = sortOrder
        self.goalRaw = goal.rawValue
    }
}

// MARK: - Activity Set Model
@Model
final class ActivitySet {
    var id: UUID
    var name: String
    var isActive: Bool
    var createdAt: Date
    
    init(name: String, isActive: Bool = false) {
        self.id = UUID()
        self.name = name
        self.isActive = isActive
        self.createdAt = Date()
    }
}

// MARK: - Time Block Rule Model
@Model
final class TimeBlockRule {
    var id: UUID
    var name: String
    var startTime: Date // Time of day (only hour/minute matter)
    var endTime: Date // Time of day
    var linkedSetID: UUID? // Optional: which activity set to activate
    var isEnabled: Bool
    var daysOfWeek: [Int] // 1=Sunday, 2=Monday, etc. Empty = all days
    var createdAt: Date
    
    var trackingModeRaw: String
    
    var trackingMode: TrackingMode {
        get { TrackingMode(rawValue: trackingModeRaw) ?? .on }
        set { trackingModeRaw = newValue.rawValue }
    }
    
    init(name: String, startTime: Date, endTime: Date, linkedSetID: UUID? = nil, daysOfWeek: [Int] = [], trackingMode: TrackingMode = .on) {
        self.id = UUID()
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.linkedSetID = linkedSetID
        self.isEnabled = true
        self.daysOfWeek = daysOfWeek
        self.createdAt = Date()
        self.trackingModeRaw = trackingMode.rawValue
    }
    
    // Check if this rule applies to the current time
    func isActiveNow() -> Bool {
        guard isEnabled else { return false }
        
        let now = Date()
        let calendar = Calendar.current
        
        // Check day of week
        if !daysOfWeek.isEmpty {
            let currentWeekday = calendar.component(.weekday, from: now)
            guard daysOfWeek.contains(currentWeekday) else { return false }
        }
        
        // Check time range
        let nowComponents = calendar.dateComponents([.hour, .minute], from: now)
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        
        guard let nowMinutes = nowComponents.hour.map({ $0 * 60 + (nowComponents.minute ?? 0) }),
              let startMinutes = startComponents.hour.map({ $0 * 60 + (startComponents.minute ?? 0) }),
              let endMinutes = endComponents.hour.map({ $0 * 60 + (endComponents.minute ?? 0) }) else {
            return false
        }
        
        // Handle overnight spans (e.g., 10pm - 2am)
        if endMinutes < startMinutes {
            return nowMinutes >= startMinutes || nowMinutes < endMinutes
        } else {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        }
    }
    
    var timeRangeDisplay: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
    
    var daysOfWeekDisplay: String {
        if daysOfWeek.isEmpty {
            return "Every day"
        }
        
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return daysOfWeek.sorted().map { dayNames[$0 - 1] }.joined(separator: ", ")
    }
}

// MARK: - Time Block Model
@Model
final class TimeBlock {
    var id: UUID
    var activityID: UUID?  // nil if Gap or Pause
    var activityName: String
    var activityColor: String
    var activitySetID: UUID?
    
    var startTime: Date  // IMMUTABLE in UI
    var endTime: Date?
    
    var isPaused: Bool
    var pauseStartTime: Date?
    var totalPauseDuration: TimeInterval
    
    var stopState: String  // "switched", "stopped", "paused", "ongoing"
    var switchCount: Int
    var remarks: String
    var blockType: String  // "activity", "gap", "pause"
    
    init(activityID: UUID?, activityName: String, activityColor: String, activitySetID: UUID?, startTime: Date, blockType: String = "activity") {
        self.id = UUID()
        self.activityID = activityID
        self.activityName = activityName
        self.activityColor = activityColor
        self.activitySetID = activitySetID
        self.startTime = startTime
        self.endTime = nil
        self.isPaused = false
        self.pauseStartTime = nil
        self.totalPauseDuration = 0
        self.stopState = "ongoing"
        self.switchCount = 0
        self.remarks = ""
        self.blockType = blockType
    }
    
    convenience init(activity: Activity, startTime: Date) {
        self.init(
            activityID: activity.id,
            activityName: activity.name,
            activityColor: activity.color,
            activitySetID: activity.setID,
            startTime: startTime,
            blockType: "activity"
        )
    }
    
    static func createGap(startTime: Date, endTime: Date? = nil) -> TimeBlock {
        let gap = TimeBlock(
            activityID: nil,
            activityName: "Gap",
            activityColor: "#9E9E9E",
            activitySetID: nil,
            startTime: startTime,
            blockType: "gap"
        )
        gap.endTime = endTime
        return gap
    }
    
    static func createPause(startTime: Date, endTime: Date? = nil) -> TimeBlock {
        let pause = TimeBlock(
            activityID: nil,
            activityName: "Pause",
            activityColor: "#FF9800",
            activitySetID: nil,
            startTime: startTime,
            blockType: "pause"
        )
        pause.endTime = endTime
        return pause
    }
    
    var duration: TimeInterval {
        guard let end = endTime else {
            let currentDuration = Date().timeIntervalSince(startTime)
            return currentDuration - totalPauseDuration - (isPaused ? Date().timeIntervalSince(pauseStartTime ?? Date()) : 0)
        }
        return end.timeIntervalSince(startTime) - totalPauseDuration
    }
    
    var isActive: Bool { endTime == nil && !isPaused }
    var isGap: Bool { blockType == "gap" }
    var isPauseBlock: Bool { blockType == "pause" }
    var isRegularActivity: Bool { blockType == "activity" }
    
    var displayName: String {
        if isPauseBlock && switchCount > 0 {
            return "Pause (\(switchCount)x)"
        }
        return activityName
    }
}

// MARK: - Helper Extensions
extension TimeInterval {
    var formattedDuration: String {
        let hours = Int(self) / 3600
        let minutes = Int(self) / 60 % 60
        let seconds = Int(self) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    var detailedFormattedDuration: String {
        let hours = Int(self) / 3600
        let minutes = Int(self) / 60 % 60
        let seconds = Int(self) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}
