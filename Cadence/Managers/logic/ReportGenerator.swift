import Foundation
import SwiftData

// MARK: - Global Helper Structs
// Moved outside ReportGenerator so ReportsView can access it directly
struct ActivityChange: Identifiable {
    var id: String { name }
    let name: String
    let currentDuration: TimeInterval
    let previousDuration: TimeInterval
    let goal: ActivityGoal
    
    var change: TimeInterval { currentDuration - previousDuration }
}

class ReportGenerator {
    
    // MARK: - Report Types
    enum ReportPeriod: String, CaseIterable, Hashable {
        case day = "Yesterday"
        case week = "Last Week"
        case month = "Month (MTD)"
        
        var displayName: String { rawValue }
        
        var comparisonDescription: String {
            switch self {
            case .day: return "vs. 7-Day Average"
            case .week: return "vs. 2 Weeks Ago"
            case .month: return "vs. Last Month (Same Days)"
            }
        }
    }
    
    // MARK: - Report Data Structures
    struct Report {
        let period: ReportPeriod
        let dateRange: String // e.g., "Oct 12 - Oct 18"
        
        let totalDuration: TimeInterval
        let unaccountedDuration: TimeInterval // ✅ ADDED: Fixes the error in ReportsView
        let totalBlocks: Int
        let activityBreakdown: [ActivityBreakdown]
        let comparisonToPrevious: ComparisonData?
        let topActivities: [ActivityBreakdown]
        
        struct ActivityBreakdown: Identifiable {
            var id: String { name }
            let name: String
            let duration: TimeInterval
            let percentage: Double
            let color: String
        }
        
        struct ComparisonData {
            let periodLabel: String // e.g., "Last Week"
            let comparisonLabel: String // e.g., "2 Weeks Ago"
            
            let currentDuration: TimeInterval
            let previousDuration: TimeInterval
            
            var durationChange: TimeInterval { currentDuration - previousDuration }
            var percentageChange: Double {
                guard previousDuration > 0 else { return 0 }
                return (durationChange / previousDuration) * 100
            }
            
            // Breakdown of changes by activity
            let activityChanges: [ActivityChange]
        }
    }
    
    // MARK: - Generators
    
    func generateReport(for period: ReportPeriod, blocks: [TimeBlock], activities: [Activity]) -> Report {
        let calendar = Calendar.current
        let now = Date()
        
        // 1. Determine Date Ranges
        let currentRange: (start: Date, end: Date)
        let previousRange: (start: Date, end: Date)
        var isAverageComparison = false
        
        switch period {
        case .day:
            // Current: Yesterday (Full Day)
            let todayStart = calendar.startOfDay(for: now)
            let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
            let yesterdayEnd = todayStart
            currentRange = (yesterdayStart, yesterdayEnd)
            
            // Previous: 7 Days prior to Yesterday
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: yesterdayStart)!
            previousRange = (sevenDaysAgo, yesterdayStart)
            isAverageComparison = true
            
        case .week:
            // Current: Last FULL Completed Week
            let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)!
            currentRange = (lastWeekStart, currentWeekStart)
            
            // Previous: The week before that
            let twoWeeksAgoStart = calendar.date(byAdding: .weekOfYear, value: -1, to: lastWeekStart)!
            previousRange = (twoWeeksAgoStart, lastWeekStart)
            
        case .month:
            // Current: Month to Date
            let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            currentRange = (thisMonthStart, now)
            
