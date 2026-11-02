import Foundation
import SwiftData

// MARK: - Global Helper Structs

struct ActivityChange: Identifiable {
    var id: String { name }
    let name: String
    let currentDuration: TimeInterval
    let previousDuration: TimeInterval
    let goal: ActivityGoal

    var change: TimeInterval { currentDuration - previousDuration }
}

// MARK: - ReportGenerator

class ReportGenerator {

    // MARK: - Report Period

    enum ReportPeriod: String, CaseIterable, Hashable {
        case day   = "Yesterday"
        case week  = "Last Week"
        case month = "Month (MTD)"

        var displayName: String { rawValue }

        var comparisonDescription: String {
            switch self {
            case .day:   return "vs. 7-Day Average"
            case .week:  return "vs. 2 Weeks Ago"
            case .month: return "vs. Last Month (Same Days)"
            }
        }
    }

    // MARK: - Report Data Structures

    struct Report {
        let period: ReportPeriod
        let dateRange: String

        let totalDuration: TimeInterval
        let unaccountedDuration: TimeInterval
        let totalBlocks: Int
        let activityBreakdown: [ActivityBreakdown]
        let comparisonToPrevious: ComparisonData?
        let topActivities: [ActivityBreakdown]

        // NEW: Semantic/qualitative layers
        let fragmentation: FragmentationData
        let tagBreakdown: [TagStat]
        let highlights: [RemarkHighlight]

        struct ActivityBreakdown: Identifiable {
            var id: String { name }
            let name: String
            let duration: TimeInterval
            let percentage: Double
            let color: String
        }

        struct ComparisonData {
            let periodLabel: String
            let comparisonLabel: String
            let currentDuration: TimeInterval
            let previousDuration: TimeInterval

            var durationChange: TimeInterval { currentDuration - previousDuration }
            var percentageChange: Double {
                guard previousDuration > 0 else { return 0 }
                return (durationChange / previousDuration) * 100
            }

            let activityChanges: [ActivityChange]
        }
    }

    // MARK: - Fragmentation Data
    //
    // A high fragmentation index means many short, frequently-interrupted sessions.
    // It is derived from switchCount relative to tracked hours —
    // a useful proxy for focus quality that requires no new data collection.

    struct FragmentationData {
        /// Average context switches per tracked hour
        let switchesPerHour: Double
        /// Average duration of a single tracked block (seconds)
        let averageBlockDuration: TimeInterval
        /// Qualitative label
        var label: String {
            switch switchesPerHour {
            case ..<2:  return "Focused"
            case 2..<5: return "Moderate"
            default:    return "Fragmented"
            }
        }
        var color: String {
            switch switchesPerHour {
            case ..<2:  return "#4CAF50"
            case 2..<5: return "#FF9800"
            default:    return "#F44336"
            }
        }
    }

    // MARK: - Tag Stats

    struct TagStat: Identifiable {
        var id: String { tag }
        let tag: String
        let count: Int               // how many remarks contain this tag
        let activities: [String]     // distinct activity names it appears on
    }

    // MARK: - Remark Highlight
    //
    // Surface up to 5 high-value remarks from "Keep High" activities
    // during the report period — the qualitative record of what happened.

    struct RemarkHighlight: Identifiable {
        let id: UUID
        let text: String
        let activityName: String
        let activityColor: String
        let timestamp: Date
        let tags: [String]
    }

    // MARK: - Generate Report

