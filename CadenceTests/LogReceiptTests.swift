//
//  LogReceiptTests.swift
//  CadenceTests
//
//  Step 1: the post-tap receipt — Undo, Change, and the "Last" row.
//
//  Each test gets its own in-memory store and its own UserDefaults suite,
//  so nothing touches the app's real data or settings on the simulator.
//

import Testing
import Foundation
import SwiftData
@testable import Cadence

@MainActor
struct LogReceiptTests {

    let container: ModelContainer
    let defaults: UserDefaults
    var context: ModelContext { container.mainContext }

    let meetings: Activity
    let email: Activity

    init() throws {
        container = try makeInMemoryContainer()
        defaults = UserDefaults(suiteName: "CadenceTests.\(UUID().uuidString)")!

        meetings = Activity(name: "Meetings", color: "#2196F3")
        email    = Activity(name: "Email",    color: "#FF9800")
        container.mainContext.insert(meetings)
        container.mainContext.insert(email)
        try container.mainContext.save()
    }

    /// Builds the manager after the store is seeded, as the app does on launch.
    private func makeManager() -> TimeTrackingManager {
        TimeTrackingManager(modelContext: context, defaults: defaults)
    }

    private func blockCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<TimeBlock>())
    }

    // MARK: - Tap

    @Test func tapLogsTheSpanSinceTheLastEntryAndShowsAReceipt() throws {
        let previousEnd = Date().addingTimeInterval(-5 * 60)
        insertBlock(from: previousEnd.addingTimeInterval(-3600), to: previousEnd, in: context)
        let manager = makeManager()

        manager.handleActivityTap(meetings)

        let receipt = try #require(manager.lastReceipt)
        #expect(receipt.block.activityName == "Meetings")
        #expect(receipt.block.start == previousEnd)
        #expect(receipt.canUndo())
        #expect(manager.lastCompleted?.blockID == receipt.block.blockID)
        #expect(try blockCount() == 2)
    }

    @Test func longSpanConfirmsFirstThenShowsAReceipt() throws {
        let previousEnd = Date().addingTimeInterval(-5 * 3600)   // over the 4h default
        insertBlock(from: previousEnd.addingTimeInterval(-3600), to: previousEnd, in: context)
        let manager = makeManager()

        manager.handleActivityTap(meetings)
        let pending = try #require(manager.pendingLabel)
        #expect(manager.lastReceipt == nil)

        manager.commitPendingLabel(start: pending.suggestedStart)
        #expect(manager.lastReceipt?.block.activityName == "Meetings")
    }

    // MARK: - Undo

    @Test func undoDeletesTheBlockAndRestoresTheAnchor() throws {
        let previousEnd = Date().addingTimeInterval(-5 * 60)
        let previous = insertBlock(from: previousEnd.addingTimeInterval(-3600), to: previousEnd, in: context)
        let manager = makeManager()
        let anchorBefore = manager.retrospectiveAnchor

        manager.handleActivityTap(meetings)
        #expect(manager.retrospectiveAnchor > anchorBefore)

        #expect(manager.undoLastLog())
        #expect(try blockCount() == 1)
        #expect(manager.retrospectiveAnchor == anchorBefore)
        #expect(manager.lastReceipt == nil)
        #expect(manager.lastCompleted?.blockID == previous.id)
    }

    @Test func undoIsRefusedAfterTheWindow() throws {
        insertBlock(from: Date().addingTimeInterval(-3600), to: Date().addingTimeInterval(-300), in: context)
        let manager = makeManager()

        manager.handleActivityTap(meetings)
        let late = Date().addingTimeInterval(LogReceipt.undoWindow + 1)

        #expect(!manager.undoLastLog(now: late))
        #expect(try blockCount() == 2)
    }

    @Test func undoRestoresAnEarlierSkip() throws {
        insertBlock(from: Date().addingTimeInterval(-3600), to: Date().addingTimeInterval(-1800), in: context)
        let skippedAt = Date().addingTimeInterval(-120)
        defaults.set(skippedAt.timeIntervalSince1970, forKey: "retroDiscardMarker")
        let manager = makeManager()

        manager.handleActivityTap(meetings)          // logs skippedAt → now, clears the skip
        let logged = try #require(manager.lastReceipt)
        #expect(abs(logged.block.start.timeIntervalSince(skippedAt)) < 0.01)

        #expect(manager.undoLastLog())
        #expect(abs(manager.retrospectiveAnchor.timeIntervalSince(skippedAt)) < 0.01)
    }

    @Test func undoAlsoDeletesANoteAddedToTheBlock() throws {
        insertBlock(from: Date().addingTimeInterval(-3600), to: Date().addingTimeInterval(-300), in: context)
        let manager = makeManager()

        manager.handleActivityTap(meetings)
        let blockID = try #require(manager.lastReceipt?.block.blockID)
        context.insert(Remark(timeBlockID: blockID, text: "Oops, wrong one"))
        try context.save()

        #expect(manager.undoLastLog())
        #expect(try context.fetchCount(FetchDescriptor<Remark>()) == 0)
    }

    @Test func skipClearsTheReceipt() throws {
        insertBlock(from: Date().addingTimeInterval(-3600), to: Date().addingTimeInterval(-300), in: context)
        let manager = makeManager()

        manager.handleActivityTap(meetings)
        manager.discardUnlabeledTime()

        #expect(manager.lastReceipt == nil)
        #expect(!manager.undoLastLog())
        #expect(try blockCount() == 2)
    }

    // MARK: - Change

    @Test func relabelChangesTheActivityButNotTheTimes() throws {
        insertBlock(from: Date().addingTimeInterval(-3600), to: Date().addingTimeInterval(-300), in: context)
        let manager = makeManager()

        manager.handleActivityTap(meetings)
        let before = try #require(manager.lastReceipt)

        manager.relabelBlock(id: before.block.blockID, to: email)

        let after = try #require(manager.lastReceipt)
        #expect(after.id == before.id)                    // same card, not a new one
        #expect(after.block.activityName == "Email")
        #expect(after.block.start == before.block.start)
        #expect(after.block.end == before.block.end)

        let block = try #require(manager.block(withID: before.block.blockID))
        #expect(block.activityID == email.id)
        #expect(block.activityColor == "#FF9800")
        #expect(manager.lastCompleted?.activityName == "Email")
    }

    // MARK: - "Last" row

    @Test func lastCompletedFollowsADeletionMadeElsewhere() throws {
        let olderEnd = Date().addingTimeInterval(-7200)
        let older = insertBlock(from: olderEnd.addingTimeInterval(-3600), to: olderEnd, in: context)
        let newer = insertBlock(from: Date().addingTimeInterval(-3600), to: Date().addingTimeInterval(-600), in: context)
        let manager = makeManager()
        #expect(manager.lastCompleted?.blockID == newer.id)

        context.delete(newer)                 // e.g. swiped away in Records
        try context.save()
        manager.refreshLastCompleted()        // what the Timer tab does on appear

        #expect(manager.lastCompleted?.blockID == older.id)
        #expect(manager.retrospectiveAnchor == olderEnd)
    }
}
