//
//  TimeBlockEditor.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 30/1/26.
//  Updated: Fixed merge/split logic - now allows splitting any activity


import Foundation
import SwiftData

@MainActor
class TimeBlockEditor {
    private var modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Validation
    
    /// Check if two blocks are truly adjacent (end time of first matches start time of second)
    func areAdjacent(_ block1: TimeBlock, _ block2: TimeBlock) -> Bool {
        guard let end1 = block1.endTime else { return false }
        let timeDiff = abs(end1.timeIntervalSince(block2.startTime))
        return timeDiff < 1.0 // Within 1 second tolerance
    }
    
    /// Check if a set of blocks can be merged
    func canMerge(_ blocks: [TimeBlock]) -> Bool {
        guard blocks.count >= 2 else { return false }
        
        let sorted = blocks.sorted { $0.startTime < $1.startTime }
        
        // Check all blocks are adjacent
        for i in 0..<(sorted.count - 1) {
            if !areAdjacent(sorted[i], sorted[i + 1]) {
                return false
            }
        }
        
        return true
    }
    
    /// Check if a block can be split
    func canSplit(_ block: TimeBlock) -> Bool {
        // Can split any completed block
        return block.endTime != nil
    }
    
    // MARK: - Merge
    
    func mergeBlocks(_ blocks: [TimeBlock], intoActivity targetActivity: Activity?) throws {
        guard canMerge(blocks) else {
            throw TimeBlockEditorError.cannotMerge
        }
        
        let sorted = blocks.sorted { $0.startTime < $1.startTime }
        
        guard let firstBlock = sorted.first,
              let lastBlock = sorted.last,
              let endTime = lastBlock.endTime else {
            throw TimeBlockEditorError.invalidBlocks
        }
        
        // Create the merged block
        let mergedBlock: TimeBlock
        if let activity = targetActivity {
            mergedBlock = TimeBlock(activity: activity, startTime: firstBlock.startTime)
        } else {
            mergedBlock = TimeBlock.createGap(startTime: firstBlock.startTime)
        }
        
        mergedBlock.endTime = endTime
        mergedBlock.stopState = lastBlock.stopState
        
        // Concatenate remarks with separator
        let allRemarks = sorted.compactMap { $0.remarks.isEmpty ? nil : $0.remarks }
        mergedBlock.remarks = allRemarks.joined(separator: "\n---\n")
        
        // Sum up pause durations and switch counts
        mergedBlock.totalPauseDuration = sorted.reduce(0) { $0 + $1.totalPauseDuration }
        mergedBlock.switchCount = sorted.reduce(0) { $0 + $1.switchCount }
        
        // Delete original blocks
        for block in sorted {
            modelContext.delete(block)
        }
        
        // Insert merged block
        modelContext.insert(mergedBlock)
        try modelContext.save()
    }
    
    // MARK: - Split
    
    /// Split a block at the given time
    /// - For activities: both parts become the same activity
    /// - For gaps/pauses: both parts remain as gaps/pauses
    func splitBlock(_ block: TimeBlock, at splitTime: Date) throws {
        guard canSplit(block) else {
            throw TimeBlockEditorError.cannotSplit
        }
        
        guard let endTime = block.endTime else {
            throw TimeBlockEditorError.blockStillActive
        }
        
        guard splitTime > block.startTime && splitTime < endTime else {
            throw TimeBlockEditorError.invalidSplitTime
        }
        
        // Create first block (same type as original)
        let firstBlock: TimeBlock
        if let activityID = block.activityID {
            let descriptor = FetchDescriptor<Activity>(
                predicate: #Predicate { $0.id == activityID }
            )
            if let activity = try? modelContext.fetch(descriptor).first {
                firstBlock = TimeBlock(activity: activity, startTime: block.startTime)
            } else {
                throw TimeBlockEditorError.activityNotFound
            }
        } else if block.isGap {
            firstBlock = TimeBlock.createGap(startTime: block.startTime)
        } else {
            firstBlock = TimeBlock.createPause(startTime: block.startTime)
        }
        
        firstBlock.endTime = splitTime
        firstBlock.stopState = "switched"
        firstBlock.remarks = block.remarks
        
        // Create second block (same type as original - NOT a gap anymore)
        let secondBlock: TimeBlock
        if let activityID = block.activityID {
            let descriptor = FetchDescriptor<Activity>(
                predicate: #Predicate { $0.id == activityID }
            )
            if let activity = try? modelContext.fetch(descriptor).first {
                secondBlock = TimeBlock(activity: activity, startTime: splitTime)
            } else {
                throw TimeBlockEditorError.activityNotFound
            }
        } else if block.isGap {
            secondBlock = TimeBlock.createGap(startTime: splitTime)
        } else {
            secondBlock = TimeBlock.createPause(startTime: splitTime)
        }
        
        secondBlock.endTime = endTime
        secondBlock.stopState = block.stopState
        // Don't copy remarks to second block - they stay with first
        
        // Delete original and insert new blocks
        modelContext.delete(block)
        modelContext.insert(firstBlock)
        modelContext.insert(secondBlock)
        
        try modelContext.save()
    }
    
    // MARK: - Convert
    
    func convertToActivity(_ block: TimeBlock, activity: Activity) throws {
        guard block.isGap || block.isPauseBlock else {
            throw TimeBlockEditorError.notAGap
        }
        
        block.activityID = activity.id
        block.activityName = activity.name
        block.activityColor = activity.color
        block.activitySetID = activity.setID
        block.blockType = "activity"
        
        try modelContext.save()
    }
    
    // MARK: - Helpers
    
    func getAdjacentBlocks(for block: TimeBlock) -> (previous: TimeBlock?, next: TimeBlock?) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: block.startTime)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { b in
                b.startTime >= dayStart && b.startTime < dayEnd
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        
        guard let allBlocks = try? modelContext.fetch(descriptor),
              let currentIndex = allBlocks.firstIndex(where: { $0.id == block.id }) else {
            return (nil, nil)
        }
        
        // Check for truly adjacent previous block
        var previous: TimeBlock? = nil
        if currentIndex > 0 {
            let prev = allBlocks[currentIndex - 1]
            if areAdjacent(prev, block) {
                previous = prev
            }
        }
        
        // Check for truly adjacent next block
        var next: TimeBlock? = nil
        if currentIndex < allBlocks.count - 1 {
            let nextBlock = allBlocks[currentIndex + 1]
            if areAdjacent(block, nextBlock) {
                next = nextBlock
            }
        }
        
        return (previous, next)
    }
}

enum TimeBlockEditorError: LocalizedError {
    case cannotMerge, cannotSplit, invalidBlocks, blockStillActive
    case invalidSplitTime, blockTooLong, activityNotFound, notAGap, alreadyGap
    
    var errorDescription: String? {
        switch self {
        case .cannotMerge: return "Cannot merge these blocks. Blocks must be adjacent and at least one must be a gap, pause, or short activity (<5 min)."
        case .cannotSplit: return "Cannot split this block. Block must be completed and at least 2 minutes long."
        case .invalidBlocks: return "Invalid blocks selected."
        case .blockStillActive: return "Cannot split an active block."
        case .invalidSplitTime: return "Invalid split time."
        case .blockTooLong: return "Block is too long to modify."
        case .activityNotFound: return "Activity not found."
        case .notAGap: return "Only gaps and pauses can be converted to activities."
        case .alreadyGap: return "This block is already a gap."
        }
    }
}