            // Previous: Last Month to Same Date
            let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!
            let daysInCurrent = calendar.dateComponents([.day], from: thisMonthStart, to: now).day ?? 0
            let lastMonthEndCandidate = calendar.date(byAdding: .day, value: daysInCurrent, to: lastMonthStart)!
            let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: lastMonthStart)!
            let lastMonthEnd = min(lastMonthEndCandidate, nextMonthStart)
            previousRange = (lastMonthStart, lastMonthEnd)
        }
        
        // 2. Filter Data
        let currentBlocks = filterBlocks(blocks, in: currentRange)
        let previousBlocks = filterBlocks(blocks, in: previousRange)
        
        // 3. Calculate Totals (Total Duration & Unaccounted Duration)
        let currentTotal = calculateTotalDuration(currentBlocks)
        
        // ✅ CALCULATE UNACCOUNTED DURATION (Gaps)
        let unaccountedTotal = currentBlocks
            .filter { $0.isGap }
            .reduce(0) { $0 + $1.duration }
        
        var previousTotal = calculateTotalDuration(previousBlocks)
        
        // ADJUSTMENT: If comparing against 7-day average, divide previous by 7
        if isAverageComparison {
            previousTotal /= 7.0
        }
        
        // 4. Generate Activity Breakdown (Current Period)
        let breakdown = generateBreakdown(blocks: currentBlocks, totalDuration: currentTotal)
        
        // 5. Generate Comparison Data
        var previousBreakdown = generateBreakdown(blocks: previousBlocks, totalDuration: 1)
        
        if isAverageComparison {
            previousBreakdown = previousBreakdown.map { item in
                Report.ActivityBreakdown(
                    name: item.name,
                    duration: item.duration / 7.0,
                    percentage: item.percentage,
                    color: item.color
                )
            }
        }
        
        let activityChanges = calculateActivityChanges(
            current: breakdown,
            previous: previousBreakdown,
            activities: activities
        )
        
        let comparison = Report.ComparisonData(
            periodLabel: period.displayName,
            comparisonLabel: period.comparisonDescription,
            currentDuration: currentTotal,
            previousDuration: previousTotal,
            activityChanges: activityChanges
        )
        
        // 6. Format Date Range String
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        let rangeString = "\(dateFormatter.string(from: currentRange.start)) - \(dateFormatter.string(from: currentRange.end.addingTimeInterval(-1)))"
        
        return Report(
            period: period,
            dateRange: rangeString,
            totalDuration: currentTotal,
            unaccountedDuration: unaccountedTotal, // ✅ Pass to struct
            totalBlocks: currentBlocks.count,
            activityBreakdown: breakdown,
            comparisonToPrevious: comparison,
            topActivities: Array(breakdown.prefix(5))
        )
    }
    
    // MARK: - Helper Methods
    
    private func filterBlocks(_ blocks: [TimeBlock], in range: (start: Date, end: Date)) -> [TimeBlock] {
        blocks.filter { block in
            // Filter 1: Must be within range
            guard block.startTime < range.end, (block.endTime ?? Date()) > range.start else { return false }
            
            // Filter 2: Ignore "Untracked" (Gray) blocks.
            // NOTE: We KEEP "Gap" (Orange) blocks so we can calculate unaccounted time.
            if block.isUntrackedBlock { return false }
            
            return true
        }
    }
    
    private func calculateTotalDuration(_ blocks: [TimeBlock]) -> TimeInterval {
        blocks.reduce(0) { total, block in
            if block.isUntrackedBlock { return total }
            return total + block.duration
        }
    }
    
    private func generateBreakdown(blocks: [TimeBlock], totalDuration: TimeInterval) -> [Report.ActivityBreakdown] {
        var dict: [String: (duration: TimeInterval, color: String)] = [:]
        
        for block in blocks {
            let name = block.displayName
            let duration = block.duration
            let color = block.activityColor
            
            if let existing = dict[name] {
                dict[name] = (existing.duration + duration, color)
            } else {
                dict[name] = (duration, color)
            }
        }
        
        let sorted = dict.map { key, value in
            Report.ActivityBreakdown(
                name: key,
                duration: value.duration,
                percentage: totalDuration > 0 ? (value.duration / totalDuration) : 0,
                color: value.color
            )
        }.sorted { $0.duration > $1.duration }
        
        return sorted
    }
    
    private func calculateActivityChanges(
        current: [Report.ActivityBreakdown],
        previous: [Report.ActivityBreakdown],
        activities: [Activity]
    ) -> [ActivityChange] {
        var changes: [ActivityChange] = []
        let prevDict = Dictionary(uniqueKeysWithValues: previous.map { ($0.name, $0.duration) })
        
        // 1. Check all current activities
        for item in current {
            let prevDuration = prevDict[item.name] ?? 0
            let goal = activities.first(where: { $0.name == item.name })?.goal ?? .neutral
            
            changes.append(ActivityChange(
                name: item.name,
                currentDuration: item.duration,
                previousDuration: prevDuration,
                goal: goal
            ))
        }
        
        // 2. Check activities that existed previously but are 0 now
        for item in previous {
            if !current.contains(where: { $0.name == item.name }) {
                let goal = activities.first(where: { $0.name == item.name })?.goal ?? .neutral
                
                changes.append(ActivityChange(
                    name: item.name,
                    currentDuration: 0,
                    previousDuration: item.duration,
                    goal: goal
                ))
            }
        }
        
        return changes.sorted { abs($0.change) > abs($1.change) }
    }
    
    func formatReportAsText(_ report: Report) -> String {
        var text = "Cadence Report: \(report.period.displayName)\n"
        text += "Period: \(report.dateRange)\n\n"
        
        text += "Total Duration: \(report.totalDuration.formattedDuration)\n"
        text += "Unaccounted: \(report.unaccountedDuration.formattedDuration)\n" // Added to text report
        
        if let comp = report.comparisonToPrevious {
            let sign = comp.durationChange >= 0 ? "+" : ""
            text += "Change: \(sign)\(comp.durationChange.formattedDuration) (\(sign)\(String(format: "%.1f", comp.percentageChange))%)\n"
        }
        
        text += "\nTop Activities:\n"
        for item in report.topActivities.prefix(5) {
            text += "• \(item.name): \(item.duration.formattedDuration)\n"
        }
        
        return text
    }
}
