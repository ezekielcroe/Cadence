// ============================================================
// FILE: Cadence/Managers/state/ConflictDetector.swift
// FULL REPLACEMENT
// Changes:
//   - Removed .exceedsDayBoundary from TimeConflict enum
//   - Removed the calendar.isDate(inSameDayAs:) check from validateEdit()
//   - Updated findOverlappingBlocks to search a 48-hour window so it catches
//     blocks that a cross-midnight block might collide with on the next day
// ============================================================

import Foundation
import SwiftData

// MARK: - Conflict Types

enum TimeConflict: Identifiable, Equatable {
    case overlap(with: TimeBlock, overlapMinutes: Int)
    case completeOverwrite(victims: [TimeBlock])
    case endBeforeStart
    case zeroOrNegativeDuration

    var id: String {
        switch self {
        case .overlap(let block, _):          return "overlap-\(block.id)"
        case .completeOverwrite(let victims): return "overwrite-\(victims.map { $0.id.uuidString }.joined())"
        case .endBeforeStart:                 return "invalid-range"
        case .zeroOrNegativeDuration:         return "zero-duration"
        }
    }

    var severity: ConflictSeverity {
        switch self {
        case .endBeforeStart, .zeroOrNegativeDuration: return .blocking
        case .completeOverwrite:                        return .destructive
        case .overlap:                                  return .warning
        }
    }

    var description: String {
        switch self {
        case .overlap(let block, let minutes):
            return "Overlaps with \"\(block.activityName)\" by \(minutes) minutes"
        case .completeOverwrite(let victims):
            return "This will delete: \(victims.map { $0.activityName }.joined(separator: ", "))"
        case .endBeforeStart:
            return "End time must be after start time"
        case .zeroOrNegativeDuration:
            return "Block must have a positive duration"
        }
    }
}

// MARK: - Conflict Severity

enum ConflictSeverity {
    case warning
    case destructive
    case blocking
}

// MARK: - Validation Result

struct ValidationResult {
    let isValid: Bool
    let conflicts: [TimeConflict]
    let canProceedWithConfirmation: Bool

    var blockingConflicts: [TimeConflict]    { conflicts.filter { $0.severity == .blocking } }
    var destructiveConflicts: [TimeConflict] { conflicts.filter { $0.severity == .destructive } }
    var warnings: [TimeConflict]             { conflicts.filter { $0.severity == .warning } }

    static var valid: ValidationResult {
        ValidationResult(isValid: true, conflicts: [], canProceedWithConfirmation: true)
    }
}

// MARK: - Conflict Detector

@MainActor
class ConflictDetector {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Edit Validation

    func validateEdit(block: TimeBlock, newStart: Date, newEnd: Date) -> ValidationResult {
        var conflicts: [TimeConflict] = []

        // Basic sanity checks
        if newEnd <= newStart { conflicts.append(.endBeforeStart) }
        if newEnd.timeIntervalSince(newStart) <= 0 { conflicts.append(.zeroOrNegativeDuration) }

        // NOTE: Cross-midnight blocks are explicitly allowed.
        // No exceedsDayBoundary check.

        if conflicts.contains(where: { $0.severity == .blocking }) {
            return ValidationResult(isValid: false, conflicts: conflicts, canProceedWithConfirmation: false)
        }

        // Search a 48-hour window centred on the start day so we catch both
        // blocks on the start day and any block on the following day that an
        // overnight block could collide with.
        let calendar = Calendar.current
        let searchStart = calendar.startOfDay(for: newStart)
        let searchEnd   = calendar.date(byAdding: .day, value: 2, to: searchStart)!

        let overlaps = findOverlappingBlocks(
            excluding: block.id,
            from: searchStart,
            to: searchEnd,
            proposedStart: newStart,
            proposedEnd: newEnd
        )

        for other in overlaps {
            let otherEnd = other.endTime ?? Date()
            if newStart <= other.startTime && newEnd >= otherEnd {
                let victims = overlaps.filter { victim in
                    let victimEnd = victim.endTime ?? Date()
                    return newStart <= victim.startTime && newEnd >= victimEnd
                }
                if !victims.isEmpty { conflicts.append(.completeOverwrite(victims: victims)) }
                break
            } else {
                let overlapStart   = max(newStart, other.startTime)
                let overlapEnd     = min(newEnd, otherEnd)
                let overlapMinutes = Int(overlapEnd.timeIntervalSince(overlapStart) / 60)
                if overlapMinutes > 0 {
                    conflicts.append(.overlap(with: other, overlapMinutes: overlapMinutes))
                }
            }
        }

        let unique = deduplicateConflicts(conflicts)
        return ValidationResult(
            isValid: unique.isEmpty,
            conflicts: unique,
            canProceedWithConfirmation: !unique.contains { $0.severity == .blocking }
        )
    }

