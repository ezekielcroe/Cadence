import Foundation
import SwiftData

// MARK: - Activity Model
@Model
final class Activity {
    var id: UUID
    var name: String
    var color: String // Hex color string
    var setID: UUID // Reference to which set this belongs to
    var createdAt: Date
    var sortOrder: Int
    
    init(name: String, color: String, setID: UUID, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.color = color
        self.setID = setID
        self.createdAt = Date()
        self.sortOrder = sortOrder
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
    var name: String // e.g., "Work Hours", "Evening"
    var startTime: Date // Time of day (only hour/minute matter)
    var endTime: Date // Time of day
    var linkedSetID: UUID? // Optional: which activity set to activate
    var isEnabled: Bool
    var daysOfWeek: [Int] // 1=Sunday, 2=Monday, etc. Empty = all days
    var createdAt: Date
    
    init(name: String, startTime: Date, endTime: Date, linkedSetID: UUID? = nil, daysOfWeek: [Int] = []) {
        self.id = UUID()
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.linkedSetID = linkedSetID
        self.isEnabled = true
        self.daysOfWeek = daysOfWeek
        self.createdAt = Date()
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
}

// MARK: - Time Block Model
@Model
final class TimeBlock {
    var id: UUID
    var activityID: UUID
    var activityName: String // Denormalized for easier queries
    var activityColor: String // Denormalized
    var startTime: Date
    var endTime: Date?
    var isPaused: Bool
    var pauseStartTime: Date?
    var totalPauseDuration: TimeInterval // In seconds
    var switchCount: Int // Number of times activity was resumed (measures fragmentation)
    var remarks: String // User-added notes
    
    init(activityID: UUID, activityName: String, activityColor: String, startTime: Date) {
        self.id = UUID()
        self.activityID = activityID
        self.activityName = activityName
        self.activityColor = activityColor
        self.startTime = startTime
        self.endTime = nil
        self.isPaused = false
        self.pauseStartTime = nil
        self.totalPauseDuration = 0
        self.switchCount = 0
        self.remarks = ""
    }
    
    var duration: TimeInterval {
        guard let end = endTime else {
            // Activity is still running
            let currentDuration = Date().timeIntervalSince(startTime)
            return currentDuration - totalPauseDuration - (isPaused ? Date().timeIntervalSince(pauseStartTime ?? Date()) : 0)
        }
        return end.timeIntervalSince(startTime) - totalPauseDuration
    }
    
    var isActive: Bool {
        endTime == nil && !isPaused
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
