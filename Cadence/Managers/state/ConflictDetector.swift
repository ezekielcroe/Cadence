//
//  ConflictDetector.swift
//  Cadence
//
//  Validates time block edits and detects conflicts
//

import Foundation
import SwiftData

// MARK: - Conflict Types

enum TimeConflict: Identifiable, Equatable {
    case overlap(with: TimeBlock, overlapMinutes: Int)
    case completeOverwrite(victims: [TimeBlock])
    case exceedsDayBoundary
    case endBeforeStart
    case zeroOrNegativeDuration
    
    var id: String {
        switch self {
        case .overlap(let block, _): return "overlap-\(block.id)"
        case .completeOverwrite(let victims): return "overwrite-\(victims.map { $0.id.uuidString }.joined())"
        case .exceedsDayBoundary: return "boundary"
        case .endBeforeStart: return "invalid-range"
        case .zeroOrNegativeDuration: return "zero-duration"
        }
    }
    
    var severity: ConflictSeverity {
        switch self {
        case .endBeforeStart, .zeroOrNegativeDuration: return .blocking
        case .completeOverwrite: return .destructive
        case .overlap: return .warning
        case .exceedsDayBoundary: return .warning
        }
    }
    
    var description: String {
        switch self {
        case .overlap(let block, let minutes):
            return "Overlaps with \"\(block.activityName)\" by \(minutes) minutes"
        case .completeOverwrite(let victims):
            let names = victims.map { $0.activityName }.joined(separator: ", ")
            return "This will delete: \(names)"
        case .exceedsDayBoundary:
            return "Time extends beyond the current day"
        case .endBeforeStart:
            return "End time must be after start time"
        case .zeroOrNegativeDuration:
            return "Block must have a positive duration"
        }
    }
}

enum ConflictSeverity {
    case warning     // Can proceed with confirmation
    case destructive // Requires explicit "I understand" confirmation
    case blocking    // Cannot proceed at all
}

// MARK: - Validation Result

struct ValidationResult {
    let isValid: Bool
    let conflicts: [TimeConflict]
    let canProceedWithConfirmation: Bool
    
    var blockingConflicts: [TimeConflict] {
        conflicts.filter { $0.severity == .blocking }
    }
    
    var destructiveConflicts: [TimeConflict] {
        conflicts.filter { $0.severity == .destructive }
    }
    
    var warnings: [TimeConflict] {
        conflicts.filter { $0.severity == .warning }
    }
    
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
    
    // MARK: - Main Validation Entry Point
    
    /// Validate a proposed edit to a time block
    func validateEdit(
        block: TimeBlock,
        newStart: Date,
        newEnd: Date
    ) -> ValidationResult {
        var conflicts: [TimeConflict] = []
        
        // 1. Basic validity checks
        if newEnd <= newStart {
            conflicts.append(.endBeforeStart)
        }
        
        let duration = newEnd.timeIntervalSince(newStart)
        if duration <= 0 {
            conflicts.append(.zeroOrNegativeDuration)
        }
        
        // 2. Day boundary check
        let calendar = Calendar.current
        if !calendar.isDate(newStart, inSameDayAs: newEnd) {
            conflicts.append(.exceedsDayBoundary)
        }
        
        // If we have blocking conflicts, return early
        if conflicts.contains(where: { $0.severity == .blocking }) {
            return ValidationResult(
                isValid: false,
                conflicts: conflicts,
                canProceedWithConfirmation: false
            )
        }
        
        // 3. Find overlapping blocks
        let dayStart = calendar.startOfDay(for: newStart)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        let overlaps = findOverlappingBlocks(
            excluding: block.id,
            in: dayStart...dayEnd,
            proposedStart: newStart,
            proposedEnd: newEnd
        )
        
        // 4. Categorize overlaps
        for other in overlaps {
            let otherEnd = other.endTime ?? Date()
            
            // Check if this edit would completely overwrite the other block
            if newStart <= other.startTime && newEnd >= otherEnd {
                // Find ALL blocks that would be overwritten
                let victims = overlaps.filter { victim in
                    let victimEnd = victim.endTime ?? Date()
                    return newStart <= victim.startTime && newEnd >= victimEnd
                }
                if !victims.isEmpty {
                    conflicts.append(.completeOverwrite(victims: victims))
                }
                break // Don't double-count
            } else {
                // Partial overlap
                let overlapStart = max(newStart, other.startTime)
                let overlapEnd = min(newEnd, otherEnd)
                let overlapMinutes = Int(overlapEnd.timeIntervalSince(overlapStart) / 60)
                
                if overlapMinutes > 0 {
                    conflicts.append(.overlap(with: other, overlapMinutes: overlapMinutes))
                }
            }
        }
        
        // Remove duplicate overwrites
        let uniqueConflicts = deduplicateConflicts(conflicts)
        
        let hasBlocking = uniqueConflicts.contains { $0.severity == .blocking }
        let canProceed = !hasBlocking
        
        return ValidationResult(
            isValid: uniqueConflicts.isEmpty,
            conflicts: uniqueConflicts,
            canProceedWithConfirmation: canProceed
        )
    }
    
    // MARK: - Gap Detection
    
    /// Find all gaps in a given date range
    func findGaps(for date: Date) -> [TimeBlock] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime >= dayStart &&
                block.startTime < dayEnd &&
                block.blockType == "gap"
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Count unresolved gaps for badge display
    func unresolvedGapCount(for date: Date? = nil) -> Int {
        if let date = date {
            return findGaps(for: date).count
        }
        
        // All unresolved gaps
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.blockType == "gap" }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
    
    // MARK: - Helpers
    
    private func findOverlappingBlocks(
        excluding blockID: UUID,
        in dateRange: ClosedRange<Date>,
        proposedStart: Date,
        proposedEnd: Date
    ) -> [TimeBlock] {
        let rangeStart = dateRange.lowerBound
        let rangeEnd = dateRange.upperBound
        
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.id != blockID &&
                block.startTime >= rangeStart &&
                block.startTime < rangeEnd
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        
        guard let blocks = try? modelContext.fetch(descriptor) else { return [] }
        
        // Filter to only those that actually overlap
        return blocks.filter { block in
            let blockEnd = block.endTime ?? Date()
            // Overlap exists if: proposedStart < blockEnd AND proposedEnd > blockStart
            return proposedStart < blockEnd && proposedEnd > block.startTime
        }
    }
    
    private func deduplicateConflicts(_ conflicts: [TimeConflict]) -> [TimeConflict] {
        var seen = Set<String>()
        return conflicts.filter { conflict in
            if seen.contains(conflict.id) {
                return false
            }
            seen.insert(conflict.id)
            return true
        }
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
    
    /// Generate suggested resolutions for conflicts
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
                // Suggest: Trim this block to fit before the other
                resolutions.append(Resolution(
                    title: "End at \(other.startTime.formatted(date: .omitted, time: .shortened))",
                    description: "Adjust end time to avoid overlap",
                    action: {
                        // Caller handles the actual edit
                    }
                ))
                
                // Suggest: Trim this block to fit after the other
                if let otherEnd = other.endTime {
                    resolutions.append(Resolution(
                        title: "Start at \(otherEnd.formatted(date: .omitted, time: .shortened))",
                        description: "Adjust start time to avoid overlap",
                        action: {}
                    ))
                }
                
            case .completeOverwrite(let victims):
                resolutions.append(Resolution(
                    title: "Delete \(victims.count) block(s) and proceed",
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

