//
//  DayPage.swift
//  Cadence
//
//  What one day looks like as a diary page: its entries (with their notes)
//  and the blank stretches between them, in time order, oldest first so
//  the day reads top to bottom. Built on DayLedger, so totals and gaps
//  always agree with every other screen.
//
//  Used by the Today tab and the Journal (Diary and Ledger views).
//

import Foundation
import SwiftData

// MARK: - DayPage

struct DayPage {

    struct Entry: Identifiable {
        let block: TimeBlock
        /// The part of the block that falls on this day.
        let clip: DateInterval
        /// Time tracked within this day (pauses excluded).
        let duration: TimeInterval
        /// Notes on the block, oldest first.
        let notes: [Remark]
        let isRunning: Bool
        let startsBeforeDay: Bool
        let endsAfterDay: Bool

        var id: UUID { block.id }
        var tags: [String] { TagIndex.uniqueSorted(notes.map(\.tags)) }
    }

    enum Item: Identifiable {
        case entry(Entry)
        case gap(ComputedGap)

        var id: String {
            switch self {
            case .entry(let entry): return "entry-\(entry.id.uuidString)"
            case .gap(let gap):     return "gap-\(gap.id)"
            }
        }

        var start: Date {
            switch self {
            case .entry(let entry): return entry.clip.start
            case .gap(let gap):     return gap.start
            }
        }
    }

    let day: Date                         // start of day
    let items: [Item]                     // oldest first
    let trackedDuration: TimeInterval
    let activityDurations: [String: TimeInterval]
    /// Notes on this day's entries (ignores filters).
    let noteCount: Int
    /// Blank stretches on the day (ignores filters and the minimum shown;
    /// excludes the live one when `dropTrailingGap`), for the
    /// accountability count in headers.
    let gapCount: Int

    var entries: [Entry] {
        items.compactMap { if case .entry(let entry) = $0 { return entry } else { return nil } }
    }

    var isEmpty: Bool { items.isEmpty }

    /// "6h 20m logged · mostly Meetings and Focused Work · 3 notes"
    var summary: String? {
        DaySummaryText.make(tracked: trackedDuration,
                            activityDurations: activityDurations,
                            noteCount: noteCount)
    }
}

// MARK: - Builder

enum DayPageBuilder {

    struct Options {
        /// Include a running (live timer) block as an entry.
        var includeRunning = true
        /// Include blank stretches at all.
        var includeGaps = true
        /// Blank stretches shorter than this are left out.
        var minimumGap: TimeInterval = ComputedGap.minimumDisplayDuration
        /// Leave out the blank stretch that runs up to `now`. On Today that
        /// time is the live counter on the "now" card, not part of the page.
        var dropTrailingGap = false
        /// Only entries of this activity (by name). Filters hide gaps.
        var activityName: String? = nil
        /// Only entries with a note carrying this tag. Filters hide gaps.
        var tag: String? = nil
    }

    /// Pure: `blocks` may include blocks from other days (they're clipped
    /// out); `remarks` may include notes on other blocks (ignored).
    static func make(
        for day: Date,
        blocks: [TimeBlock],
        remarks: [Remark],
        now: Date = Date(),
        window: TrackingWindow = .current,
        options: Options = Options(),
        calendar: Calendar = .current
    ) -> DayPage {
        let ledger = LedgerBuilder.makeLedger(for: day, blocks: blocks, now: now,
                                              window: window, calendar: calendar)

        let notesByBlock = Dictionary(grouping: remarks, by: \.timeBlockID)
            .mapValues { $0.sorted { $0.timestamp < $1.timestamp } }

        let filtering = options.activityName != nil || options.tag != nil
        var items: [DayPage.Item] = []
        var noteCount = 0

        for clipped in ledger.blocks {
            let block = clipped.block
            let notes = notesByBlock[block.id] ?? []
            noteCount += notes.count

            let isRunning = block.endTime == nil
            if isRunning && !options.includeRunning { continue }
            if let name = options.activityName, block.activityName != name { continue }
            if let tag = options.tag, !notes.contains(where: { $0.tags.contains(tag) }) { continue }

            items.append(.entry(DayPage.Entry(
                block: block,
                clip: clipped.clip,
                duration: clipped.trackedDuration,
                notes: notes,
                isRunning: isRunning,
                startsBeforeDay: block.startTime < ledger.date,
                endsAfterDay: (block.endTime ?? now) > clipped.clip.end
            )))
        }

        // The live stretch up to `now` isn't blank time yet; it's the counter.
        let gaps = ledger.gaps.filter {
            !(options.dropTrailingGap && $0.end >= ledger.generatedAt.addingTimeInterval(-1))
        }
        if options.includeGaps && !filtering {
            for gap in gaps where gap.duration >= options.minimumGap {
                items.append(.gap(gap))
            }
        }

        items.sort { a, b in
            if a.start != b.start { return a.start < b.start }
            if case .entry = a { return true }   // an entry before a gap at the same moment
            return false
        }

        return DayPage(
            day: ledger.date,
            items: items,
            trackedDuration: ledger.trackedDuration,
            activityDurations: ledger.activityDurations,
            noteCount: noteCount,
            gapCount: gaps.count
        )
    }
}

