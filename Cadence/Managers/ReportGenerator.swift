//
//  ReportGenerator.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 29/1/26.
//

import Foundation
import SwiftData

class ReportGenerator {
    
    // MARK: - Report Types
    enum ReportPeriod: Hashable, Equatable {
        case thisWeek
        case lastWeek
        case thisMonth
        case lastMonth
        case custom(start: Date, end: Date)
        
        var dateRange: (start: Date, end: Date) {
            let calendar = Calendar.current
            let now = Date()
            
            switch self {
            case .thisWeek:
                let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
                return (weekStart, weekEnd)
                
            case .lastWeek:
                let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!
                let lastWeekEnd = thisWeekStart
                return (lastWeekStart, lastWeekEnd)
                
            case .thisMonth:
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!
                return (monthStart, monthEnd)
                
            case .lastMonth:
                let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!
                let lastMonthEnd = thisMonthStart
                return (lastMonthStart, lastMonthEnd)
                
            case .custom(let start, let end):
                return (start, end)
            }
        }
        
        var displayName: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            
            switch self {
            case .thisWeek:
                return "This Week"
            case .lastWeek:
                return "Last Week"
            case .thisMonth:
                return "This Month"
            case .lastMonth:
                return "Last Month"
            case .custom(let start, let end):
                return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
            }
        }
    }
    
    // MARK: - Report Structure
    struct Report {
        let period: ReportPeriod
        let totalDuration: TimeInterval
        let totalBlocks: Int
        let totalSwitches: Int
        let activityBreakdown: [(name: String, duration: TimeInterval, percentage: Double, color: String)]
        let dailyTotals: [(date: Date, duration: TimeInterval)]
        let comparisonToPrevious: ComparisonData?
        let topActivities: [(name: String, duration: TimeInterval)]
        let mostProductiveDay: (date: Date, duration: TimeInterval)?
        
        struct ComparisonData {
            let previousTotalDuration: TimeInterval
            let durationChange: TimeInterval
            let percentageChange: Double
            let activityChanges: [(name: String, change: TimeInterval, percentageChange: Double)]
        }
    }
    
    // MARK: - Generate Report
    func generateReport(for period: ReportPeriod, blocks: [TimeBlock]) -> Report {
        let (start, end) = period.dateRange
        
        // Filter blocks for this period
        let periodBlocks = blocks.filter { block in
            block.startTime >= start && block.startTime < end
        }
        
        // Calculate total duration
        let totalDuration = periodBlocks.reduce(0) { $0 + $1.duration }
        
        // Calculate total switches
        let totalSwitches = periodBlocks.reduce(0) { $0 + $1.switchCount }
        
        // Activity breakdown
        var activityDurations: [String: (duration: TimeInterval, color: String)] = [:]
        for block in periodBlocks {
            let existing = activityDurations[block.activityName, default: (0, block.activityColor)]
            activityDurations[block.activityName] = (existing.duration + block.duration, block.activityColor)
        }
        
        let activityBreakdown = activityDurations.map { name, data in
            let percentage = totalDuration > 0 ? (data.duration / totalDuration) * 100 : 0
            return (name: name, duration: data.duration, percentage: percentage, color: data.color)
        }.sorted { $0.duration > $1.duration }
        
        // Daily totals
        let calendar = Calendar.current
        var dailyDurations: [Date: TimeInterval] = [:]
        for block in periodBlocks {
            let day = calendar.startOfDay(for: block.startTime)
            dailyDurations[day, default: 0] += block.duration
        }
        
        let dailyTotals = dailyDurations.sorted { $0.key < $1.key }.map { (date: $0.key, duration: $0.value) }
        
        // Most productive day
        let mostProductiveDay = dailyTotals.max { $0.duration < $1.duration }
        
        // Top 5 activities
        let topActivities = Array(activityBreakdown.prefix(5)).map { (name: $0.name, duration: $0.duration) }
        
        // Comparison to previous period
        let comparisonData = calculateComparison(currentBlocks: periodBlocks, period: period, allBlocks: blocks)
        
        return Report(
            period: period,
            totalDuration: totalDuration,
            totalBlocks: periodBlocks.count,
            totalSwitches: totalSwitches,
            activityBreakdown: activityBreakdown,
            dailyTotals: dailyTotals,
            comparisonToPrevious: comparisonData,
            topActivities: topActivities,
            mostProductiveDay: mostProductiveDay
        )
    }
    
    // MARK: - Comparison Calculation
    private func calculateComparison(currentBlocks: [TimeBlock], period: ReportPeriod, allBlocks: [TimeBlock]) -> Report.ComparisonData? {
        let calendar = Calendar.current
        let (currentStart, currentEnd) = period.dateRange
        
        // Calculate previous period range
        let (previousStart, previousEnd): (Date, Date)
        switch period {
        case .thisWeek, .lastWeek:
            let duration = currentEnd.timeIntervalSince(currentStart)
            previousEnd = currentStart
            previousStart = currentStart.addingTimeInterval(-duration)
            
        case .thisMonth, .lastMonth:
            previousEnd = currentStart
            previousStart = calendar.date(byAdding: .month, value: -1, to: currentStart)!
            
        case .custom:
            let duration = currentEnd.timeIntervalSince(currentStart)
            previousEnd = currentStart
            previousStart = currentStart.addingTimeInterval(-duration)
        }
        
        // Filter blocks for previous period
        let previousBlocks = allBlocks.filter { block in
            block.startTime >= previousStart && block.startTime < previousEnd
        }
        
        guard !previousBlocks.isEmpty else { return nil }
        
        // Calculate previous total duration
        let previousTotalDuration = previousBlocks.reduce(0) { $0 + $1.duration }
        let currentTotalDuration = currentBlocks.reduce(0) { $0 + $1.duration }
        
        let durationChange = currentTotalDuration - previousTotalDuration
        let percentageChange = previousTotalDuration > 0 ? (durationChange / previousTotalDuration) * 100 : 0
        
        // Calculate activity-level changes
        var currentActivityDurations: [String: TimeInterval] = [:]
        for block in currentBlocks {
            currentActivityDurations[block.activityName, default: 0] += block.duration
        }
        
        var previousActivityDurations: [String: TimeInterval] = [:]
        for block in previousBlocks {
            previousActivityDurations[block.activityName, default: 0] += block.duration
        }
        
        // Find all unique activities
        let allActivities = Set(currentActivityDurations.keys).union(Set(previousActivityDurations.keys))
        
        let activityChanges = allActivities.map { activity in
            let current = currentActivityDurations[activity] ?? 0
            let previous = previousActivityDurations[activity] ?? 0
            let change = current - previous
            let percentChange = previous > 0 ? (change / previous) * 100 : (current > 0 ? 100 : 0)
            return (name: activity, change: change, percentageChange: percentChange)
        }.sorted { abs($0.change) > abs($1.change) }
        
        return Report.ComparisonData(
            previousTotalDuration: previousTotalDuration,
            durationChange: durationChange,
            percentageChange: percentageChange,
            activityChanges: activityChanges
        )
    }
    
    // MARK: - Format Report as Text
    func formatReportAsText(_ report: Report) -> String {
        var text = ""
        
        text += "# \(report.period.displayName) Report\n\n"
        
        // Summary
        text += "## Summary\n"
        text += "Total Time: \(report.totalDuration.formattedDuration)\n"
        text += "Activities: \(report.totalBlocks)\n"
        text += "Switches: \(report.totalSwitches)\n"
        
        if let mostProductive = report.mostProductiveDay {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            text += "Most Productive: \(formatter.string(from: mostProductive.date)) (\(mostProductive.duration.formattedDuration))\n"
        }
        
        text += "\n"
        
        // Top Activities
        text += "## Top Activities\n"
        for (index, activity) in report.topActivities.enumerated() {
            text += "\(index + 1). \(activity.name): \(activity.duration.formattedDuration)\n"
        }
        
        text += "\n"
        
        // Comparison
        if let comparison = report.comparisonToPrevious {
            text += "## Comparison to Previous Period\n"
            let changeSymbol = comparison.durationChange >= 0 ? "↑" : "↓"
            text += "Total Time: \(changeSymbol) \(abs(comparison.durationChange).formattedDuration) (\(String(format: "%.1f", abs(comparison.percentageChange)))%)\n"
            
            text += "\nBiggest Changes:\n"
            for change in comparison.activityChanges.prefix(5) {
                let symbol = change.change >= 0 ? "↑" : "↓"
                text += "  \(change.name): \(symbol) \(abs(change.change).formattedDuration)\n"
            }
        }
        
        return text
    }
}
