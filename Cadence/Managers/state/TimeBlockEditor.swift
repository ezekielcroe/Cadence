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
        return abs(end1.timeIntervalSince(block2.startTime)) < 1.0
    }

    func canMerge(_ blocks: [TimeBlock]) -> Bool {
        guard blocks.count >= 2 else { return false }
        let sorted = blocks.sorted { $0.startTime < $1.startTime }
        for i in 0 ..< sorted.count - 1 {
            guard sorted[i].endTime != nil else { return false }
            if !areAdjacent(sorted[i], sorted[i + 1]) { return false }
        }
        return sorted.last?.endTime != nil
    }

    func canSplit(_ block: TimeBlock) -> Bool {
        block.endTime != nil
    }

    // MARK: - Merge

    /// Merges adjacent activity blocks into one.
    /// Remarks attached to any of the source blocks are re-pointed to the merged block.
    func mergeBlocks(_ blocks: [TimeBlock], intoActivity targetActivity: Activity?) throws {
        guard canMerge(blocks) else { throw TimeBlockEditorError.cannotMerge }
        guard let activity = targetActivity else { throw TimeBlockEditorError.activityRequired }

        let sorted = blocks.sorted { $0.startTime < $1.startTime }
        guard let lastBlock = sorted.last, let endTime = lastBlock.endTime else {
            throw TimeBlockEditorError.invalidBlocks
        }

        // Build the merged block
        let mergedBlock                    = TimeBlock(activity: activity, startTime: sorted[0].startTime)
        mergedBlock.endTime                = endTime
        mergedBlock.stopState              = lastBlock.stopState
        mergedBlock.totalPauseDuration     = sorted.reduce(0) { $0 + $1.totalPauseDuration }
        mergedBlock.pauseCount             = sorted.reduce(0) { $0 + $1.pauseCount }
        mergedBlock.switchCount            = sorted.reduce(0) { $0 + $1.switchCount }

        // Re-point all Remark records from source blocks to the new merged block
        let sourceIDs = sorted.map { $0.id }
        let remarkDescriptor = FetchDescriptor<Remark>()
        if let allRemarks = try? modelContext.fetch(remarkDescriptor) {
            for remark in allRemarks where sourceIDs.contains(remark.timeBlockID) {
                remark.timeBlockID = mergedBlock.id
            }
        }

        // Delete source blocks and insert merged block
        for block in sorted { modelContext.delete(block) }
        modelContext.insert(mergedBlock)
        try modelContext.save()
    }

    // MARK: - Split

    /// Splits a completed block at `splitTime`. Remarks stay on the first half.
    func splitBlock(_ block: TimeBlock, at splitTime: Date) throws {
        guard canSplit(block) else { throw TimeBlockEditorError.cannotSplit }
        guard let endTime = block.endTime else { throw TimeBlockEditorError.blockStillActive }
        guard splitTime > block.startTime && splitTime < endTime else {
            throw TimeBlockEditorError.invalidSplitTime
        }
        guard let activityID = block.activityID else { throw TimeBlockEditorError.activityNotFound }

        let descriptor = FetchDescriptor<Activity>(predicate: #Predicate { $0.id == activityID })
        guard let activity = try? modelContext.fetch(descriptor).first else {
            throw TimeBlockEditorError.activityNotFound
        }

        let firstBlock       = TimeBlock(activity: activity, startTime: block.startTime)
        firstBlock.endTime   = splitTime
        firstBlock.stopState = "switched"

        let secondBlock       = TimeBlock(activity: activity, startTime: splitTime)
        secondBlock.endTime   = endTime
        secondBlock.stopState = block.stopState

        // Remarks stay on the first half — re-point them
        let remarkDescriptor = FetchDescriptor<Remark>()
        if let allRemarks = try? modelContext.fetch(remarkDescriptor) {
            for remark in allRemarks where remark.timeBlockID == block.id {
                remark.timeBlockID = firstBlock.id
            }
        }

        modelContext.delete(block)
        modelContext.insert(firstBlock)
        modelContext.insert(secondBlock)
        try modelContext.save()
    }

    // MARK: - Adjacency Lookup

    func getAdjacentBlocks(for block: TimeBlock) -> (previous: TimeBlock?, next: TimeBlock?) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: block.startTime)
        let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { b in
                b.startTime >= dayStart && b.startTime < dayEnd && b.activityID != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )

        guard let allBlocks = try? modelContext.fetch(descriptor),
              let idx = allBlocks.firstIndex(where: { $0.id == block.id })
        else { return (nil, nil) }

        let previous: TimeBlock? = idx > 0 && areAdjacent(allBlocks[idx - 1], block)
            ? allBlocks[idx - 1] : nil
        let next: TimeBlock? = idx < allBlocks.count - 1 && areAdjacent(block, allBlocks[idx + 1])
            ? allBlocks[idx + 1] : nil

        return (previous, next)
    }
}

// MARK: - Errors

enum TimeBlockEditorError: LocalizedError {
    case cannotMerge
    case cannotSplit
    case invalidBlocks
    case blockStillActive
    case invalidSplitTime
    case activityNotFound
    case activityRequired

    var errorDescription: String? {
        switch self {
        case .cannotMerge:      return "Cannot merge these blocks. Blocks must be adjacent and all must be completed."
        case .cannotSplit:      return "Cannot split this block. The block must be completed."
        case .invalidBlocks:    return "Invalid blocks selected."
        case .blockStillActive: return "Cannot split an active block."
        case .invalidSplitTime: return "Invalid split time. The split must fall within the block's time range."
        case .activityNotFound: return "The original activity could not be found."
        case .activityRequired: return "An activity must be selected to merge into."
        }
    }
}
