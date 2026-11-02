//
//  TestSupport.swift
//  CadenceTests
//

import Foundation
import SwiftData
@testable import Cadence

/// A local-time date, e.g. `day(2026, 3, 10, 9, 30)`.
func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(
        year: year, month: month, day: dayOfMonth, hour: hour, minute: minute
    ))!
}

/// A fresh, empty in-memory store built from the app's real schema.
/// Keep the returned container alive for as long as you use its context.
@MainActor
func makeInMemoryContainer() throws -> ModelContainer {
    try CadenceSchema.makeContainer(inMemory: true)
}

/// Inserts a finished block for a throwaway activity.
@MainActor
@discardableResult
func insertBlock(named name: String = "Focused Work",
                 from start: Date, to end: Date,
                 in context: ModelContext) -> TimeBlock {
    let block = TimeBlock(activityID: UUID(), activityName: name, activityColor: "#4CAF50",
                          activitySetID: nil, startTime: start)
    block.endTime = end
    block.stopState = "stopped"
    context.insert(block)
    try? context.save()
    return block
}
