//
//  BlockDeletionTests.swift
//  CadenceTests
//
//  Step 5: delete an entry and undo it exactly.
//

import Testing
import Foundation
import SwiftData
@testable import Cadence

@MainActor
struct BlockDeletionTests {

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try makeInMemoryContainer()
    }

    private func blockCount() throws -> Int { try context.fetchCount(FetchDescriptor<TimeBlock>()) }
    private func noteCount() throws -> Int { try context.fetchCount(FetchDescriptor<Remark>()) }

    @Test func deleteRemovesTheEntryAndItsNotes() throws {
        let block = insertBlock(from: day(2026, 3, 10, 9), to: day(2026, 3, 10, 10), in: context)
        RemarkStore.addNote("one", toBlock: block.id, in: context)
        RemarkStore.addNote("two", toBlock: block.id, in: context)

        let deleted = BlockDeletion.delete(block, in: context)

        #expect(try blockCount() == 0)
        #expect(try noteCount() == 0)
        #expect(deleted.notes.count == 2)
    }

    @Test func restorePutsEverythingBackWithTheSameIDs() throws {
        let block = insertBlock(named: "Writing", from: day(2026, 3, 10, 9), to: day(2026, 3, 10, 11), in: context)
        block.pauseSpans = [PauseSpan(start: day(2026, 3, 10, 9, 30), end: day(2026, 3, 10, 9, 45))]
        block.pauseCount = 1
        let note = try #require(RemarkStore.addNote("Chapter two #book", toBlock: block.id,
                                                    in: context, now: day(2026, 3, 10, 11, 5)))
        let blockID = block.id, noteID = note.id

        let deleted = BlockDeletion.delete(block, in: context)
        let restored = BlockDeletion.restore(deleted, in: context)

        #expect(restored.id == blockID)
        #expect(restored.activityName == "Writing")
        #expect(restored.startTime == day(2026, 3, 10, 9))
        #expect(restored.endTime == day(2026, 3, 10, 11))
        #expect(restored.pauseSpans.count == 1)
        #expect(restored.duration == 105 * 60)

        let notes = RemarkStore.notes(forBlock: blockID, in: context)
        #expect(notes.map(\.id) == [noteID])
        #expect(notes.first?.text == "Chapter two #book")
        #expect(notes.first?.tags == ["book"])
        #expect(notes.first?.timestamp == day(2026, 3, 10, 11, 5))
    }

    @Test func aRunningTimerIsNeverDeletedFromHere() throws {
        let running = TimeBlock(activityID: UUID(), activityName: "Live", activityColor: "#000000",
                                activitySetID: nil, startTime: Date().addingTimeInterval(-600))
        context.insert(running)
        let done = insertBlock(from: day(2026, 3, 10, 9), to: day(2026, 3, 10, 10), in: context)

        #expect(!BlockDeletion.canDelete(running))
        #expect(BlockDeletion.canDelete(done))

        let deleted = BlockDeletion.delete([running, done], in: context)
        #expect(deleted.count == 1)
        #expect(try blockCount() == 1)
    }
}
