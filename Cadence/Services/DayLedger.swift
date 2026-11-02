//
//  ComputedGap.swift
//  Cadence
//
//  Created by Yeo Zhi Zheng on 7/7/26.
//


//
//  DayLedger.swift
//  Cadence
//
//  REPLACES Models/Computes/ComputedGap.swift — delete that file.
//
//  Single source of truth for "what does a day look like".
//  Every consumer of blocks + gaps (RecordsView, TimelineListView,
//  HistoryManager, ReportGenerator, ConflictDetector, TimesheetBuilder,
//  getTodaysStats) reads from here. No other file computes gaps.
//
//  Rules encoded once:
//  - A block belongs to every day it OVERLAPS, clipped to that day.
//    No overnight special cases anywhere else.
//  - Gaps are the complement of the union of block intervals, restricted
//    to the tracking window segments of the day, and never extend past `now`.
//  - Overlapping blocks cannot inflate a day past 24h: durations come from
//    the union where totals matter, per-clip where per-block rows matter.
//

import Foundation
import SwiftData

// MARK: - ComputedGap (public type preserved — views depend on it)

struct ComputedGap: Identifiable, Equatable {
    var id: String { "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var interval: DateInterval { DateInterval(start: start, end: end) }

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    init(_ interval: DateInterval) {
        self.start = interval.start
        self.end = interval.end
    }

    /// Gaps shorter than this are not shown or flagged for resolution.
    static let minimumDisplayDuration: TimeInterval = 60
}

// MARK: - Interval math

enum LedgerMath {

    /// Merges overlapping/touching intervals into a sorted disjoint set.
    static func union(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }

        var result: [DateInterval] = []
        for next in sorted.dropFirst() {
            if next.start <= current.end {
                if next.end > current.end {
                    current = DateInterval(start: current.start, end: next.end)
                }
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }

    /// The parts of `bounds` not covered by `covered`.
    /// `covered` must be the output of `union(_:)` (sorted, disjoint).
    static func complement(of covered: [DateInterval], within bounds: DateInterval) -> [DateInterval] {
        guard bounds.duration > 0 else { return [] }
        var result: [DateInterval] = []
        var cursor = bounds.start

        for interval in covered {
            if interval.end <= cursor { continue }
            if interval.start >= bounds.end { break }
            if interval.start > cursor {
                result.append(DateInterval(start: cursor, end: min(interval.start, bounds.end)))
            }
            cursor = max(cursor, interval.end)
            if cursor >= bounds.end { break }
        }
        if cursor < bounds.end {
            result.append(DateInterval(start: cursor, end: bounds.end))
        }
        return result
    }

    static func intersection(_ a: DateInterval, _ b: DateInterval) -> DateInterval? {
        let start = max(a.start, b.start)
        let end   = min(a.end, b.end)
        return start < end ? DateInterval(start: start, end: end) : nil
    }
}

// MARK: - DayLedger

struct DayLedger {

    struct ClippedBlock: Identifiable {
        let block: TimeBlock
        /// The block's interval intersected with the day. Never falsified:
        /// `block.startTime`/`endTime` remain the record of truth; the clip
        /// exists so day totals and multi-day rendering are consistent.
        let clip: DateInterval
        /// Clip duration minus pause time falling inside the clip.
        let trackedDuration: TimeInterval

        var id: UUID { block.id }
    }

    let date: Date                       // startOfDay
    let generatedAt: Date
    /// Accountable segments for this day, already capped at `generatedAt`.
    let windowSegments: [DateInterval]
    let blocks: [ClippedBlock]           // sorted by clip.start
    let gaps: [ComputedGap]              // inside windowSegments only, >= 60s

    // MARK: Derived totals

    var trackedDuration: TimeInterval {
        blocks.reduce(0) { $0 + $1.trackedDuration }
    }

    var unaccountedDuration: TimeInterval {
        gaps.reduce(0) { $0 + $1.duration }
    }

    var blockCount: Int { blocks.count }

    /// Durations grouped by activity identity, keyed by display name.
    /// Grouping happens on activityID so renaming an activity does not fork
    /// its history; the name of the most recent block is used for display.
    /// Blocks with no activityID group by their snapshot name.
    var activityDurations: [String: TimeInterval] {
        struct Bucket { var duration: TimeInterval; var name: String; var latest: Date }
        var byKey: [String: Bucket] = [:]

        for clipped in blocks {
            let key = clipped.block.activityID?.uuidString ?? "name:\(clipped.block.activityName)"
            if var bucket = byKey[key] {
                bucket.duration += clipped.trackedDuration
                if clipped.block.startTime > bucket.latest {
                    bucket.name = clipped.block.activityName
                    bucket.latest = clipped.block.startTime
                }
                byKey[key] = bucket
            } else {
                byKey[key] = Bucket(duration: clipped.trackedDuration,
                                    name: clipped.block.activityName,
                                    latest: clipped.block.startTime)
            }
        }

        var result: [String: TimeInterval] = [:]
        for bucket in byKey.values {
            result[bucket.name, default: 0] += bucket.duration
        }
        return result
    }

    var stats: DayStats {
        DayStats(
            totalDuration: trackedDuration,
            activityDurations: activityDurations,
            totalSwitches: 0,   // switchCount was never populated; field retained for compatibility
            blockCount: blockCount,
            unaccountedDuration: unaccountedDuration
        )
    }
}

// MARK: - LedgerBuilder

enum LedgerBuilder {

