//
//  ComputedGap.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 13/2/26.
//


// GapCalculator.swift
// Cadence
//
// Gaps are not stored. They are always derived from the space
// between the end of one activity block and the start of the next.

import Foundation

// MARK: - ComputedGap

/// A gap in the timeline — untracked time between two completed activity blocks.
/// This is a pure value type derived from block timestamps; it is never persisted.
struct ComputedGap: Identifiable {
    let id: UUID
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }

    init(start: Date, end: Date) {
        self.id = UUID()
        self.start = start
        self.end = end
    }

    /// Gaps shorter than this are not shown or flagged for resolution.
    static let minimumDisplayDuration: TimeInterval = 60 // 1 minute
}

// MARK: - GapCalculator

enum GapCalculator {

    /// Computes all gaps within a time range from a set of activity blocks.
    ///
    /// - Parameters:
    ///   - blocks:       The complete set of TimeBlocks for the range (mix of active and completed).
    ///   - rangeStart:   The earliest time a gap could begin (typically start of day).
    ///   - rangeEnd:     The latest time a gap could end (typically now, or end of day).
    ///   - minimumDuration: Gaps shorter than this are excluded. Defaults to 1 minute.
    /// - Returns: Sorted array of ComputedGap values.
    static func computeGaps(
        in blocks: [TimeBlock],
        from rangeStart: Date,
        to rangeEnd: Date,
        minimumDuration: TimeInterval = ComputedGap.minimumDisplayDuration
    ) -> [ComputedGap] {

        // Only completed blocks anchor gap boundaries.
        // An active block (endTime == nil) is still in progress — no gap after it.
        let completed = blocks
            .filter { $0.endTime != nil }
            .sorted { $0.startTime < $1.startTime }

        var gaps: [ComputedGap] = []

        // Gap before the first block (from rangeStart)
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

        // Note: we deliberately do NOT create a gap after the last block up to rangeEnd.
        // The user may simply have stopped tracking — that is not an error to resolve.

        return gaps
    }

    /// Total unaccounted duration within a range (no minimum filter).
    static func totalUnaccountedDuration(
        in blocks: [TimeBlock],
        from rangeStart: Date,
        to rangeEnd: Date
    ) -> TimeInterval {
        computeGaps(in: blocks, from: rangeStart, to: rangeEnd, minimumDuration: 0)
            .reduce(0) { $0 + $1.duration }
    }

    /// Number of gaps requiring resolution for a given day.
    static func gapCount(in blocks: [TimeBlock], for date: Date) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd   = min(calendar.date(byAdding: .day, value: 1, to: dayStart)!, Date())
        return computeGaps(in: blocks, from: dayStart, to: dayEnd).count
    }
}

// MARK: - TimelineItem
//
// Used by RecordsView to render a unified list of activity blocks and computed gaps.

enum TimelineItem: Identifiable {
    case activity(TimeBlock)
    case gap(ComputedGap)

    var id: String {
        switch self {
        case .activity(let b): return "activity-\(b.id.uuidString)"
        case .gap(let g):      return "gap-\(g.id.uuidString)"
        }
    }

    var startTime: Date {
        switch self {
        case .activity(let b): return b.startTime
        case .gap(let g):      return g.start
        }
    }
}
