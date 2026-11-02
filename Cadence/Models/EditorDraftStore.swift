//
//  EditorDraftStore.swift
//  Cadence
//
//  Keeps what you're typing in the journal editor until you save or
//  discard it, so nothing is lost if the app is closed mid-sentence.
//  One draft per editor target (see JournalEditorTarget.draftKey).
//

import Foundation

struct EditorDraftStore {

    private static let prefix = "editorDraft."

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func draft(for key: String) -> String? {
        defaults.string(forKey: Self.prefix + key)
    }

    /// Saving empty text removes the draft.
    func save(_ text: String, for key: String) {
        if text.isEmpty {
            clear(for: key)
        } else {
            defaults.set(text, forKey: Self.prefix + key)
        }
    }

    func clear(for key: String) {
        defaults.removeObject(forKey: Self.prefix + key)
    }
}
