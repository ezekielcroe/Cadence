//
//  RemarkStoreTests.swift
//  CadenceTests
//
//  Step 3: adding, editing and deleting notes from the editor.
//

import Testing
import Foundation
import SwiftData
@testable import Cadence

@MainActor
struct RemarkStoreTests {

    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let blockID = UUID()

    init() throws {
        container = try makeInMemoryContainer()
    }

    private func allNotes() throws -> [Remark] {
        try context.fetch(FetchDescriptor<Remark>(sortBy: [SortDescriptor(\.timestamp)]))
    }

    // MARK: - Add

    @Test func addTrimsAndReadsTags() throws {
        let note = try #require(RemarkStore.addNote("  Good call with #Design team \n", toBlock: blockID, in: context))
        #expect(note.text == "Good call with #Design team")
        #expect(note.tags == ["design"])
        #expect(note.timeBlockID == blockID)
        #expect(try allNotes().count == 1)
    }

    @Test func addEmptyAddsNothing() throws {
        #expect(RemarkStore.addNote("  \n ", toBlock: blockID, in: context) == nil)
        #expect(try allNotes().isEmpty)
    }

    @Test func addUsesTheGivenTime() throws {
        let writtenAt = day(2026, 3, 10, 14, 5)
        let note = try #require(RemarkStore.addNote("x", toBlock: blockID, in: context, now: writtenAt))
        #expect(note.timestamp == writtenAt)
    }

    // MARK: - Edit

    @Test func updateChangesTextAndTagsButKeepsTheTime() throws {
        let writtenAt = day(2026, 3, 10, 9)
        let note = try #require(RemarkStore.addNote("Draft #wip", toBlock: blockID, in: context, now: writtenAt))

        RemarkStore.updateNote(note, text: "Final version #done #shipped", in: context)

        #expect(note.text == "Final version #done #shipped")
        #expect(note.tags == ["done", "shipped"])
        #expect(note.timestamp == writtenAt)
        #expect(try allNotes().count == 1)
    }

    @Test func updateToEmptyDeletesTheNote() throws {
        let note = try #require(RemarkStore.addNote("Oops", toBlock: blockID, in: context))
        #expect(RemarkStore.updateNote(note, text: "   ", in: context) == nil)
        #expect(try allNotes().isEmpty)
    }

    @Test func deleteRemovesTheNote() throws {
        let note = try #require(RemarkStore.addNote("Gone soon", toBlock: blockID, in: context))
        RemarkStore.deleteNote(note, in: context)
        #expect(try allNotes().isEmpty)
    }

    // MARK: - Lookup

    @Test func notesForABlockAreOldestFirstAndOnlyThatBlock() throws {
        RemarkStore.addNote("second", toBlock: blockID, in: context, now: day(2026, 3, 10, 11))
        RemarkStore.addNote("first",  toBlock: blockID, in: context, now: day(2026, 3, 10, 10))
        RemarkStore.addNote("other",  toBlock: UUID(),  in: context, now: day(2026, 3, 10, 9))

        #expect(RemarkStore.notes(forBlock: blockID, in: context).map(\.text) == ["first", "second"])
    }

    @Test func findsANoteByID() throws {
        let note = try #require(RemarkStore.addNote("find me", toBlock: blockID, in: context))
        #expect(RemarkStore.note(withID: note.id, in: context)?.text == "find me")
        #expect(RemarkStore.note(withID: UUID(), in: context) == nil)
    }
}
