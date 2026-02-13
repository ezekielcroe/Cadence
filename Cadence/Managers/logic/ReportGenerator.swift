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

    // MARK: - Generate Report

    func generateReport(for period: ReportPeriod, blocks: [TimeBlock], activities: [Activity]) -> Report {
        let calendar = Calendar.current
        let now = Date()

        // 1. Determine date ranges

        let currentRange: (start: Date, end: Date)
        let previousRange: (start: Date, end: Date)
        var isAverageComparison = false

        switch period {
        case .day:
            let todayStart      = calendar.startOfDay(for: now)
            let yesterdayStart  = calendar.date(byAdding: .day, value: -1, to: todayStart)!
            currentRange        = (yesterdayStart, todayStart)
            let sevenDaysAgo    = calendar.date(byAdding: .day, value: -7, to: yesterdayStart)!
            previousRange       = (sevenDaysAgo, yesterdayStart)
            isAverageComparison = true

        case .week:
            let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let lastWeekStart    = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)!
            currentRange         = (lastWeekStart, currentWeekStart)
            let twoWeeksAgoStart = calendar.date(byAdding: .weekOfYear, value: -1, to: lastWeekStart)!
            previousRange        = (twoWeeksAgoStart, lastWeekStart)

        case .month:
            let thisMonthStart       = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            currentRange             = (thisMonthStart, now)
            let lastMonthStart       = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!
            let daysInCurrent        = calendar.dateComponents([.day], from: thisMonthStart, to: now).day ?? 0
            let lastMonthEndCandidate = calendar.date(byAdding: .day, value: daysInCurrent, to: lastMonthStart)!
            let nextMonthStart       = calendar.date(byAdding: .month, value: 1, to: lastMonthStart)!
            previousRange            = (lastMonthStart, min(lastMonthEndCandidate, nextMonthStart))
        }

        // 2. Filter to activity blocks only within each range
        //    There are no gap/pause/untracked block types anymore — every stored TimeBlock
        //    is a real activity session. activityID being non-nil is the defensive check.
        let currentBlocks  = filterBlocks(blocks, in: currentRange)
        let previousBlocks = filterBlocks(blocks, in: previousRange)

        // 3. Calculate durations

        let currentTotal = calculateTotalDuration(currentBlocks)

        // Unaccounted time is the space between activity blocks — computed, never stored.
        let unaccountedTotal = GapCalculator.totalUnaccountedDuration(
            in: currentBlocks,
            from: currentRange.start,
            to: currentRange.end
        )

        var previousTotal = calculateTotalDuration(previousBlocks)
        if isAverageComparison { previousTotal /= 7.0 }

        // 4. Activity breakdown

        let breakdown = generateBreakdown(blocks: currentBlocks, totalDuration: currentTotal)

        var previousBreakdown = generateBreakdown(blocks: previousBlocks, totalDuration: 1)
        if isAverageComparison {
            previousBreakdown = previousBreakdown.map {
                Report.ActivityBreakdown(
                    name: $0.name,
                    duration: $0.duration / 7.0,
                    percentage: $0.percentage,
                    color: $0.color
                )
            }
        }

        // 5. Comparison data

        let activityChanges = calculateActivityChanges(
            current: breakdown,
            previous: previousBreakdown,
            activities: activities
        )

        let comparison = Report.ComparisonData(
            periodLabel:       period.displayName,
            comparisonLabel:   period.comparisonDescription,
            currentDuration:   currentTotal,
            previousDuration:  previousTotal,
            activityChanges:   activityChanges
        )

        // 6. Date range label

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        let rangeString = "\(dateFormatter.string(from: currentRange.start)) - \(dateFormatter.string(from: currentRange.end.addingTimeInterval(-1)))"

        return Report(
            period:               period,
            dateRange:            rangeString,
            totalDuration:        currentTotal,
            unaccountedDuration:  unaccountedTotal,
            totalBlocks:          currentBlocks.count,
            activityBreakdown:    breakdown,
            comparisonToPrevious: comparison,
            topActivities:        Array(breakdown.prefix(5))
        )
    }

    // MARK: - Helpers

    /// Returns activity blocks within a date range.
    /// Blocks are clipped to the range boundary if they span across it.
    private func filterBlocks(_ blocks: [TimeBlock], in range: (start: Date, end: Date)) -> [TimeBlock] {
        blocks.filter { block in
            guard block.activityID != nil else { return false }   // activity blocks only
            guard block.startTime < range.end else { return false }
            let blockEnd = block.endTime ?? Date()
            return blockEnd > range.start
        }
    }

    private func calculateTotalDuration(_ blocks: [TimeBlock]) -> TimeInterval {
        blocks.reduce(0) { $0 + $1.duration }
    }

    /// Groups blocks by activity name and sums their durations.
    /// Uses `activityName` (not `displayName`) so pause annotations don't
    /// fragment a single activity into multiple breakdown rows.
    private func generateBreakdown(blocks: [TimeBlock], totalDuration: TimeInterval) -> [Report.ActivityBreakdown] {
        var dict: [String: (duration: TimeInterval, color: String)] = [:]

        for block in blocks {
            let name = block.activityName   // raw name, no pause suffix
            let existing = dict[name]
            dict[name] = ((existing?.duration ?? 0) + block.duration, block.activityColor)
        }

        return dict
            .map { name, value in
                Report.ActivityBreakdown(
                    name:       name,
                    duration:   value.duration,
                    percentage: totalDuration > 0 ? (value.duration / totalDuration) : 0,
                    color:      value.color
                )
            }
            .sorted { $0.duration > $1.duration }
    }

    private func calculateActivityChanges(
        current:    [Report.ActivityBreakdown],
        previous:   [Report.ActivityBreakdown],
        activities: [Activity]
    ) -> [ActivityChange] {

        var changes: [ActivityChange] = []
        let prevDict = Dictionary(uniqueKeysWithValues: previous.map { ($0.name, $0.duration) })

        for item in current {
            changes.append(ActivityChange(
                name:             item.name,
                currentDuration:  item.duration,
                previousDuration: prevDict[item.name] ?? 0,
                goal:             activities.first { $0.name == item.name }?.goal ?? .neutral
            ))
        }

        // Activities that existed before but are absent this period
        for item in previous where !current.contains(where: { $0.name == item.name }) {
            changes.append(ActivityChange(
                name:             item.name,
                currentDuration:  0,
                previousDuration: item.duration,
                goal:             activities.first { $0.name == item.name }?.goal ?? .neutral
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

        if let comp = report.comparisonToPrevious {
            let sign = comp.durationChange >= 0 ? "+" : ""
            text += "Change: \(sign)\(comp.durationChange.formattedDuration) (\(sign)\(String(format: "%.1f", comp.percentageChange))%)\n"
        }

        text += "\nTop Activities:\n"
        for item in report.topActivities.prefix(5) {
            text += "• \(item.name): \(item.duration.formattedDuration)\n"
        }

        return text
    }
}
