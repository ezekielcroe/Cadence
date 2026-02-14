//
//  HistoryManager.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 14/2/26.
//

import Foundation
import SwiftData

@MainActor
class HistoryManager {
    static let shared = HistoryManager()
    private init() {}
    
    /// Retrieves a summary for a specific date.
    /// If one exists, returns it. If not, calculates it from raw blocks, saves it, and returns it.
    func getOrGenerateSummary(for date: Date, in context: ModelContext) -> DailySummary? {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        
        // 1. Try fetch existing
        let descriptor = FetchDescriptor<DailySummary>(
            predicate: #Predicate { $0.date == normalizedDate }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        
        // 2. Generate if missing
        return regenerateSummary(for: normalizedDate, in: context)
    }
    
    /// Forces a re-calculation for a specific date. Call this when a block is edited/deleted.
    func invalidateDate(_ date: Date, in context: ModelContext) {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        _ = regenerateSummary(for: normalizedDate, in: context)
    }
    
    @discardableResult
    private func regenerateSummary(for date: Date, in context: ModelContext) -> DailySummary? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        // Fetch raw data for this day
        let blockDesc = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.startTime >= dayStart && $0.startTime < dayEnd }
        )
        let noteDesc = FetchDescriptor<DayNote>(
            predicate: #Predicate { $0.date == dayStart }
        )
        
        guard let blocks = try? context.fetch(blockDesc) else { return nil }
        let note = (try? context.fetch(noteDesc))?.first
        
        // Calculate Stats (Manual calculation to avoid dependency loops)
        var durations: [String: TimeInterval] = [:]
        var totalDur: TimeInterval = 0
        var switches = 0
        
        for block in blocks {
            let d = block.duration
            totalDur += d
            switches += block.switchCount
            durations[block.activityName, default: 0] += d
        }
        
        // Note: For historical summaries, we assume standard gap rules (no special exclusions)
        let unaccounted = GapCalculator.totalUnaccountedDuration(in: blocks, from: dayStart, to: dayEnd)
        
        let stats = DayStats(
            totalDuration: totalDur,
            activityDurations: durations,
            totalSwitches: switches,
            blockCount: blocks.count,
            unaccountedDuration: unaccounted
        )
        
        // Upsert
        let summaryDesc = FetchDescriptor<DailySummary>(predicate: #Predicate { $0.date == dayStart })
        
        if let existing = try? context.fetch(summaryDesc).first {
            existing.totalDuration       = stats.totalDuration
            existing.unaccountedDuration = stats.unaccountedDuration
            existing.blockCount          = stats.blockCount
            existing.switchCount         = stats.totalSwitches
            existing.activityBreakdownData = try? JSONEncoder().encode(stats.activityDurations)
            existing.intention           = note?.intention ?? ""
            existing.reflection          = note?.reflection ?? ""
            existing.lastUpdated         = Date()
            return existing
        } else {
            let newSummary = DailySummary(date: dayStart, stats: stats, notes: note)
            context.insert(newSummary)
            return newSummary
        }
    }
}
