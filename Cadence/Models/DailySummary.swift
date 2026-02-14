import Foundation
import SwiftData

@Model
final class DailySummary {
    /// Unique identifier: The date normalized to start-of-day (00:00:00)
    @Attribute(.unique) var date: Date
    
    // MARK: - Cached Metrics
    var totalDuration:       TimeInterval
    var unaccountedDuration: TimeInterval
    var blockCount:          Int
    var switchCount:         Int
    var fragmentationScore:  Double
    
    // MARK: - Serialized Data
    // We store the [ActivityName: Duration] dictionary as Data to avoid
    // complex relationships for simple historical stats.
    var activityBreakdownData: Data?
    
    // MARK: - Journal Snapshot
    var intention:  String
    var reflection: String
    
    // MARK: - Metadata
    var lastUpdated: Date

    init(date: Date, stats: DayStats, notes: DayNote?) {
        self.date = Calendar.current.startOfDay(for: date)
        self.totalDuration       = stats.totalDuration
        self.unaccountedDuration = stats.unaccountedDuration
        self.blockCount          = stats.blockCount
        self.switchCount         = stats.totalSwitches
        
        // Simple fragmentation: Switches per tracked hour
        let hours = stats.totalDuration / 3600
        self.fragmentationScore = hours > 0 ? Double(stats.totalSwitches) / hours : 0.0
        
        self.intention  = notes?.intention ?? ""
        self.reflection = notes?.reflection ?? ""
        self.lastUpdated = Date()
        
        if let data = try? JSONEncoder().encode(stats.activityDurations) {
            self.activityBreakdownData = data
        }
    }
    
    /// Hydrates the breakdown data back into a usable dictionary
    var activityBreakdown: [String: TimeInterval] {
        guard let data = activityBreakdownData else { return [:] }
        return (try? JSONDecoder().decode([String: TimeInterval].self, from: data)) ?? [:]
    }
    
    /// Converts cached summary back to a DayStats struct for View compatibility
    var asDayStats: DayStats {
        DayStats(
            totalDuration: totalDuration,
            activityDurations: activityBreakdown,
            totalSwitches: switchCount,
            blockCount: blockCount,
            unaccountedDuration: unaccountedDuration
        )
    }
}
