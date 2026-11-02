//
//  LiveTimerTests.swift
//  CadenceTests
//
//  Step 2: one tap behaviour. Tap logs; long-press starts a timer; while a
//  timer runs, tap switches it; start/switch can be undone.
//

import Testing
import Foundation
import SwiftData
@testable import Cadence

@MainActor
struct LiveTimerTests {

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

    /// A manager whose unlabeled time started 5 minutes ago.
    private func makeManager() -> TimeTrackingManager {
        let end = Date().addingTimeInterval(-5 * 60)
        insertBlock(named: "Earlier", from: end.addingTimeInterval(-3600), to: end, in: context)
        return TimeTrackingManager(modelContext: context, defaults: defaults)
    }

    private func allBlocks() throws -> [TimeBlock] {
        try context.fetch(FetchDescriptor<TimeBlock>(sortBy: [SortDescriptor(\.startTime)]))
    }

    // MARK: - Start

    @Test func startLiveTimerRunsAndShowsAReceipt() throws {
        let manager = makeManager()

        manager.startLiveTimer(meetings)

        #expect(manager.isTimerRunning)
        #expect(manager.currentTimeBlock?.activityName == "Meetings")
        #expect(manager.currentTimeBlock?.endTime == nil)
        let receipt = try #require(manager.lastTimerReceipt)
        #expect(receipt.replaced == nil)
        #expect(receipt.unlabeledBefore >= 5 * 60 - 1)   // the 5 min left unlabeled
        #expect(manager.lastReceipt == nil)
    }

    @Test func startWithGoalSetsTheTarget() throws {
        let manager = makeManager()
        let goal: TimeInterval = 25 * 60
        manager.startLiveTimer(meetings, targetDuration: goal)

        // Unwrap first, then compare two TimeIntervals. Comparing the
        // optional chain directly against `25 * 60` failed even though both
        // sides printed as 1500.
        let target = try #require(manager.currentTimeBlock?.targetDuration)
        #expect(target == goal)
    }

    // MARK: - Tap while running

    @Test func tapWhileATimerRunsSwitchesIt() throws {
        let manager = makeManager()
        manager.startLiveTimer(meetings)
        let first = try #require(manager.currentTimeBlock)

        manager.handleActivityTap(email)

        #expect(first.endTime != nil)
        #expect(first.stopState == "switched")
        #expect(manager.currentTimeBlock?.activityName == "Email")
        #expect(manager.isTimerRunning)
        #expect(manager.lastTimerReceipt?.replaced?.activityName == "Meetings")
        #expect(manager.lastReceipt == nil)           // no "Logged" card for a switch
    }

    @Test func tapOnTheRunningActivityDoesNothing() throws {
        let manager = makeManager()
        manager.startLiveTimer(meetings)
        let first = try #require(manager.currentTimeBlock)

        manager.handleActivityTap(meetings)

        #expect(manager.currentTimeBlock?.id == first.id)
        #expect(first.endTime == nil)
        #expect(try allBlocks().count == 2)
    }

    @Test func tapOnThePausedRunningActivityResumesIt() throws {
        let manager = makeManager()
        manager.startLiveTimer(meetings)
        manager.handlePauseTap()
        #expect(manager.currentTimeBlock?.isPaused == true)

        manager.handleActivityTap(meetings)

        #expect(manager.currentTimeBlock?.isPaused == false)
    }

    // MARK: - Stop

    @Test func stopGoesBackToLogging() throws {
        let manager = makeManager()
        manager.startLiveTimer(meetings)
        let block = try #require(manager.currentTimeBlock)

        manager.handleStopTap()

        #expect(!manager.isTimerRunning)
        #expect(manager.lastTimerReceipt == nil)
        #expect(manager.retrospectiveAnchor == block.endTime)
        #expect(manager.lastCompleted?.blockID == block.id)
    }

    // MARK: - Undo

    @Test func undoStartFromIdleRemovesTheTimer() throws {
        let manager = makeManager()
        let anchorBefore = manager.retrospectiveAnchor

        manager.startLiveTimer(meetings)
        #expect(manager.undoTimerStart())

        #expect(!manager.isTimerRunning)
        #expect(manager.currentTimeBlock == nil)
        #expect(try allBlocks().map(\.activityName) == ["Earlier"])
        #expect(manager.retrospectiveAnchor == anchorBefore)
    }

    @Test func undoSwitchReopensThePreviousTimer() throws {
        let manager = makeManager()
        manager.startLiveTimer(meetings)
        let first = try #require(manager.currentTimeBlock)

        manager.handleActivityTap(email)
        #expect(manager.undoTimerStart())

        #expect(manager.currentTimeBlock?.id == first.id)
        #expect(first.endTime == nil)
        #expect(first.stopState == "ongoing")
        #expect(manager.isTimerRunning)
        #expect(try allBlocks().map(\.activityName) == ["Earlier", "Meetings"])
    }

    @Test func undoSwitchRestoresAnOpenPause() throws {
        let manager = makeManager()
        manager.startLiveTimer(meetings)
        manager.handlePauseTap()
        let first = try #require(manager.currentTimeBlock)

        manager.handleActivityTap(email)        // the switch closes the pause
        #expect(first.pauseSpans.last?.end != nil)

        #expect(manager.undoTimerStart())
        #expect(first.isPaused)
        #expect(first.pauseSpans.last?.end == nil)
        #expect(first.pauseCount == 1)
    }

    @Test func undoIsRefusedAfterTheWindow() throws {
        let manager = makeManager()
        manager.startLiveTimer(meetings)

        #expect(!manager.undoTimerStart(now: Date().addingTimeInterval(LogReceipt.undoWindow + 1)))
        #expect(manager.isTimerRunning)
    }

    // MARK: - Migration

    @Test func oldStartModeSettingIsRemovedAndTapLogs() throws {
        defaults.set("prospective", forKey: "savedEntryMode")
        let manager = makeManager()
        #expect(defaults.object(forKey: "savedEntryMode") == nil)

        manager.handleActivityTap(meetings)

        #expect(!manager.isTimerRunning)
        #expect(manager.lastReceipt?.block.activityName == "Meetings")
    }

    @Test func aTimerLeftRunningIsPickedUpOnLaunch() throws {
        let running = TimeBlock(activityID: meetings.id, activityName: "Meetings",
                                activityColor: meetings.color, activitySetID: nil,
                                startTime: Date().addingTimeInterval(-600))
        context.insert(running)
        try context.save()

        let manager = makeManager()

        #expect(manager.isTimerRunning)
        #expect(manager.currentTimeBlock?.id == running.id)
    }
}