    /// Full report including semantic layers from remarks.
    func generateReport(
        for period: ReportPeriod,
        blocks: [TimeBlock],
        activities: [Activity],
        remarks: [Remark] = []
    ) -> Report {
        let calendar = Calendar.current
        let now = Date()

        // 1. Determine date ranges
        let currentRange: (start: Date, end: Date)
        let previousRange: (start: Date, end: Date)
        var isAverageComparison = false

        switch period {
        case .day:
            let todayStart     = calendar.startOfDay(for: now)
            let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
            currentRange       = (yesterdayStart, todayStart)
            let sevenDaysAgo   = calendar.date(byAdding: .day, value: -7, to: yesterdayStart)!
            previousRange      = (sevenDaysAgo, yesterdayStart)
            isAverageComparison = true

        case .week:
            let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let lastWeekStart    = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)!
            currentRange         = (lastWeekStart, currentWeekStart)
            let twoWeeksAgoStart = calendar.date(byAdding: .weekOfYear, value: -1, to: lastWeekStart)!
            previousRange        = (twoWeeksAgoStart, lastWeekStart)

        case .month:
            let thisMonthStart        = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            currentRange              = (thisMonthStart, now)
            let lastMonthStart        = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!
            let daysInCurrent         = calendar.dateComponents([.day], from: thisMonthStart, to: now).day ?? 0
            let lastMonthEndCandidate = calendar.date(byAdding: .day, value: daysInCurrent, to: lastMonthStart)!
            let nextMonthStart        = calendar.date(byAdding: .month, value: 1, to: lastMonthStart)!
            previousRange             = (lastMonthStart, min(lastMonthEndCandidate, nextMonthStart))
        }

        // 2. Filter blocks
        let currentBlocks  = filterBlocks(blocks, in: currentRange)
        let previousBlocks = filterBlocks(blocks, in: previousRange)

        // 3. Durations — clamped to each range so cross-boundary blocks
        //    only contribute the portion that falls within the period.
        let currentTotal = calculateTotalDuration(currentBlocks, in: currentRange)
        let unaccountedTotal = GapCalculator.totalUnaccountedDuration(
            in: currentBlocks, from: currentRange.start, to: currentRange.end
        )

        var previousTotal = calculateTotalDuration(previousBlocks, in: previousRange)
        if isAverageComparison { previousTotal /= 7.0 }

        // 4. Activity breakdown
        let breakdown = generateBreakdown(blocks: currentBlocks, totalDuration: currentTotal, in: currentRange)

        var previousBreakdown = generateBreakdown(blocks: previousBlocks, totalDuration: 1, in: previousRange)
        if isAverageComparison {
            previousBreakdown = previousBreakdown.map {
                Report.ActivityBreakdown(name: $0.name, duration: $0.duration / 7.0,
                                         percentage: $0.percentage, color: $0.color)
            }
        }

        // 5. Comparison
        let activityChanges = calculateActivityChanges(
            current: breakdown, previous: previousBreakdown, activities: activities
        )
        let comparison = Report.ComparisonData(
            periodLabel: period.displayName,
            comparisonLabel: period.comparisonDescription,
            currentDuration: currentTotal,
            previousDuration: previousTotal,
            activityChanges: activityChanges
        )

        // 6. Fragmentation index
        let fragmentation = calculateFragmentation(blocks: currentBlocks, in: currentRange)

        // 7. Tag breakdown (from remarks in current range)
        let currentBlockIDs = Set(currentBlocks.map { $0.id })
        let currentRemarks  = remarks.filter { currentBlockIDs.contains($0.timeBlockID) }
        let tagBreakdown    = calculateTagBreakdown(remarks: currentRemarks, blocks: currentBlocks)

        // 8. Highlights — top remarks from high-value (goal = .increase) activities
        let highlights = generateHighlights(
            remarks: currentRemarks, blocks: currentBlocks, activities: activities
        )

        // 9. Date range label
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        let rangeString = "\(dateFormatter.string(from: currentRange.start)) – \(dateFormatter.string(from: currentRange.end.addingTimeInterval(-1)))"

