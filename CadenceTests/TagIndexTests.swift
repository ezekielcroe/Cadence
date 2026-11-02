//
//  TagIndexTests.swift
//  CadenceTests
//

import Testing
@testable import Cadence

struct TagIndexTests {

    @Test func extractsLowercasedTags() {
        #expect(Remark.extractTags(from: "Shipped it #Work #deep-focus") == ["work", "deep-focus"])
    }

    @Test func ignoresTextWithoutTags() {
        #expect(Remark.extractTags(from: "No tags here, just # a hash").isEmpty)
    }

    @Test func uniqueSortedMergesAndSorts() {
        let lists = [["work", "health"], ["health"], [], ["admin", "work"]]
        #expect(TagIndex.uniqueSorted(lists) == ["admin", "health", "work"])
    }

    @Test func uniqueSortedOfNothingIsEmpty() {
        #expect(TagIndex.uniqueSorted([[String]]()).isEmpty)
    }
}
