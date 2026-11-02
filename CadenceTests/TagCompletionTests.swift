//
//  TagCompletionTests.swift
//  CadenceTests
//
//  Step 3: tag suggestions above the keyboard.
//

import Testing
@testable import Cadence

struct TagCompletionTests {

    // MARK: - What's being typed

    @Test(arguments: [
        ("lunch with #fam", "fam"),
        ("done #", ""),
        ("#Work", "work"),
        ("line one\n#ab", "ab"),
        ("#deep-fo", "deep-fo"),
    ])
    func findsTheTagBeingTyped(text: String, expected: String) {
        #expect(TagCompletion.partialTag(atEndOf: text) == expected)
    }

    @Test(arguments: [
        "no tag here",
        "#work done",        // the tag is finished, not at the end
        "email#x",           // glued to a word
        "",
        "costs #£5",         // not a tag character
    ])
    func ignoresTextThatIsNotTypingATag(text: String) {
        #expect(TagCompletion.partialTag(atEndOf: text) == nil)
    }

    // MARK: - Suggestions

    @Test func suggestsKnownTagsWithThePrefixInTheGivenOrder() {
        let known = ["family", "focus", "fam-dinner", "work"]
        #expect(TagCompletion.suggestions(for: "fa", from: known) == ["family", "fam-dinner"])
    }

    @Test func doesNotSuggestTheTagAlreadyTypedInFull() {
        #expect(TagCompletion.suggestions(for: "work", from: ["work", "workout"]) == ["workout"])
    }

    @Test func emptyPrefixSuggestsEverythingUpToTheLimit() {
        let known = (1...20).map { "t\($0)" }
        #expect(TagCompletion.suggestions(for: "", from: known, limit: 3) == ["t1", "t2", "t3"])
    }

    // MARK: - Completing

    @Test(arguments: [
        ("lunch with #fa", "family", "lunch with #family "),
        ("lunch", "family", "lunch #family "),
        ("lunch ", "family", "lunch #family "),
        ("", "family", "#family "),
        ("done #", "work", "done #work "),
    ])
    func completesOrAppendsTheTag(text: String, tag: String, expected: String) {
        #expect(TagCompletion.complete(text, with: tag) == expected)
    }

    @Test(arguments: [
        ("hello", "hello #"),
        ("hello ", "hello #"),
        ("", "#"),
        ("line\n", "line\n#"),
    ])
    func insertsAHashWithSpacing(text: String, expected: String) {
        #expect(TagCompletion.insertHash(into: text) == expected)
    }

    // MARK: - Most used

    @Test func mostUsedOrdersByCountThenName() {
        let lists = [["work", "health"], ["health"], ["admin"], ["health", "work"]]
        #expect(TagIndex.mostUsed(lists) == ["health", "work", "admin"])
    }

    @Test func mostUsedRespectsTheLimit() {
        let lists = [["b"], ["a"], ["c"], ["a"]]
        #expect(TagIndex.mostUsed(lists, limit: 2) == ["a", "b"])
    }
}