    /// Fetching variant. The predicate is OVERLAP-based, not start-based:
    /// a block belongs to every day it touches.
    @MainActor
    static func makeLedger(
        for date: Date,
        context: ModelContext,
        now: Date = Date(),
        window: TrackingWindow = .current
    ) -> DayLedger {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let distantFuture = Date.distantFuture
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime < dayEnd && (block.endTime ?? distantFuture) > dayStart
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        let blocks = (try? context.fetch(descriptor)) ?? []
        return makeLedger(for: date, blocks: blocks, now: now, window: window)
    }

    /// Pure variant — deterministic, unit-testable.
    static func makeLedger(
        for date: Date,
        blocks: [TimeBlock],
        now: Date = Date(),
        window: TrackingWindow = .current,
        calendar: Calendar = .current
    ) -> DayLedger {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let day      = DateInterval(start: dayStart, end: dayEnd)

        // 1. Clip blocks to the day. Ongoing blocks end at `now` for math.
        var clipped: [DayLedger.ClippedBlock] = []
        for block in blocks {
            let effectiveEnd = block.endTime ?? now
            guard effectiveEnd > block.startTime else { continue }
            let span = DateInterval(start: block.startTime, end: effectiveEnd)
            guard let clip = LedgerMath.intersection(span, day) else { continue }

            let pauseInClip = pauseDuration(of: block, within: clip, asOf: now)
            clipped.append(DayLedger.ClippedBlock(
                block: block,
                clip: clip,
                trackedDuration: max(0, clip.duration - pauseInClip)
            ))
        }
        clipped.sort { $0.clip.start < $1.clip.start }

        // 2. Window segments, capped at `now` — the future is never a gap.
        let cap = min(now, dayEnd)
        let segments = window.segments(on: dayStart, calendar: calendar)
            .compactMap { segment -> DateInterval? in
                guard segment.start < cap else { return nil }
                return DateInterval(start: segment.start, end: min(segment.end, cap))
            }

        // 3. Gaps: complement of the block union within each segment.
        let covered = LedgerMath.union(clipped.map(\.clip))
        var gaps: [ComputedGap] = []
        for segment in segments {
            for hole in LedgerMath.complement(of: covered, within: segment)
            where hole.duration >= ComputedGap.minimumDisplayDuration {
                gaps.append(ComputedGap(hole))
            }
        }
        gaps.sort { $0.start < $1.start }

        return DayLedger(
            date: dayStart,
            generatedAt: now,
            windowSegments: segments,
            blocks: clipped,
            gaps: gaps
        )
    }

    /// Pause time of `block` falling inside `clip`.
    /// PauseSpans are clipped exactly. The legacy `totalPauseDuration`
    /// (pre-migration blocks, which have no spans) cannot be placed in
    /// time, so it is apportioned proportionally to the clipped fraction.
    static func pauseDuration(
        of block: TimeBlock,
        within clip: DateInterval,
        asOf now: Date
    ) -> TimeInterval {
        var total: TimeInterval = 0

        for span in block.pauseSpans {
            let spanInterval = DateInterval(start: span.start, end: span.end ?? now)
            if spanInterval.duration > 0,
               let overlap = LedgerMath.intersection(spanInterval, clip) {
                total += overlap.duration
            }
        }

        if block.totalPauseDuration > 0 {
            let effectiveEnd = block.endTime ?? now
            let raw = effectiveEnd.timeIntervalSince(block.startTime)
            if raw > 0 {
                total += block.totalPauseDuration * (clip.duration / raw)
            }
        }
        return total
    }
}

// MARK: - GapCalculator (compatibility facade)
//
// Same signatures as before so TimelineListView and ReportGenerator keep
// compiling, but all math now routes through LedgerBuilder. The `rules`
// parameter is dead and ignored. Callers should pass OVERLAP-filtered
// blocks, not start-filtered (see INTEGRATION.md for the two one-line fixes).

enum GapCalculator {

    static func computeGaps(
        in blocks: [TimeBlock],
        from rangeStart: Date,
        to rangeEnd: Date,
        minimumDuration: TimeInterval = ComputedGap.minimumDisplayDuration
    ) -> [ComputedGap] {
        let calendar = Calendar.current
        let now = Date()
        let cappedEnd = min(rangeEnd, now)
        guard rangeStart < cappedEnd else { return [] }

        var gaps: [ComputedGap] = []
        var day = calendar.startOfDay(for: rangeStart)
        let requested = DateInterval(start: rangeStart, end: cappedEnd)

        while day < cappedEnd {
            let ledger = LedgerBuilder.makeLedger(for: day, blocks: blocks, now: now)
            for gap in ledger.gaps {
                if let clippedGap = LedgerMath.intersection(gap.interval, requested),
                   clippedGap.duration >= minimumDuration {
                    gaps.append(ComputedGap(clippedGap))
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return gaps
    }

    static func totalUnaccountedDuration(
        in blocks: [TimeBlock],
        from rangeStart: Date,
        to rangeEnd: Date
    ) -> TimeInterval {
        computeGaps(in: blocks, from: rangeStart, to: rangeEnd, minimumDuration: 0)
            .reduce(0) { $0 + $1.duration }
    }

    static func gapCount(
        in blocks: [TimeBlock],
        rules: [TimeBlockRule] = [],   // ignored — kept for source compatibility
        for date: Date
    ) -> Int {
        LedgerBuilder.makeLedger(for: date, blocks: blocks).gaps.count
    }
}

// MARK: - TimelineItem (public type preserved — views depend on it)

enum TimelineItem: Identifiable {
    case activity(TimeBlock)
    case gap(ComputedGap)

    var id: String {
        switch self {
        case .activity(let b): return "activity-\(b.id.uuidString)"
        case .gap(let g):      return "gap-\(g.id)"
        }
    }

    var startTime: Date {
        switch self {
        case .activity(let b): return b.startTime
        case .gap(let g):      return g.start
        }
    }
}