// MARK: - One-line day summary

enum DaySummaryText {

    /// "6h 20m logged · mostly Meetings and Focused Work · 3 notes".
    /// A second activity is named only if it has at least a fifth of the
    /// day. nil when there's nothing to say.
    static func make(tracked: TimeInterval,
                     activityDurations: [String: TimeInterval],
                     noteCount: Int) -> String? {
        var parts: [String] = []

        if tracked >= 60 {
            parts.append("\(tracked.formattedDuration) logged")

            let ranked = activityDurations
                .filter { $0.value > 0 }
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }

            if let first = ranked.first {
                if ranked.count == 1 {
                    parts.append("all \(first.key)")
                } else if ranked[1].value >= tracked * 0.2 {
                    parts.append("mostly \(first.key) and \(ranked[1].key)")
                } else {
                    parts.append("mostly \(first.key)")
                }
            }
        }

        if noteCount > 0 {
            parts.append("\(noteCount) note\(noteCount == 1 ? "" : "s")")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Fetching helpers (for views that aren't driven by @Query)

@MainActor
enum DayPageFetch {

    /// Blocks overlapping [start, end).
    static func blocks(from start: Date, to end: Date, in context: ModelContext) -> [TimeBlock] {
        let distantFuture = Date.distantFuture
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime < end && (block.endTime ?? distantFuture) > start
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// A ready-made page for one day — e.g. the reflection editor's summary.
    static func page(for day: Date, in context: ModelContext, now: Date = Date()) -> DayPage {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let blocks = blocks(from: start, to: end, in: context)
        let ids = Set(blocks.map(\.id))
        // A note is written during or after its block, so nothing older
        // than the earliest block start can belong to this day.
        let earliest = blocks.first?.startTime ?? start
        let notes = ((try? context.fetch(FetchDescriptor<Remark>(
            predicate: #Predicate { $0.timestamp >= earliest }
        ))) ?? []).filter { ids.contains($0.timeBlockID) }
        return DayPageBuilder.make(for: start, blocks: blocks, remarks: notes, now: now)
    }
}

// MARK: - Which days have a page

enum JournalDays {

    /// Days in [start, end) that have something to show (an entry
    /// touching the day, or a written intention/reflection), plus today
    /// if it falls in the range. Newest first.
    static func days(
        blocks: [TimeBlock],
        noteDays: [Date],
        from start: Date,
        to end: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        var days = Set<Date>()

        for block in blocks {
            let blockEnd = block.endTime ?? now
            let first = max(block.startTime, start)
            let last  = min(blockEnd.addingTimeInterval(-1), end.addingTimeInterval(-1))
            guard first <= last else { continue }
            var day = calendar.startOfDay(for: first)
            let lastDay = calendar.startOfDay(for: last)
            while day <= lastDay {
                days.insert(day)
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        }

        for noteDay in noteDays where noteDay >= start && noteDay < end {
            days.insert(calendar.startOfDay(for: noteDay))
        }

        let today = calendar.startOfDay(for: now)
        if today >= start && today < end { days.insert(today) }

        return days.sorted(by: >)
    }
}
