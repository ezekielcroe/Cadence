//
//  JournalEditorTests.swift
//  CadenceTests
//
//  Step 3: draft keeping and editor targets.
//

import Testing
import Foundation
@testable import Cadence

struct EditorDraftStoreTests {

    let store = EditorDraftStore(defaults: UserDefaults(suiteName: "CadenceTests.\(UUID().uuidString)")!)

    @Test func savesAndRestoresADraft() {
        store.save("Half a thought", for: "note.x")
        #expect(store.draft(for: "note.x") == "Half a thought")
    }

    @Test func clearRemovesTheDraft() {
        store.save("Half a thought", for: "note.x")
        store.clear(for: "note.x")
        #expect(store.draft(for: "note.x") == nil)
    }

    @Test func savingEmptyRemovesTheDraft() {
        store.save("Half a thought", for: "note.x")
        store.save("", for: "note.x")
        #expect(store.draft(for: "note.x") == nil)
    }

    @Test func draftsAreKeptPerTarget() {
        store.save("one", for: "a")
        store.save("two", for: "b")
        #expect(store.draft(for: "a") == "one")
        #expect(store.draft(for: "b") == "two")
    }
}

struct JournalEditorTargetTests {

    @Test func sameDayGivesTheSameKeyAtAnyTime() {
        let morning = JournalEditorTarget.intention(day: day(2026, 3, 10, 7))
        let night   = JournalEditorTarget.intention(day: day(2026, 3, 10, 23, 59))
        #expect(morning.draftKey == night.draftKey)
        #expect(morning.draftKey == "intention.2026-03-10")
    }

    @Test func differentDaysAndKindsGetDifferentKeys() {
        let keys: Set<String> = [
            JournalEditorTarget.intention(day: day(2026, 3, 10)).draftKey,
            JournalEditorTarget.intention(day: day(2026, 3, 11)).draftKey,
            JournalEditorTarget.reflection(day: day(2026, 3, 10)).draftKey,
        ]
        #expect(keys.count == 3)
    }

    @Test func newNoteAndEditNoteNeverShareAKey() {
        let id = UUID()
        #expect(JournalEditorTarget.newNote(blockID: id).draftKey
                != JournalEditorTarget.editNote(remarkID: id).draftKey)
    }
}
