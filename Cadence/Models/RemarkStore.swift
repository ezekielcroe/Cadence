//
//  RemarkStore.swift
//  Cadence
//
//  Every add / edit / delete of a note (Remark) from the editor goes
//  through here, so text is always trimmed and tags always match the text.
//

import Foundation
import SwiftData

@MainActor
enum RemarkStore {

    static func note(withID id: UUID, in context: ModelContext) -> Remark? {
        var descriptor = FetchDescriptor<Remark>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// All notes on a block, oldest first.
    static func notes(forBlock blockID: UUID, in context: ModelContext) -> [Remark] {
        let descriptor = FetchDescriptor<Remark>(
            predicate: #Predicate { $0.timeBlockID == blockID },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Adds a note to a block. Empty text adds nothing and returns nil.
    @discardableResult
    static func addNote(_ text: String, toBlock blockID: UUID, in context: ModelContext,
                        now: Date = Date()) -> Remark? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let remark = Remark(timeBlockID: blockID, text: trimmed, timestamp: now)
        context.insert(remark)
        try? context.save()
        return remark
    }

    /// Replaces a note's text and re-reads its tags. The timestamp (when it
    /// was first written) is kept. Empty text deletes the note and returns nil.
    @discardableResult
    static func updateNote(_ remark: Remark, text: String, in context: ModelContext) -> Remark? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteNote(remark, in: context)
            return nil
        }
        guard remark.text != trimmed else { return remark }
        remark.text = trimmed
        remark.refreshTags()
        try? context.save()
        return remark
    }

    static func deleteNote(_ remark: Remark, in context: ModelContext) {
        context.delete(remark)
        try? context.save()
    }
}
