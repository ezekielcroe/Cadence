//
//  ConflictDetector.swift
//  Cadence
//
//  Changes in this revision:
//  - findGaps/unresolvedGapCount are thin calls into LedgerBuilder.
//    The private overnight-coverage logic is gone; the ledger owns it.
//  - findOverlappingBlocks queries by interval overlap against the
//    proposed range directly. The old 48-hour start-based window missed
//    any long block that started before the window and extended into it.
//

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

        if newEnd <= newStart { conflicts.append(.endBeforeStart) }
        if newEnd.timeIntervalSince(newStart) <= 0 { conflicts.append(.zeroOrNegativeDuration) }

        // Cross-midnight blocks are explicitly allowed.

        if conflicts.contains(where: { $0.severity == .blocking }) {
            return ValidationResult(isValid: false, conflicts: conflicts, canProceedWithConfirmation: false)
        }

        let overlaps = findOverlappingBlocks(
            excluding: block.id,
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

    // MARK: - Gap Detection (ledger-backed)

    func findGaps(for date: Date) -> [ComputedGap] {
        LedgerBuilder.makeLedger(for: date, context: modelContext).gaps
    }

    func unresolvedGapCount(for date: Date = Date()) -> Int {
        findGaps(for: date).count
    }

    // MARK: - Private Helpers

    /// Exact interval-overlap query against the proposed range. A block
    /// overlaps [proposedStart, proposedEnd) iff it starts before the end
    /// and (its end, or infinity if ongoing) is after the start.
    private func findOverlappingBlocks(
        excluding blockID: UUID,
        proposedStart: Date,
        proposedEnd: Date
    ) -> [TimeBlock] {
        let distantFuture = Date.distantFuture
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.id != blockID &&
                block.startTime < proposedEnd &&
                (block.endTime ?? distantFuture) > proposedStart
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
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
