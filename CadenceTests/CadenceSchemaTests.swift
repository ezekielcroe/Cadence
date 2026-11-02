//
//  CadenceSchemaTests.swift
//  CadenceTests
//
//  Guards against a model being used in code but missing from the
//  container (DailySummary was missing before Step 0).
//

import Testing
import Foundation
import SwiftData
@testable import Cadence

@MainActor
struct CadenceSchemaTests {

    @Test func everyModelTypeIsInTheSchema() {
        let names = Set(CadenceSchema.schema.entities.map(\.name))
        for expected in ["Activity", "ActivitySet", "TimeBlock", "TimeBlockRule",
                         "Remark", "DayNote", "DailySummary"] {
            #expect(names.contains(expected), "\(expected) is missing from CadenceSchema")
        }
    }

    @Test func inMemoryContainerBuilds() throws {
        let container = try makeInMemoryContainer()
        #expect(try container.mainContext.fetchCount(FetchDescriptor<TimeBlock>()) == 0)
    }

    @Test func savingABlockWritesItsDailySummary() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let block = insertBlock(from: day(2026, 3, 10, 9), to: day(2026, 3, 10, 10), in: context)
        HistoryManager.shared.invalidate(block: block, in: context)
        try context.save()

        let summaries = try context.fetch(FetchDescriptor<DailySummary>())
        #expect(summaries.count == 1)
        #expect(summaries.first?.date == day(2026, 3, 10))
        #expect(summaries.first?.totalDuration == 3600)
    }

    @Test func overnightBlockWritesBothDaysSummaries() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let block = insertBlock(named: "Sleep", from: day(2026, 3, 10, 23), to: day(2026, 3, 11, 7), in: context)
        HistoryManager.shared.invalidate(block: block, in: context)
        try context.save()

        let summaries = try context.fetch(FetchDescriptor<DailySummary>(sortBy: [SortDescriptor(\.date)]))
        #expect(summaries.map(\.date) == [day(2026, 3, 10), day(2026, 3, 11)])
        #expect(summaries.map(\.totalDuration) == [3600, 7 * 3600])
    }
}