    // MARK: - Gap Detection

    func findGaps(for date: Date) -> [ComputedGap] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)

        // Fetch blocks that START on this day
        let endOfFetch = calendar.date(byAdding: .day, value: 2, to: dayStart)!
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime >= dayStart &&
                block.startTime < endOfFetch &&
                block.activityID != nil
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        let dayBlocks = (try? modelContext.fetch(descriptor)) ?? []

        // Effective range end: the later of calendar midnight or last block end
        let calendarEnd  = min(calendar.date(byAdding: .day, value: 1, to: dayStart)!, Date())
        let lastBlockEnd = dayBlocks.compactMap { $0.endTime }.max() ?? calendarEnd
        let effectiveEnd = max(calendarEnd, lastBlockEnd)

        // Effective range start: if an overnight block from the previous day bleeds
        // into today, don't report a gap during those covered hours.
        let effectiveStart = overnightCoverageEnd(before: dayStart) ?? dayStart

        return GapCalculator.computeGaps(in: dayBlocks, from: effectiveStart, to: effectiveEnd)
    }

    func unresolvedGapCount(for date: Date = Date()) -> Int {
        findGaps(for: date).count
    }

    // MARK: - Private Helpers

    /// Returns the endTime of any block that started on the previous day and
    /// ends on `dayStart` or later, i.e. an overnight block that covers the
    /// beginning of `dayStart`. Returns nil if no such block exists.
    private func overnightCoverageEnd(before dayStart: Date) -> Date? {
        let calendar      = Calendar.current
        let prevDayStart  = calendar.date(byAdding: .day, value: -1, to: dayStart)!

        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime >= prevDayStart &&
                block.startTime < dayStart &&
                block.activityID != nil
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        guard let prevBlocks = try? modelContext.fetch(descriptor) else { return nil }

        // Find the latest endTime among previous-day blocks that crosses into today
        return prevBlocks
            .compactMap { $0.endTime }
            .filter { $0 > dayStart }
            .max()
    }

    private func findOverlappingBlocks(
        excluding blockID: UUID,
        from rangeStart: Date,
        to rangeEnd: Date,
        proposedStart: Date,
        proposedEnd: Date
    ) -> [TimeBlock] {
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.id != blockID &&
                block.activityID != nil &&
                block.startTime >= rangeStart &&
                block.startTime < rangeEnd
            },
            sortBy: [SortDescriptor(\.startTime)]
        )

        guard let blocks = try? modelContext.fetch(descriptor) else { return [] }
        return blocks.filter { block in
            let blockEnd = block.endTime ?? Date()
            return proposedStart < blockEnd && proposedEnd > block.startTime
        }
    }

    private func deduplicateConflicts(_ conflicts: [TimeConflict]) -> [TimeConflict] {
        var seen = Set<String>()
        return conflicts.filter { seen.insert($0.id).inserted }
    }
}

// MARK: - Suggested Resolutions

extension ConflictDetector {

    struct Resolution: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let action: () -> Void
    }

    func suggestResolutions(
        for conflicts: [TimeConflict],
        block: TimeBlock,
        proposedStart: Date,
        proposedEnd: Date
    ) -> [Resolution] {
        var resolutions: [Resolution] = []

        for conflict in conflicts {
            switch conflict {
            case .overlap(let other, _):
                resolutions.append(Resolution(
                    title: "End at \(other.startTime.formatted(date: .omitted, time: .shortened))",
                    description: "Adjust end time to avoid overlap",
                    action: {}
                ))
                if let otherEnd = other.endTime {
                    resolutions.append(Resolution(
                        title: "Start at \(otherEnd.formatted(date: .omitted, time: .shortened))",
                        description: "Adjust start time to avoid overlap",
                        action: {}
                    ))
                }
            case .completeOverwrite(let victims):
                resolutions.append(Resolution(
                    title: "Delete \(victims.count) block\(victims.count == 1 ? "" : "s") and proceed",
                    description: "This cannot be undone",
                    action: {}
                ))
            default:
                break
            }
        }

        return resolutions
    }
}
