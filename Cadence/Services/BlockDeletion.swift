//
//  BlockDeletion.swift
//  Cadence
//
//  Deleting an entry (a block and its notes) in a way that can be undone
//  exactly: the restored block and notes keep their original IDs, times,
//  pauses and text. Used by the Journal and the entry page.
//
//  Running blocks (a live timer) are never deleted from here; the Today
//  tab owns them.
//

import Foundation
import SwiftData

/// Everything needed to put a deleted entry back.
struct DeletedBlock: Identifiable {
    struct Note {
        let id: UUID
        let text: String
        let timestamp: Date
    }

    let id = UUID()
    let blockID: UUID
    let activityID: UUID?
    let activityName: String
    let activityColor: String
    let activitySetID: UUID?
    let targetDuration: TimeInterval?
    let startTime: Date
    let endTime: Date?
    let pauseCount: Int
    let totalPauseDuration: TimeInterval
    let pauseSpans: [PauseSpan]
    let stopState: String
    let switchCount: Int
    let notes: [Note]
}

@MainActor
enum BlockDeletion {

    /// Whether this block may be deleted outside the Today tab.
    static func canDelete(_ block: TimeBlock) -> Bool {
        block.endTime != nil
    }

    /// Deletes the block and its notes. Returns what's needed to undo.
    @discardableResult
    static func delete(_ block: TimeBlock, in context: ModelContext) -> DeletedBlock {
        let notes = RemarkStore.notes(forBlock: block.id, in: context)
        let snapshot = DeletedBlock(
            blockID: block.id,
            activityID: block.activityID,
            activityName: block.activityName,
            activityColor: block.activityColor,
            activitySetID: block.activitySetID,
            targetDuration: block.targetDuration,
            startTime: block.startTime,
            endTime: block.endTime,
            pauseCount: block.pauseCount,
            totalPauseDuration: block.totalPauseDuration,
            pauseSpans: block.pauseSpans,
            stopState: block.stopState,
            switchCount: block.switchCount,
            notes: notes.map { DeletedBlock.Note(id: $0.id, text: $0.text, timestamp: $0.timestamp) }
        )

        for note in notes { context.delete(note) }
        context.delete(block)
        try? context.save()
        HistoryManager.shared.invalidate(from: snapshot.startTime, to: snapshot.endTime ?? Date(), in: context)
        return snapshot
    }

    /// Deletes several blocks (e.g. a Ledger selection). Running ones are skipped.
    @discardableResult
    static func delete(_ blocks: [TimeBlock], in context: ModelContext) -> [DeletedBlock] {
        blocks.filter(canDelete).map { delete($0, in: context) }
    }

    /// Puts a deleted entry back exactly as it was.
    @discardableResult
    static func restore(_ deleted: DeletedBlock, in context: ModelContext) -> TimeBlock {
        let block = TimeBlock(activityID: deleted.activityID, activityName: deleted.activityName,
                              activityColor: deleted.activityColor, activitySetID: deleted.activitySetID,
                              startTime: deleted.startTime, targetDuration: deleted.targetDuration)
        block.id                 = deleted.blockID
        block.endTime            = deleted.endTime
        block.pauseCount         = deleted.pauseCount
        block.totalPauseDuration = deleted.totalPauseDuration
        block.pauseSpans         = deleted.pauseSpans
        block.stopState          = deleted.stopState
        block.switchCount        = deleted.switchCount
        context.insert(block)

        for note in deleted.notes {
            let remark = Remark(timeBlockID: deleted.blockID, text: note.text, timestamp: note.timestamp)
            remark.id = note.id
            context.insert(remark)
        }

        try? context.save()
        HistoryManager.shared.invalidate(from: deleted.startTime, to: deleted.endTime ?? Date(), in: context)
        return block
    }
}
