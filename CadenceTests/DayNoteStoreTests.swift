//
//  DayNoteStoreTests.swift
//  CadenceTests
//

import Testing
import Foundation
import SwiftData
@testable import Cadence

@MainActor
struct DayNoteStoreTests {

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try makeInMemoryContainer()
    }

    private func allNotes() throws -> [DayNote] {
        try context.fetch(FetchDescriptor<DayNote>(sortBy: [SortDescriptor(\.date)]))
    }

    @Test func writesToTheDayItWasOpenedFor() throws {
        DayNoteStore.setIntention("Finish the draft", for: day(2026, 3, 10, 15), in: context)

        let notes = try allNotes()
        #expect(notes.count == 1)
        #expect(notes.first?.date == day(2026, 3, 10))
        #expect(notes.first?.intention == "Finish the draft")
    }

    @Test func secondWriteUpdatesTheSameNote() throws {
        DayNoteStore.setIntention("First", for: day(2026, 3, 10, 8), in: context)
        DayNoteStore.setIntention("Second", for: day(2026, 3, 10, 20), in: context)

        let notes = try allNotes()
        #expect(notes.count == 1)
        #expect(notes.first?.intention == "Second")
    }

    @Test func intentionAndReflectionShareOneNote() throws {
        DayNoteStore.setIntention("Plan", for: day(2026, 3, 10, 8), in: context)
        DayNoteStore.setReflection("Went well", for: day(2026, 3, 10, 22), in: context)

        let notes = try allNotes()
        #expect(notes.count == 1)
        #expect(notes.first?.intention == "Plan")
        #expect(notes.first?.reflection == "Went well")
    }

    @Test func differentDaysGetDifferentNotes() throws {
        DayNoteStore.setReflection("Mon", for: day(2026, 3, 9, 21), in: context)
        DayNoteStore.setReflection("Tue", for: day(2026, 3, 10, 21), in: context)

        #expect(try allNotes().map(\.reflection) == ["Mon", "Tue"])
    }

    @Test func trimsWhitespace() throws {
        DayNoteStore.setIntention("  Breathe \n", for: day(2026, 3, 10), in: context)
        #expect(try allNotes().first?.intention == "Breathe")
    }

    @Test func emptyTextDoesNotCreateANote() throws {
        let result = DayNoteStore.setIntention("   ", for: day(2026, 3, 10), in: context)
        #expect(result == nil)
        #expect(try allNotes().isEmpty)
    }

    @Test func emptyTextClearsAnExistingIntention() throws {
        DayNoteStore.setIntention("Plan", for: day(2026, 3, 10, 8), in: context)
        DayNoteStore.setIntention("", for: day(2026, 3, 10, 9), in: context)

        let note = try #require(try allNotes().first)
        #expect(note.intention.isEmpty)
        #expect(note.intentionUpdatedAt == nil)
    }

    @Test func stampsTheWriteTime() throws {
        let writtenAt = day(2026, 3, 10, 21, 45)
        DayNoteStore.setReflection("Done", for: day(2026, 3, 10), in: context, now: writtenAt)

        let note = try #require(try allNotes().first)
        #expect(note.reflectionUpdatedAt == writtenAt)
        #expect(note.intentionUpdatedAt == nil)
    }

    @Test func unchangedTextKeepsTheOriginalTimestamp() throws {
        let first = day(2026, 3, 10, 8)
        DayNoteStore.setIntention("Plan", for: first, in: context, now: first)
        DayNoteStore.setIntention("Plan", for: first, in: context, now: day(2026, 3, 10, 12))

        #expect(try allNotes().first?.intentionUpdatedAt == first)
    }

    @Test func findsTheNoteFromAnyTimeOfDay() throws {
        DayNoteStore.setIntention("Plan", for: day(2026, 3, 10, 0, 1), in: context)
        #expect(DayNoteStore.note(for: day(2026, 3, 10, 23, 59), in: context)?.intention == "Plan")
        #expect(DayNoteStore.note(for: day(2026, 3, 11, 0, 0), in: context) == nil)
    }
}
