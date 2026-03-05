//
//  ComputedGap.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 13/2/26.
//

import Foundation
import SwiftData

// MARK: - ComputedGap

/// A gap in the timeline — untracked time between two completed activity blocks.
/// This is a pure value type derived from block timestamps; it is never persisted.
struct ComputedGap: Identifiable {
    // FIX: Stable ID based on timestamps prevents SwiftUI from losing track of the row on refresh
    var id: String { "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// Gaps shorter than this are not shown or flagged for resolution.
    static let minimumDisplayDuration: TimeInterval = 60 // 1 minute
}

// MARK: - GapCalculator

enum GapCalculator {
    // 1. Simplify computeGaps
    static func computeGaps(
        in blocks: [TimeBlock],
        from rangeStart: Date,
        to rangeEnd: Date,
        minimumDuration: TimeInterval = ComputedGap.minimumDisplayDuration
    ) -> [ComputedGap] {
        let rawGaps = calculateRawGaps(
            in: blocks,
            from: rangeStart,
            to: rangeEnd,
            minimumDuration: 0
        )
        // No more rules or paused range subtracting! Just filter by duration.
        return rawGaps.filter { $0.duration >= minimumDuration }
    }

    // 2. Simplify totalUnaccountedDuration
    static func totalUnaccountedDuration(
        in blocks: [TimeBlock],
        from rangeStart: Date,
        to rangeEnd: Date
    ) -> TimeInterval {
        computeGaps(in: blocks, from: rangeStart, to: rangeEnd, minimumDuration: 0)
            .reduce(0) { $0 + $1.duration }
    }

    /// Number of gaps requiring resolution for a given day.
    /// Extends the day boundary past midnight when blocks do, so an overnight
    /// block (e.g. sleep ending at 7am next day) doesn't produce a false gap
    /// for the hours it covers on the following morning.
    static func gapCount(
        in blocks: [TimeBlock],
        rules: [TimeBlockRule] = [],
        for date: Date
    ) -> Int {
        let calendar     = Calendar.current
        let dayStart     = calendar.startOfDay(for: date)
        let calendarEnd  = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let cappedEnd    = min(calendarEnd, Date())   // don't count future time

        // Extend past midnight if any block on this day ends later
        let latestEnd    = blocks.compactMap { $0.endTime }.max() ?? cappedEnd
        let effectiveEnd = max(cappedEnd, min(latestEnd, Date()))

        return computeGaps(in: blocks, from: dayStart, to: effectiveEnd).count
    }

    // MARK: - Private Helpers

    /// Core gap detection: finds untracked windows between and around blocks
    /// within [rangeStart, rangeEnd]. Includes a leading gap (before the first
    /// block) and a trailing gap (after the last block) when applicable.
    private static func calculateRawGaps(
        in blocks: [TimeBlock],
        from rangeStart: Date,
        to rangeEnd: Date,
        minimumDuration: TimeInterval
    ) -> [ComputedGap] {

        // Only completed blocks participate in gap detection; ongoing blocks
        // by definition have no gap after them yet.
        let completed = blocks
            .filter { $0.endTime != nil }
            .sorted { $0.startTime < $1.startTime }

        var gaps: [ComputedGap] = []

        // Leading gap — before the first block
        if let first = completed.first, first.startTime > rangeStart {
            let gap = ComputedGap(start: rangeStart, end: first.startTime)
            if gap.duration >= minimumDuration { gaps.append(gap) }
        }

        // Gaps between consecutive blocks
        for (current, next) in zip(completed, completed.dropFirst()) {
            guard let blockEnd = current.endTime else { continue }
            if next.startTime > blockEnd {
                let gap = ComputedGap(start: blockEnd, end: next.startTime)
                if gap.duration >= minimumDuration { gaps.append(gap) }
            }
        }

        // If an ongoing block has already started, the gap ends where it began —
        // the ongoing block is covering time from that point forward.
        // If there is no ongoing block, report a gap to rangeEnd only when the
        // full range is in the past (avoids flagging unelapsed time as a gap).
        let ongoingStart = blocks.first(where: { $0.endTime == nil })?.startTime

        if let last = completed.last, let lastEnd = last.endTime {
            if let ongoingStart, ongoingStart > lastEnd {
                // Ongoing block is accounting for time from ongoingStart onward.
                // The only real gap is the window between the last completed block
                // and when the ongoing block started.
                let gap = ComputedGap(start: lastEnd, end: ongoingStart)
                if gap.duration >= minimumDuration { gaps.append(gap) }
            } else if ongoingStart == nil, lastEnd < rangeEnd, rangeEnd <= Date() {
                // No ongoing block — only flag a trailing gap if the entire range
                // is behind us, so we don't report future time as unaccounted.
                let gap = ComputedGap(start: lastEnd, end: rangeEnd)
                if gap.duration >= minimumDuration { gaps.append(gap) }
            }
            // If ongoingStart <= lastEnd, the ongoing block started before or exactly
            // when the last completed block ended — no trailing gap at all.
        }

        return gaps
    }

