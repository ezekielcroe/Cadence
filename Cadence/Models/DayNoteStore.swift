//
//  DayNoteStore.swift
//  Cadence
//
//  Every write to a day's intention or reflection goes through here, so:
//    • the text lands on the day the user was looking at (not "today"),
//    • a day never ends up with two DayNotes,
//    • clearing the text actually clears it.
//

import Foundation
import SwiftData

@MainActor
enum DayNoteStore {

    /// The note for the calendar day containing `date`, if one exists.
    /// Range-based rather than equality-based, so a note whose stored date
    /// is not exactly midnight (e.g. written across a time-zone change) is
    /// still found.
    static func note(for date: Date, in context: ModelContext, calendar: Calendar = .current) -> DayNote? {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let descriptor = FetchDescriptor<DayNote>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
            sortBy: [SortDescriptor(\.date)]
        )
        return try? context.fetch(descriptor).first
    }

    /// Sets the intention for the day containing `date`. Text is trimmed.
    /// Empty text clears an existing intention and never creates a note.
    @discardableResult
    static func setIntention(_ text: String, for date: Date, in context: ModelContext,
                             now: Date = Date()) -> DayNote? {
        write(text, to: .intention, for: date, in: context, now: now)
    }

    /// Sets the reflection for the day containing `date`. Same rules as `setIntention`.
    @discardableResult
    static func setReflection(_ text: String, for date: Date, in context: ModelContext,
                              now: Date = Date()) -> DayNote? {
        write(text, to: .reflection, for: date, in: context, now: now)
    }

    // MARK: - Private

    private enum Field { case intention, reflection }

    private static func write(_ text: String, to field: Field, for date: Date,
                              in context: ModelContext, now: Date) -> DayNote? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let note: DayNote
        if let existing = Self.note(for: date, in: context) {
            note = existing
        } else {
            guard !trimmed.isEmpty else { return nil }   // nothing to clear, nothing to create
            note = DayNote(date: date)
            context.insert(note)
        }

        switch field {
        case .intention:
            guard note.intention != trimmed else { return note }
            note.intention          = trimmed
            note.intentionUpdatedAt = trimmed.isEmpty ? nil : now
        case .reflection:
            guard note.reflection != trimmed else { return note }
            note.reflection          = trimmed
            note.reflectionUpdatedAt = trimmed.isEmpty ? nil : now
        }

        try? context.save()
        return note
    }
}
