//
//  ReportGenerator.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 29/1/26.
//

import Foundation
import SwiftData

// MARK: - Top Level Structs (Moved out to fix inference errors)
struct ActivityChange: Identifiable, Hashable {
    var id: String { name } // Conforms to Identifiable
    let name: String
    let change: TimeInterval
    let percentageChange: Double
    let goal: ActivityGoal
}

class ReportGenerator {
    
    // MARK: - Report Types
    enum ReportPeriod: Hashable, Equatable {
        case thisWeek, lastWeek, thisMonth, lastMonth
        case custom(start: Date, end: Date)
        
        var dateRange: (start: Date, end: Date) {
            let calendar = Calendar.current
            let now = Date()
            switch self {
            case .thisWeek:
                let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                return (start, calendar.date(byAdding: .day, value: 7, to: start)!)
            case .lastWeek:
                let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                let lastStart = calendar.date(byAdding: .weekOfYear, value: -1, to: start)!
                return (lastStart, start)
            case .thisMonth:
                let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                return (start, calendar.date(byAdding: .month, value: 1, to: start)!)
            case .lastMonth:
                let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                let lastStart = calendar.date(byAdding: .month, value: -1, to: start)!
                return (lastStart, start)
            case .custom(let s, let e): return (s, e)
            }
        }
        
        var displayName: String {
            switch self {
            case .thisWeek: return "This Week"
            case .lastWeek: return "Last Week"
            case .thisMonth: return "This Month"
            case .lastMonth: return "Last Month"
            case .custom: return "Custom"
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
            let activityChanges: [ActivityChange] // Uses the top-level struct
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
        
        let comparison = calculateComparison(currentBlocks: periodBlocks, period: period, allBlocks: blocks, goalMap: goalMap)
        
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
    
    private func calculateComparison(currentBlocks: [TimeBlock], period: ReportPeriod, allBlocks: [TimeBlock], goalMap: [String: ActivityGoal]) -> Report.ComparisonData? {
        let (cStart, cEnd) = period.dateRange
        let pEnd = cStart
        let pStart: Date
        
        // Calculate previous start
        switch period {
        case .thisWeek, .lastWeek:
            pStart = cStart.addingTimeInterval(-(cEnd.timeIntervalSince(cStart)))
        case .thisMonth, .lastMonth:
            pStart = Calendar.current.date(byAdding: .month, value: -1, to: cStart)!
        case .custom:
            pStart = cStart.addingTimeInterval(-(cEnd.timeIntervalSince(cStart)))
        }
        
        let prevBlocks = allBlocks.filter { $0.startTime >= pStart && $0.startTime < pEnd }
        if prevBlocks.isEmpty { return nil }
        
        let prevDur = prevBlocks.reduce(0) { $0 + $1.duration }
        let currDur = currentBlocks.reduce(0) { $0 + $1.duration }
        let diff = currDur - prevDur
        
        // Activity Changes
        var cMap: [String: TimeInterval] = [:]
        var pMap: [String: TimeInterval] = [:]
        for b in currentBlocks { cMap[b.activityName, default: 0] += b.duration }
        for b in prevBlocks { pMap[b.activityName, default: 0] += b.duration }
        
        let allNames = Set(cMap.keys).union(pMap.keys)
        let changes: [ActivityChange] = allNames.map { name in
            let c = cMap[name] ?? 0
            let p = pMap[name] ?? 0
            let chg = c - p
            let pct = p > 0 ? (chg/p)*100 : (c > 0 ? 100 : 0)
            return ActivityChange(name: name, change: chg, percentageChange: pct, goal: goalMap[name] ?? .neutral)
        }.sorted { abs($0.change) > abs($1.change) }
        
        return Report.ComparisonData(
            previousTotalDuration: prevDur,
            durationChange: diff,
            percentageChange: prevDur > 0 ? (diff/prevDur)*100 : 0,
            activityChanges: changes
        )
    }
    
    func formatReportAsText(_ report: Report) -> String {
        return "Report for \(report.period.displayName)\nTotal: \(report.totalDuration.formattedDuration)"
    }
}