    /// Generates time ranges where tracking is paused based on rules.
    private static func resolvePausedRanges(
        rules: [TimeBlockRule],
        from start: Date,
        to end: Date
    ) -> [Range<Date>] {
        var ranges: [Range<Date>] = []
        let calendar = Calendar.current

        let pausedRules = rules.filter { $0.isEnabled }
        guard !pausedRules.isEmpty else { return [] }

        var currentDate = calendar.startOfDay(for: start)
        let finalDate   = calendar.startOfDay(for: end)

        while currentDate <= finalDate {
            let weekday = calendar.component(.weekday, from: currentDate)

            for rule in pausedRules {
                if !rule.daysOfWeek.isEmpty && !rule.daysOfWeek.contains(weekday) { continue }

                let startComps = calendar.dateComponents([.hour, .minute], from: rule.startTime)
                let endComps   = calendar.dateComponents([.hour, .minute], from: rule.endTime)

                guard
                    let dayStart = calendar.date(
                        bySettingHour: startComps.hour ?? 0,
                        minute: startComps.minute ?? 0,
                        second: 0, of: currentDate
                    ),
                    let dayEnd = calendar.date(
                        bySettingHour: endComps.hour ?? 0,
                        minute: endComps.minute ?? 0,
                        second: 0, of: currentDate
                    )
                else { continue }

                if dayStart < dayEnd {
                    ranges.append(dayStart..<dayEnd)
                } else {
                    // Overnight rule (e.g., 23:00 → 07:00)
                    let dayBeginning = calendar.startOfDay(for: currentDate)
                    let dayEnding    = calendar.date(byAdding: .day, value: 1, to: dayBeginning)!
                    ranges.append(dayBeginning..<dayEnd)
                    ranges.append(dayStart..<dayEnding)
                }
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        return ranges
    }

    /// Subtracts paused ranges from a source interval; returns remaining parts.
    private static func subtract(
        pausedRanges: [Range<Date>],
        from interval: ClosedRange<Date>
    ) -> [Range<Date>] {
        var result: [Range<Date>] = [interval.lowerBound..<interval.upperBound]

        for pause in pausedRanges {
            var next: [Range<Date>] = []
            for segment in result {
                let overlapStart = max(segment.lowerBound, pause.lowerBound)
                let overlapEnd   = min(segment.upperBound, pause.upperBound)

                if overlapStart < overlapEnd {
                    if segment.lowerBound < overlapStart {
                        next.append(segment.lowerBound..<overlapStart)
                    }
                    if overlapEnd < segment.upperBound {
                        next.append(overlapEnd..<segment.upperBound)
                    }
                } else {
                    next.append(segment)
                }
            }
            result = next
        }
        return result
    }
}

// MARK: - TimelineItem

enum TimelineItem: Identifiable {
    case activity(TimeBlock)
    case gap(ComputedGap)

    var id: String {
        switch self {
        case .activity(let b): return "activity-\(b.id.uuidString)"
        case .gap(let g):      return "gap-\(g.id)" // FIX: Uses string ID directly
        }
    }

    var startTime: Date {
        switch self {
        case .activity(let b): return b.startTime
        case .gap(let g):      return g.start
        }
    }
}
