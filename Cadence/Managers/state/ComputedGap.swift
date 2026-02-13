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

    /// Computes all gaps within a time range from a set of activity blocks,
    /// respecting "Paused" TimeBlockRules.
    ///
    /// - Parameters:
    ///   - blocks:       The complete set of TimeBlocks for the range.
    ///   - rules:        The list of TimeBlockRules to check for "Paused" mode.
    ///   - rangeStart:   The earliest time a gap could begin.
    ///   - rangeEnd:     The latest time a gap could end.
    ///   - minimumDuration: Gaps shorter than this are excluded.
    /// - Returns: Sorted array of ComputedGap values.
    static func computeGaps(
        in blocks: [TimeBlock],
        rules: [TimeBlockRule] = [], // Default to empty for backward compatibility
        from rangeStart: Date,
        to rangeEnd: Date,
        minimumDuration: TimeInterval = ComputedGap.minimumDisplayDuration
    ) -> [ComputedGap] {

        // 1. Identify raw gaps between blocks (ignoring rules)
        let rawGaps = calculateRawGaps(in: blocks, from: rangeStart, to: rangeEnd, minimumDuration: 0)

        // 2. If no rules, just filter by duration and return
        if rules.isEmpty {
            return rawGaps.filter { $0.duration >= minimumDuration }
        }

        // 3. Subtract "Paused" time ranges from the raw gaps
        // Identify all time ranges where tracking is Paused
        let pausedRanges = resolvePausedRanges(rules: rules, from: rangeStart, to: rangeEnd)
        
        var finalGaps: [ComputedGap] = []
        
        for gap in rawGaps {
            // Subtract paused ranges from this specific gap
            let remainingIntervals = subtract(pausedRanges: pausedRanges, from: gap.start...gap.end)
            
            // Create new gaps from the remaining intervals
            for interval in remainingIntervals {
                if interval.upperBound.timeIntervalSince(interval.lowerBound) >= minimumDuration {
                    finalGaps.append(ComputedGap(start: interval.lowerBound, end: interval.upperBound))
                }
            }
        }

        return finalGaps
    }

    /// Total unaccounted duration within a range.
    static func totalUnaccountedDuration(
        in blocks: [TimeBlock],
        rules: [TimeBlockRule] = [],
        from rangeStart: Date,
        to rangeEnd: Date
    ) -> TimeInterval {
        computeGaps(in: blocks, rules: rules, from: rangeStart, to: rangeEnd, minimumDuration: 0)
            .reduce(0) { $0 + $1.duration }
    }

    /// Number of gaps requiring resolution for a given day.
    static func gapCount(
        in blocks: [TimeBlock],
        rules: [TimeBlockRule] = [],
        for date: Date
    ) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd   = min(calendar.date(byAdding: .day, value: 1, to: dayStart)!, Date())
        return computeGaps(in: blocks, rules: rules, from: dayStart, to: dayEnd).count
    }
    
    // MARK: - Private Helpers
    
    /// Basic gap detection logic (between blocks only).
    private static func calculateRawGaps(
        in blocks: [TimeBlock],
        from rangeStart: Date,
        to rangeEnd: Date,
        minimumDuration: TimeInterval
    ) -> [ComputedGap] {
        let completed = blocks
            .filter { $0.endTime != nil }
            .sorted { $0.startTime < $1.startTime }

        var gaps: [ComputedGap] = []

        // Gap before the first block
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
        
        return gaps
    }
    
    /// Generates a list of time ranges where tracking is effectively paused based on rules.
    private static func resolvePausedRanges(
        rules: [TimeBlockRule],
        from start: Date,
        to end: Date
    ) -> [Range<Date>] {
        var ranges: [Range<Date>] = []
        let calendar = Calendar.current
        
        // Only consider rules that are enabled and set to 'off' (Paused)
        let pausedRules = rules.filter { $0.isEnabled && $0.trackingMode == .off }
        
        guard !pausedRules.isEmpty else { return [] }
        
        // Iterate through every day in the requested range to generate specific Paused intervals
        var currentDate = calendar.startOfDay(for: start)
        let finalDate = calendar.startOfDay(for: end)
        
        while currentDate <= finalDate {
            let currentDayComponent = calendar.component(.weekday, from: currentDate)
            
            for rule in pausedRules {
                // Check if rule applies to this day
                // (Empty daysOfWeek means applies every day)
                if !rule.daysOfWeek.isEmpty && !rule.daysOfWeek.contains(currentDayComponent) {
                    continue
                }
                
                // Construct start/end times for this specific day
                let ruleStartComponents = calendar.dateComponents([.hour, .minute], from: rule.startTime)
                let ruleEndComponents = calendar.dateComponents([.hour, .minute], from: rule.endTime)
                
                guard let dayStart = calendar.date(bySettingHour: ruleStartComponents.hour ?? 0,
                                                 minute: ruleStartComponents.minute ?? 0,
                                                 second: 0, of: currentDate),
                      let dayEnd = calendar.date(bySettingHour: ruleEndComponents.hour ?? 0,
                                               minute: ruleEndComponents.minute ?? 0,
                                               second: 0, of: currentDate)
                else { continue }
                
                if dayStart < dayEnd {
                    // Standard rule (e.g., 14:00 to 16:00)
                    ranges.append(dayStart..<dayEnd)
                } else {
                    // Overnight rule (e.g., 23:00 to 07:00)
                    // Applies to 00:00-07:00 AND 23:00-24:00 on this day
                    let dayBeginning = calendar.startOfDay(for: currentDate)
                    let dayEnding = calendar.date(byAdding: .day, value: 1, to: dayBeginning)!
                    
                    ranges.append(dayBeginning..<dayEnd) // 00:00 to 07:00
                    ranges.append(dayStart..<dayEnding)   // 23:00 to 24:00
                }
            }
            
            // Move to next day
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return ranges
    }
    
    /// Subtracts a list of exclusion ranges (pauses) from a source time interval.
    /// Returns the remaining parts of the interval.
    private static func subtract(
        pausedRanges: [Range<Date>],
        from interval: ClosedRange<Date>
    ) -> [Range<Date>] {
        // Convert ClosedRange to Range for easier calculation
        var result: [Range<Date>] = [interval.lowerBound..<interval.upperBound]
        
        for pause in pausedRanges {
            var nextResult: [Range<Date>] = []
            
            for segment in result {
                // Calculate intersection
                let overlapStart = max(segment.lowerBound, pause.lowerBound)
                let overlapEnd = min(segment.upperBound, pause.upperBound)
                
                if overlapStart < overlapEnd {
                    // Overlap exists; keep the parts outside the overlap
                    
                    // Part before the pause
                    if segment.lowerBound < overlapStart {
                        nextResult.append(segment.lowerBound..<overlapStart)
                    }
                    
                    // Part after the pause
                    if overlapEnd < segment.upperBound {
                        nextResult.append(overlapEnd..<segment.upperBound)
                    }
                } else {
                    // No overlap; keep segment as is
                    nextResult.append(segment)
                }
            }
            result = nextResult
        }
        
        return result
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
