//
//  DurationFormat.swift
//  Cadence
//
//  Created by Yeo Zhi Zheng on 7/7/26.
//


//
//  LedgerRows.swift
//  Cadence
//
//  The one mapping from DayLedger to displayable rows. RecordsView and
//  TimesheetRenderer both consume this, so the exported sheet is the
//  screen restyled and the two can never drift.
//
//  Rounding policy: start and end are rounded to the nearest minute HERE,
//  once. Row durations are end − start of the ROUNDED values, subtotals
//  sum the rounded durations, period totals sum the subtotals. A reviewer
//  with a calculator reconciles every number on the sheet.
//

import Foundation

// MARK: - Single duration format

enum DurationFormat {

    /// The one duration string used everywhere a reviewer might compare
    /// numbers: "7h 05m", "0h 45m". Zero-padded minutes so columns align.
    static func hoursMinutes(_ t: TimeInterval) -> String {
        let clamped = max(0, t)
        let totalMinutes = Int((clamped / 60).rounded())
        return String(format: "%dh %02dm", totalMinutes / 60, totalMinutes % 60)
    }

    static func roundedToMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded() * 60)
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let dayHeading: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM yyyy"
        return f
    }()
}

// MARK: - Row model

struct TimesheetRow: Identifiable {
    enum Kind {
        case block
        case gap
    }

    let id: String
    let kind: Kind
    let start: Date              // minute-rounded
    let end: Date                // minute-rounded
    let activityName: String
    let activityColor: String?
    /// Total break time inside this row's span, minute-rounded. Zero for gaps.
    let breakDuration: TimeInterval
    let breakCount: Int
    let remarks: [String]        // hashtag handling decided at build time

    var duration: TimeInterval { end.timeIntervalSince(start) }
    /// Duration minus breaks: what actually counts toward totals.
    var netDuration: TimeInterval { max(0, duration - breakDuration) }
}

struct TimesheetDay: Identifiable {
    let date: Date               // startOfDay
    let rows: [TimesheetRow]
    let intention: String?
    let reflection: String?

    var id: Date { date }

    var trackedSubtotal: TimeInterval {
        rows.filter { $0.kind == .block }.reduce(0) { $0 + $1.netDuration }
    }
    var unaccountedSubtotal: TimeInterval {
        rows.filter { $0.kind == .gap }.reduce(0) { $0 + $1.duration }
    }
}

struct TimesheetDocument {
    let ownerName: String
    let periodStart: Date
    let periodEnd: Date
    let generatedAt: Date
    let windowDescription: String
    let days: [TimesheetDay]
    let includeGaps: Bool

    var periodLabel: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return "\(f.string(from: periodStart)) – \(f.string(from: periodEnd))"
    }

    var totalTracked: TimeInterval { days.reduce(0) { $0 + $1.trackedSubtotal } }
    var totalUnaccounted: TimeInterval { days.reduce(0) { $0 + $1.unaccountedSubtotal } }

    /// Period totals per activity, from row net durations, sorted descending.
    var activityTotals: [(name: String, duration: TimeInterval)] {
        var totals: [String: TimeInterval] = [:]
        for day in days {
            for row in day.rows where row.kind == .block {
                totals[row.activityName, default: 0] += row.netDuration
            }
        }
        return totals.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}

// MARK: - Builder

enum TimesheetBuilder {

    struct Options {
        var includeGaps = true
        var includeRemarks = true
        var stripHashtags = true
        var ownerName = ""
    }

    static func build(
        ledgers: [DayLedger],
        remarksByBlock: [UUID: [Remark]],
        notesByDay: [Date: DayNote],
        options: Options,
        generatedAt: Date = Date()
    ) -> TimesheetDocument {
        let sortedLedgers = ledgers.sorted { $0.date < $1.date }

        let days: [TimesheetDay] = sortedLedgers.map { ledger in
            var rows: [TimesheetRow] = []

            for clipped in ledger.blocks {
                let start = DurationFormat.roundedToMinute(clipped.clip.start)
                let end   = DurationFormat.roundedToMinute(clipped.clip.end)
                guard end > start else { continue }

                var remarks: [String] = []
                if options.includeRemarks,
                   let blockRemarks = remarksByBlock[clipped.block.id] {
                    remarks = blockRemarks
                        .sorted { $0.timestamp < $1.timestamp }
                        .filter { $0.timestamp >= clipped.clip.start && $0.timestamp <= clipped.clip.end }
                        .map { options.stripHashtags ? stripTags(from: $0.text) : $0.text }
                        .filter { !$0.isEmpty }
                }

                let pauseInClip = LedgerBuilder.pauseDuration(
                    of: clipped.block, within: clipped.clip, asOf: generatedAt)
                let breakMinutes = (pauseInClip / 60).rounded() * 60

                rows.append(TimesheetRow(
                    id: "block-\(clipped.block.id.uuidString)-\(ledger.date.timeIntervalSince1970)",
                    kind: .block,
                    start: start,
                    end: end,
                    activityName: clipped.block.activityName,
                    activityColor: clipped.block.activityColor,
                    breakDuration: breakMinutes,
                    breakCount: breakMinutes > 0 ? max(clipped.block.pauseCount, 1) : 0,
                    remarks: remarks
                ))
            }

            if options.includeGaps {
                for gap in ledger.gaps {
                    let start = DurationFormat.roundedToMinute(gap.start)
                    let end   = DurationFormat.roundedToMinute(gap.end)
                    guard end > start else { continue }
                    rows.append(TimesheetRow(
                        id: "gap-\(gap.id)",
                        kind: .gap,
                        start: start,
                        end: end,
                        activityName: "Unaccounted",
                        activityColor: nil,
                        breakDuration: 0,
                        breakCount: 0,
                        remarks: []
                    ))
                }
            }

            rows.sort { $0.start < $1.start }

            let note = notesByDay[ledger.date]
            return TimesheetDay(
                date: ledger.date,
                rows: rows,
                intention: note?.intention.isEmpty == false ? note?.intention : nil,
                reflection: note?.reflection.isEmpty == false ? note?.reflection : nil
            )
        }

        return TimesheetDocument(
            ownerName: options.ownerName,
            periodStart: sortedLedgers.first?.date ?? generatedAt,
            periodEnd: sortedLedgers.last?.date ?? generatedAt,
            generatedAt: generatedAt,
            windowDescription: TrackingWindow.current.displayString,
            days: days.filter { !$0.rows.isEmpty || $0.intention != nil || $0.reflection != nil },
            includeGaps: options.includeGaps
        )
    }

    private static func stripTags(from text: String) -> String {
        text.replacingOccurrences(
            of: #"#[a-zA-Z0-9][a-zA-Z0-9\-]*"#,
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}