        return Report(
            period:               period,
            dateRange:            rangeString,
            totalDuration:        currentTotal,
            unaccountedDuration:  unaccountedTotal,
            totalBlocks:          currentBlocks.count,
            activityBreakdown:    breakdown,
            comparisonToPrevious: comparison,
            topActivities:        Array(breakdown.prefix(5)),
            fragmentation:        fragmentation,
            tagBreakdown:         tagBreakdown,
            highlights:           highlights
        )
    }

    // MARK: - Fragmentation Calculation
    private func calculateFragmentation(blocks: [TimeBlock], in range: (start: Date, end: Date)) -> FragmentationData {
        guard !blocks.isEmpty else {
            return FragmentationData(switchesPerHour: 0, averageBlockDuration: 0)
        }
        
        // 1. Calculate total interruptions (Switches + Pauses)
        // Every new block is a switch, and every pause is an interruption.
        let totalPauses = blocks.reduce(0) { $0 + $1.pauseCount }
        let totalInterruptions = Double(blocks.count + totalPauses)
        
        // 2. Frequency of interruptions per hour
        let totalHours = calculateTotalDuration(blocks, in: range) / 3600
        let interruptionsPerHr = totalHours > 0 ? totalInterruptions / totalHours : 0
        
        // 3. Average focus segment duration
        // We divide the total tracked time by the number of uninterrupted segments.
        let avgBlock = calculateTotalDuration(blocks, in: range) / totalInterruptions
        
        return FragmentationData(
            switchesPerHour: interruptionsPerHr,
            averageBlockDuration: avgBlock
        )
    }

    // MARK: - Tag Breakdown

    private func calculateTagBreakdown(remarks: [Remark], blocks: [TimeBlock]) -> [TagStat] {
        let blockLookup = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.activityName) })

        var tagData: [String: (count: Int, activities: Set<String>)] = [:]
        for remark in remarks {
            let activityName = blockLookup[remark.timeBlockID] ?? "Unknown"
            for tag in remark.tags {
                var existing = tagData[tag] ?? (count: 0, activities: Set<String>())
                existing.count += 1
                existing.activities.insert(activityName)
                tagData[tag] = existing
            }
        }

        return tagData
            .map { tag, data in
                TagStat(tag: tag, count: data.count, activities: Array(data.activities).sorted())
            }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Highlights

    private func generateHighlights(
        remarks: [Remark],
        blocks: [TimeBlock],
        activities: [Activity]
    ) -> [RemarkHighlight] {
        // Build lookup structures
        let blockLookup      = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        let activityGoalLookup: [String: ActivityGoal] = Dictionary(
            activities.map { ($0.name, $0.goal) },
            uniquingKeysWith: { first, _ in first }
        )

        // Prioritise remarks on "Keep High" activities, then others
        let sorted = remarks.sorted { a, b in
            let aGoal = blockLookup[a.timeBlockID].flatMap { activityGoalLookup[$0.activityName] } ?? .neutral
            let bGoal = blockLookup[b.timeBlockID].flatMap { activityGoalLookup[$0.activityName] } ?? .neutral
            if aGoal == .increase && bGoal != .increase { return true }
            if aGoal != .increase && bGoal == .increase { return false }
            return a.timestamp > b.timestamp  // most recent first within same priority
        }

        return sorted.prefix(6).compactMap { remark in
            guard let block = blockLookup[remark.timeBlockID] else { return nil }
            return RemarkHighlight(
                id:            remark.id,
                text:          remark.text,
                activityName:  block.activityName,
                activityColor: block.activityColor,
                timestamp:     remark.timestamp,
                tags:          remark.tags
            )
        }
    }

    // MARK: - Helpers

    /// Returns the portion of a block's active duration that falls within the given range.
    /// Blocks that merely overlap the range are clamped so only the intersecting
    /// segment is counted — this prevents a single cross-midnight block from
    /// inflating a day's total beyond 24 hours.
    private func clampedDuration(of block: TimeBlock, in range: (start: Date, end: Date)) -> TimeInterval {
        let blockStart = block.startTime
        let blockEnd   = block.endTime ?? Date()

        // Clamp to the portion that actually falls within the report range
        let effectiveStart = max(blockStart, range.start)
        let effectiveEnd   = min(blockEnd,   range.end)

        guard effectiveEnd > effectiveStart else { return 0 }

        let clampedRaw = effectiveEnd.timeIntervalSince(effectiveStart)

        // Proportionally scale down the pause duration.
        // If only half the block falls within the range, assume roughly half
        // the pause time belongs to this side. This is a reasonable heuristic
        // because we don't store individual pause timestamps.
        let fullRaw = blockEnd.timeIntervalSince(blockStart)
        let overlapRatio = fullRaw > 0 ? clampedRaw / fullRaw : 1.0
        let scaledPause  = block.pauseDuration * overlapRatio

        return max(0, clampedRaw - scaledPause)
    }

    private func filterBlocks(_ blocks: [TimeBlock], in range: (start: Date, end: Date)) -> [TimeBlock] {
        blocks.filter { $0.startTime < range.end && ($0.endTime ?? Date()) > range.start }
    }

    private func calculateTotalDuration(_ blocks: [TimeBlock], in range: (start: Date, end: Date)) -> TimeInterval {
        blocks.reduce(0) { $0 + clampedDuration(of: $1, in: range) }
    }

    private func generateBreakdown(blocks: [TimeBlock], totalDuration: TimeInterval, in range: (start: Date, end: Date)) -> [Report.ActivityBreakdown] {
        var dict: [String: (duration: TimeInterval, color: String)] = [:]
        for block in blocks {
            let d = clampedDuration(of: block, in: range)
            let existing = dict[block.activityName]
            dict[block.activityName] = ((existing?.duration ?? 0) + d, block.activityColor)
        }
        return dict
            .map { name, value in
                Report.ActivityBreakdown(
                    name: name,
                    duration: value.duration,
                    percentage: totalDuration > 0 ? (value.duration / totalDuration) : 0,
                    color: value.color
                )
            }
            .sorted { $0.duration > $1.duration }
    }

    private func calculateActivityChanges(
        current: [Report.ActivityBreakdown],
        previous: [Report.ActivityBreakdown],
        activities: [Activity]
    ) -> [ActivityChange] {
        var changes: [ActivityChange] = []
        let prevDict = Dictionary(
            previous.map { ($0.name, $0.duration) },
            uniquingKeysWith: { first, _ in first }
        )

        for item in current {
            changes.append(ActivityChange(
                name: item.name,
                currentDuration: item.duration,
                previousDuration: prevDict[item.name] ?? 0,
                goal: activities.first { $0.name == item.name }?.goal ?? .neutral
            ))
        }
        for item in previous where !current.contains(where: { $0.name == item.name }) {
            changes.append(ActivityChange(
                name: item.name,
                currentDuration: 0,
                previousDuration: item.duration,
                goal: activities.first { $0.name == item.name }?.goal ?? .neutral
            ))
        }

        return changes.sorted { abs($0.change) > abs($1.change) }
    }

    // MARK: - Text Export

    func formatReportAsText(_ report: Report) -> String {
        var text = "Cadence Report: \(report.period.displayName)\n"
        text += "Period: \(report.dateRange)\n\n"
        text += "Total Tracked: \(report.totalDuration.formattedDuration)\n"
        text += "Unaccounted:   \(report.unaccountedDuration.formattedDuration)\n"
        text += "Focus:         \(report.fragmentation.label) (\(String(format: "%.1f", report.fragmentation.switchesPerHour)) switches/hr)\n"

        if let comp = report.comparisonToPrevious {
            let sign = comp.durationChange >= 0 ? "+" : ""
            text += "Change: \(sign)\(comp.durationChange.formattedDuration) (\(sign)\(String(format: "%.1f", comp.percentageChange))%)\n"
        }

        text += "\nTop Activities:\n"
        for item in report.topActivities.prefix(5) {
            text += "• \(item.name): \(item.duration.formattedDuration)\n"
        }

        if !report.tagBreakdown.isEmpty {
            text += "\nTop Tags:\n"
            for tag in report.tagBreakdown.prefix(5) {
                text += "• #\(tag.tag): \(tag.count)×\n"
            }
        }

        if !report.highlights.isEmpty {
            text += "\nHighlights:\n"
            for h in report.highlights {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                text += "[\(formatter.string(from: h.timestamp))] \(h.activityName): \(h.text)\n"
            }
        }

        return text
    }
}
