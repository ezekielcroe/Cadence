//
//  TimeBlockEditor.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 30/1/26.
//


import Foundation
import SwiftData

@MainActor
class TimeBlockEditor {
    private var modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Validation
    
    func areAdjacent(_ block1: TimeBlock, _ block2: TimeBlock) -> Bool {
        guard let end1 = block1.endTime else { return false }
        let timeDiff = abs(end1.timeIntervalSince(block2.startTime))
        return timeDiff < 1.0
    }
    
    func canMerge(_ blocks: [TimeBlock]) -> Bool {
        guard blocks.count >= 2 else { return false }
        
        let sorted = blocks.sorted { $0.startTime < $1.startTime }
        
        for i in 0..<(sorted.count - 1) {
            if !areAdjacent(sorted[i], sorted[i + 1]) {
                return false
            }
        }
        
        let hasGapOrPause = sorted.contains { $0.isGap || $0.isPauseBlock }
        let allSameActivity = Set(sorted.compactMap { $0.activityID }).count <= 1
        
        return hasGapOrPause || allSameActivity
    }
    
    func canSplit(_ block: TimeBlock) -> Bool {
        guard let endTime = block.endTime else { return false }
        let duration = endTime.timeIntervalSince(block.startTime)
        return duration >= 120
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
        
        let mergedBlock: TimeBlock
        if let activity = targetActivity {
            mergedBlock = TimeBlock(activity: activity, startTime: firstBlock.startTime)
        } else {
            mergedBlock = TimeBlock.createGap(startTime: firstBlock.startTime)
        }
        
        mergedBlock.endTime = endTime
        mergedBlock.stopState = lastBlock.stopState
        
        let allRemarks = sorted.compactMap { $0.remarks.isEmpty ? nil : $0.remarks }
        mergedBlock.remarks = allRemarks.joined(separator: "\n---\n")
        
        mergedBlock.totalPauseDuration = sorted.reduce(0) { $0 + $1.totalPauseDuration }
        mergedBlock.switchCount = sorted.reduce(0) { $0 + $1.switchCount }
        
        for block in sorted {
            modelContext.delete(block)
        }
        
        modelContext.insert(mergedBlock)
        try modelContext.save()
    }
    
    // MARK: - Split
    
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
        
        let secondBlock = TimeBlock.createGap(startTime: splitTime)
        secondBlock.endTime = endTime
        secondBlock.stopState = block.stopState
        secondBlock.remarks = block.remarks
        
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
        
        let previous = currentIndex > 0 ? allBlocks[currentIndex - 1] : nil
        let next = currentIndex < allBlocks.count - 1 ? allBlocks[currentIndex + 1] : nil
        
        return (previous, next)
    }
}

enum TimeBlockEditorError: LocalizedError {
    case cannotMerge, cannotSplit, invalidBlocks, blockStillActive
    case invalidSplitTime, blockTooLong, activityNotFound, notAGap, alreadyGap
    
    var errorDescription: String? {
        switch self {
        case .cannotMerge: return "Cannot merge these blocks."
        case .cannotSplit: return "Cannot split this block."
        case .invalidBlocks: return "Invalid blocks selected."
        case .blockStillActive: return "Cannot split an active block."
        case .invalidSplitTime: return "Invalid split time."
        case .blockTooLong: return "Block too long."
        case .activityNotFound: return "Activity not found."
        case .notAGap: return "Not a Gap or Pause."
        case .alreadyGap: return "Already a Gap."
        }
    }
}