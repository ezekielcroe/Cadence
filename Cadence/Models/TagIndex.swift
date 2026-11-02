//
//  TagIndex.swift
//  Cadence
//
//  Pure helpers for #tags: the filter bars, and suggestions in the editor.
//

import Foundation

enum TagIndex {

    /// Every distinct tag across the given tag lists, sorted A–Z.
    /// Tags are already lowercased by `Remark.extractTags`.
    static func uniqueSorted<S: Sequence>(_ tagLists: S) -> [String] where S.Element == [String] {
        Array(Set(tagLists.joined())).sorted()
    }

    /// Distinct tags, most used first; ties A–Z.
    static func mostUsed<S: Sequence>(_ tagLists: S, limit: Int? = nil) -> [String] where S.Element == [String] {
        var counts: [String: Int] = [:]
        for list in tagLists {
            for tag in list { counts[tag, default: 0] += 1 }
        }
        let ordered = counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map(\.key)
        guard let limit else { return ordered }
        return Array(ordered.prefix(limit))
    }
}

// MARK: - Completion while typing

/// Works on the end of the text, which is where you're typing almost all
/// of the time. (Cursor-aware completion needs iOS 18's TextSelection.)
enum TagCompletion {

    /// The tag being typed at the very end of `text`, without the "#",
    /// lowercased: "lunch with #fam" → "fam", "done #" → "".
    /// nil when the text doesn't end in a tag being typed. A "#" glued to
    /// a word ("email#x") doesn't count.
    static func partialTag(atEndOf text: String) -> String? {
        guard let hashIndex = text.lastIndex(of: "#") else { return nil }
        let typed = text[text.index(after: hashIndex)...]
        guard typed.allSatisfy(isTagCharacter) else { return nil }
        if hashIndex > text.startIndex {
            guard text[text.index(before: hashIndex)].isWhitespace else { return nil }
        }
        return typed.lowercased()
    }

    /// Known tags that start with `partial` (excluding an exact match), in
    /// the order given — pass `TagIndex.mostUsed` for best-first.
    static func suggestions(for partial: String, from tags: [String], limit: Int = 8) -> [String] {
        let prefix = partial.lowercased()
        return Array(tags.filter { $0.hasPrefix(prefix) && $0 != prefix }.prefix(limit))
    }

    /// Finishes the tag being typed with `tag`, or appends `#tag` if none
    /// is being typed. Always leaves a trailing space to keep writing.
    static func complete(_ text: String, with tag: String) -> String {
        if partialTag(atEndOf: text) != nil, let hashIndex = text.lastIndex(of: "#") {
            return String(text[..<hashIndex]) + "#" + tag + " "
        }
        return insertHash(into: text) + tag + " "
    }

    /// Appends "#", adding a space first if the text ends mid-word.
    static func insertHash(into text: String) -> String {
        guard let last = text.last, !last.isWhitespace else { return text + "#" }
        return text + " #"
    }

    private static func isTagCharacter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "-")
    }
}
