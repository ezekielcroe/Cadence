//
//  HistoryManager.swift
//  Cadence
//
//  REWRITTEN: summaries are generated from DayLedger, so they can no
//  longer disagree with any screen. invalidate(block:) covers every day
//  a block overlaps.
//

import Foundation
import SwiftData

@MainActor
class HistoryManager {
    static let shared = HistoryManager()
    private init() {}

    func getOrGenerateSummary(for date: Date, in context: ModelContext) -> DailySummary? {
        let normalizedDate = Calendar.current.startOfDay(for: date)

        let descriptor = FetchDescriptor<DailySummary>(
            predicate: #Predicate { $0.date == normalizedDate }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        return regenerateSummary(for: normalizedDate, in: context)
    }

    /// Regenerates the summary of every day the block overlaps.
    /// An overnight block touches two days; both must be refreshed.
    func invalidate(block: TimeBlock, in context: ModelContext) {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: block.startTime)
        let lastDay = calendar.startOfDay(for: block.endTime ?? Date())

        while day <= lastDay {
            _ = regenerateSummary(for: day, in: context)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
    }

    /// Single-date variant, kept for callers that edit by date (e.g. notes).
    func invalidateDate(_ date: Date, in context: ModelContext) {
        _ = regenerateSummary(for: Calendar.current.startOfDay(for: date), in: context)
    }

    /// Every day in [start, end]. For when the block itself is gone.
    func invalidate(from start: Date, to end: Date, in context: ModelContext) {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: max(start, end))
        while day <= lastDay {
            _ = regenerateSummary(for: day, in: context)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
    }

    @discardableResult
    private func regenerateSummary(for date: Date, in context: ModelContext) -> DailySummary? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        // Sole source of day math.
        let ledger = LedgerBuilder.makeLedger(for: dayStart, context: context)
        let stats = ledger.stats

        let noteDesc = FetchDescriptor<DayNote>(
            predicate: #Predicate { $0.date == dayStart }
        )
        let note = (try? context.fetch(noteDesc))?.first

        let summaryDesc = FetchDescriptor<DailySummary>(
            predicate: #Predicate { $0.date == dayStart }
        )

        if let existing = try? context.fetch(summaryDesc).first {
            existing.totalDuration         = stats.totalDuration
            existing.unaccountedDuration   = stats.unaccountedDuration
            existing.blockCount            = stats.blockCount
            existing.switchCount           = stats.totalSwitches
            existing.activityBreakdownData = try? JSONEncoder().encode(stats.activityDurations)
            existing.intention             = note?.intention ?? ""
            existing.reflection            = note?.reflection ?? ""
            existing.lastUpdated           = Date()
            return existing
        } else {
            let newSummary = DailySummary(date: dayStart, stats: stats, notes: note)
            context.insert(newSummary)
            return newSummary
        }
    }
}
