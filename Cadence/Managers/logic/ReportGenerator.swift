//
//  ReportGenerator.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 29/1/26.
//  UPDATED: Simplified to Day/Week/Month with better comparisons
//

import Foundation
import SwiftData

// MARK: - Top Level Structs
struct ActivityChange: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let change: TimeInterval
    let percentageChange: Double
    let goal: ActivityGoal
}

class ReportGenerator {
    
    // MARK: - Report Types
    enum ReportPeriod: String, CaseIterable, Hashable, Equatable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        
        var dateRange: (start: Date, end: Date) {
            let calendar = Calendar.current
            let now = Date()
            
            switch self {
            case .day:
                // Yesterday (full day)
                let today = calendar.startOfDay(for: now)
                let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
                return (yesterday, today)
                
            case .week:
                // This week (Monday to today, or Sunday to today depending on locale)
                let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                return (weekStart, now)
                
            case .month:
                // This month (1st to today)
                let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                return (monthStart, now)
            }
        }
        
        var displayName: String {
            rawValue
        }
        
        var comparisonDescription: String {
            switch self {
            case .day: return "vs. Avg of Last 3 Days"
            case .week: return "vs. Last Week"
            case .month: return "vs. Last Month"
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
            let activityChanges: [ActivityChange]
            let comparisonLabel: String  // e.g., "Last Week", "3-Day Avg"
        }
    }
    
    // MARK: - Generate Report
    func generateReport(for period: ReportPeriod, blocks: [TimeBlock], activities: [Activity]) -> Report {
        let (start, end) = period.dateRange
        let periodBlocks = blocks.filter { $0.startTime >= start && $0.startTime < end }
        
        let totalDuration = periodBlocks.reduce(0) { $0 + $1.duration }
        let totalSwitches = periodBlocks.reduce(0) { $0 + $1.switchCount }
        
        // Breakdown
        var durMap: [String: (TimeInterval, String)] = [:]
        for b in periodBlocks {
            let curr = durMap[b.activityName] ?? (0, b.activityColor)
            durMap[b.activityName] = (curr.0 + b.duration, b.activityColor)
        }
        
        let breakdown = durMap.map { k, v in
            (name: k, duration: v.0, percentage: totalDuration > 0 ? (v.0/totalDuration)*100 : 0, color: v.1)
        }.sorted { $0.duration > $1.duration }
        
        // Daily
        let cal = Calendar.current
        var dailyMap: [Date: TimeInterval] = [:]
        for b in periodBlocks {
            let d = cal.startOfDay(for: b.startTime)
            dailyMap[d, default: 0] += b.duration
        }
        let dailyTotals = dailyMap.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        
        let top5 = Array(breakdown.prefix(5)).map { ($0.name, $0.duration) }
        let bestDay = dailyTotals.max { $0.1 < $1.1 }
        
        // Goal Lookup
        let goalMap = Dictionary(activities.map { ($0.name, $0.goal) }, uniquingKeysWith: { (first, _) in first })
        
        let comparison = calculateComparison(
            currentBlocks: periodBlocks,
            period: period,
            allBlocks: blocks,
            goalMap: goalMap
        )
        
        return Report(
            period: period,
            totalDuration: totalDuration,
            totalBlocks: periodBlocks.count,
            totalSwitches: totalSwitches,
            activityBreakdown: breakdown,
            dailyTotals: dailyTotals,
            comparisonToPrevious: comparison,
            topActivities: top5,
            mostProductiveDay: bestDay
        )
    }
    
    private func calculateComparison(
        currentBlocks: [TimeBlock],
        period: ReportPeriod,
        allBlocks: [TimeBlock],
        goalMap: [String: ActivityGoal]
    ) -> Report.ComparisonData? {
        let (cStart, cEnd) = period.dateRange
        let calendar = Calendar.current
        
        let (previousBlocks, comparisonLabel): ([TimeBlock], String)
        
        switch period {
        case .day:
            // Compare yesterday to average of 3 days before
            // Days: -4, -3, -2 (average)
            let day2 = calendar.date(byAdding: .day, value: -2, to: cStart)!
            let day3 = calendar.date(byAdding: .day, value: -3, to: cStart)!
            let day4 = calendar.date(byAdding: .day, value: -4, to: cStart)!
            
            let blocks = allBlocks.filter { block in
                (block.startTime >= day4 && block.startTime < day3) ||
                (block.startTime >= day3 && block.startTime < day2) ||
                (block.startTime >= day2 && block.startTime < cStart)
            }
            
            previousBlocks = blocks
            comparisonLabel = "3-Day Avg"
            
        case .week:
            // Compare this week to last week
            let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: cStart)!
            let lastWeekEnd = cStart
            
            previousBlocks = allBlocks.filter { $0.startTime >= lastWeekStart && $0.startTime < lastWeekEnd }
            comparisonLabel = "Last Week"
            
        case .month:
            // Compare this month to last month
            let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: cStart)!
            let lastMonthEnd = cStart
            
            previousBlocks = allBlocks.filter { $0.startTime >= lastMonthStart && $0.startTime < lastMonthEnd }
            comparisonLabel = "Last Month"
        }
        
        guard !previousBlocks.isEmpty else { return nil }
        
        // For day view, we need to average the 3 days
        let prevDur: TimeInterval
        if period == .day {
            let totalPrevDur = previousBlocks.reduce(0) { $0 + $1.duration }
            prevDur = totalPrevDur / 3.0  // Average of 3 days
        } else {
            prevDur = previousBlocks.reduce(0) { $0 + $1.duration }
        }
        
        let currDur = currentBlocks.reduce(0) { $0 + $1.duration }
        let diff = currDur - prevDur
        
        // Activity Changes
        var cMap: [String: TimeInterval] = [:]
        var pMap: [String: TimeInterval] = [:]
        
        for b in currentBlocks {
            cMap[b.activityName, default: 0] += b.duration
        }
        
        for b in previousBlocks {
            pMap[b.activityName, default: 0] += b.duration
        }
        
        // For day view, average the previous activities
        if period == .day {
            for key in pMap.keys {
                pMap[key] = (pMap[key] ?? 0) / 3.0
            }
        }
        
        let allNames = Set(cMap.keys).union(pMap.keys)
        let changes: [ActivityChange] = allNames.map { name in
            let c = cMap[name] ?? 0
            let p = pMap[name] ?? 0
            let chg = c - p
            let pct = p > 0 ? (chg/p)*100 : (c > 0 ? 100 : 0)
            return ActivityChange(
                name: name,
                change: chg,
                percentageChange: pct,
                goal: goalMap[name] ?? .neutral
            )
        }.sorted { abs($0.change) > abs($1.change) }
        
        return Report.ComparisonData(
            previousTotalDuration: prevDur,
            durationChange: diff,
            percentageChange: prevDur > 0 ? (diff/prevDur)*100 : 0,
            activityChanges: changes,
            comparisonLabel: comparisonLabel
        )
    }
    
    func formatReportAsText(_ report: Report) -> String {
        var text = "Report for \(report.period.displayName)\n"
        text += "Total: \(report.totalDuration.formattedDuration)\n"
        text += "Activities: \(report.totalBlocks)\n\n"
        
        if let comparison = report.comparisonToPrevious {
            text += "Comparison to \(comparison.comparisonLabel):\n"
            text += "Change: \(comparison.durationChange.formattedDuration) "
            text += "(\(String(format: "%.1f", comparison.percentageChange))%)\n\n"
        }
        
        text += "Top Activities:\n"
        for (name, duration) in report.topActivities {
            text += "- \(name): \(duration.formattedDuration)\n"
        }
        
        return text
    }
}
