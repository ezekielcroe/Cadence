//
//  DayPageTests.swift
//  CadenceTests
//
//  Steps 4–5: how a day becomes a page (Today, Journal Diary and Ledger).
//

import Testing
import Foundation
import SwiftData
@testable import Cadence

@MainActor
struct DayPageTests {

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    /// Full-day window, so tests don't depend on the simulator's settings.
    let allDay = TrackingWindow(isEnabled: false, startMinutes: 0, endMinutes: 0, weekdays: [])
    let tuesday = day(2026, 3, 10)
    let noon = day(2026, 3, 10, 12)

    init() throws {
        container = try makeInMemoryContainer()
    }

    /// 09:00–10:00 Meetings, 10:30–11:00 Email; viewed at noon.
    private func seedMorning() -> (meetings: TimeBlock, email: TimeBlock) {
        let meetings = insertBlock(named: "Meetings", from: day(2026, 3, 10, 9), to: day(2026, 3, 10, 10), in: context)
        let email = insertBlock(named: "Email", from: day(2026, 3, 10, 10, 30), to: day(2026, 3, 10, 11), in: context)
        return (meetings, email)
    }

    private func page(_ blocks: [TimeBlock], notes: [Remark] = [],
                      options: DayPageBuilder.Options = .init()) -> DayPage {
        DayPageBuilder.make(for: tuesday, blocks: blocks, remarks: notes,
                            now: noon, window: allDay, options: options)
    }

    private func describe(_ page: DayPage) -> [String] {
        page.items.map {
            switch $0 {
            case .entry(let entry): return entry.block.activityName
            case .gap(let gap):     return "gap \(Int(gap.duration / 60))m"
            }
        }
    }

    // MARK: - Order

    @Test func readsTopToBottomWithBlankTimeBetween() {
        let (meetings, email) = seedMorning()
        let page = page([email, meetings])   // order given doesn't matter

        #expect(describe(page) == ["gap 540m", "Meetings", "gap 30m", "Email", "gap 60m"])
        #expect(page.trackedDuration == 90 * 60)
        #expect(page.gapCount == 3)
    }

    @Test func shortBlankTimeIsLeftOut() {
        let (meetings, email) = seedMorning()
        var options = DayPageBuilder.Options()
        options.minimumGap = 45 * 60
        #expect(describe(page([meetings, email], options: options)) == ["gap 540m", "Meetings", "Email", "gap 60m"])
    }

    @Test func theLiveStretchUpToNowCanBeDropped() {
        let (meetings, email) = seedMorning()
        var options = DayPageBuilder.Options()
        options.dropTrailingGap = true
        let page = page([meetings, email], options: options)

        #expect(describe(page) == ["gap 540m", "Meetings", "gap 30m", "Email"])
        #expect(page.gapCount == 2)
    }

    @Test func aRunningTimerCanBeLeftOut() {
        let (meetings, _) = seedMorning()
        let running = TimeBlock(activityID: UUID(), activityName: "Writing", activityColor: "#000000",
                                activitySetID: nil, startTime: day(2026, 3, 10, 11, 30))
        context.insert(running)

        var options = DayPageBuilder.Options()
        options.includeRunning = false
        options.includeGaps = false
        #expect(describe(page([meetings, running], options: options)) == ["Meetings"])
    }

    // MARK: - Notes

    @Test func notesAreAttachedOldestFirst() throws {
        let (meetings, email) = seedMorning()
        let later   = try #require(RemarkStore.addNote("second", toBlock: meetings.id, in: context, now: day(2026, 3, 10, 11)))
        let earlier = try #require(RemarkStore.addNote("first",  toBlock: meetings.id, in: context, now: day(2026, 3, 10, 10)))
        let other   = try #require(RemarkStore.addNote("elsewhere", toBlock: UUID(), in: context))

        let page = page([meetings, email], notes: [later, other, earlier])

        let entry = try #require(page.entries.first { $0.block.id == meetings.id })
        #expect(entry.notes.map(\.text) == ["first", "second"])
        #expect(page.noteCount == 2)
    }

    // MARK: - Filters

    @Test func activityFilterShowsOnlyThatActivityAndNoBlankTime() {
        let (meetings, email) = seedMorning()
        var options = DayPageBuilder.Options()
        options.activityName = "Email"
        #expect(describe(page([meetings, email], options: options)) == ["Email"])
    }

    @Test func tagFilterShowsOnlyEntriesWithATaggedNote() throws {
        let (meetings, email) = seedMorning()
        let note = try #require(RemarkStore.addNote("Deep work #focus", toBlock: meetings.id, in: context))
        var options = DayPageBuilder.Options()
        options.tag = "focus"
        #expect(describe(page([meetings, email], notes: [note], options: options)) == ["Meetings"])
    }

    // MARK: - Across midnight

    @Test func anOvernightEntryShowsOnTheMorningAsAContinuation() throws {
        let sleep = insertBlock(named: "Sleep", from: day(2026, 3, 9, 23), to: day(2026, 3, 10, 7), in: context)
        var options = DayPageBuilder.Options()
        options.includeGaps = false

        let entry = try #require(page([sleep], options: options).entries.first)
        #expect(entry.startsBeforeDay)
        #expect(!entry.endsAfterDay)
        #expect(entry.clip.start == tuesday)
        #expect(entry.duration == 7 * 3600)
    }
}

// MARK: - Day summary line

struct DaySummaryTextTests {

    @Test func nothingToSay() {
        #expect(DaySummaryText.make(tracked: 0, activityDurations: [:], noteCount: 0) == nil)
    }

    @Test func namesTheTopTwoWhenTheSecondIsSubstantial() {
        let text = DaySummaryText.make(
            tracked: 6 * 3600 + 20 * 60,
            activityDurations: ["Meetings": 4 * 3600, "Focused Work": 2 * 3600 + 20 * 60],
            noteCount: 3
        )
        #expect(text == "6h 20m logged · mostly Meetings and Focused Work · 3 notes")
    }

    @Test func namesOnlyTheTopWhenTheRestIsSmall() {
        let text = DaySummaryText.make(
            tracked: 5 * 3600,
            activityDurations: ["Meetings": 4 * 3600 + 30 * 60, "Email": 30 * 60],
            noteCount: 0
        )
        #expect(text == "5h 0m logged · mostly Meetings")
    }

    @Test func oneActivityIsAllOfIt() {
        let text = DaySummaryText.make(tracked: 3600, activityDurations: ["Sleep": 3600], noteCount: 1)
        #expect(text == "1h 0m logged · all Sleep · 1 note")
    }

    @Test func notesAloneStillGetALine() {
        #expect(DaySummaryText.make(tracked: 0, activityDurations: [:], noteCount: 2) == "2 notes")
    }

    @Test func tiesAreBrokenAlphabetically() {
        let text = DaySummaryText.make(tracked: 2 * 3600,
                                       activityDurations: ["Reading": 3600, "Cooking": 3600],
                                       noteCount: 0)
        #expect(text == "2h 0m logged · mostly Cooking and Reading")
    }
}

// MARK: - Which days get a page

@MainActor
struct JournalDaysTests {

    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let march = (start: day(2026, 3, 1), end: day(2026, 4, 1))
    let later = day(2026, 6, 1)   // "now", outside March

    init() throws {
        container = try makeInMemoryContainer()
    }

    @Test func everyDayAnEntryTouchesNewestFirst() {
        let sleep = insertBlock(named: "Sleep", from: day(2026, 3, 9, 23), to: day(2026, 3, 10, 7), in: context)
        let lunch = insertBlock(named: "Lunch", from: day(2026, 3, 12, 12), to: day(2026, 3, 12, 13), in: context)

        let days = JournalDays.days(blocks: [lunch, sleep], noteDays: [], from: march.start, to: march.end, now: later)
        #expect(days == [day(2026, 3, 12), day(2026, 3, 10), day(2026, 3, 9)])
    }

    @Test func anEntryEndingAtMidnightDoesNotAddTheNextDay() {
        let evening = insertBlock(named: "TV", from: day(2026, 3, 9, 21), to: day(2026, 3, 10), in: context)
        let days = JournalDays.days(blocks: [evening], noteDays: [], from: march.start, to: march.end, now: later)
        #expect(days == [day(2026, 3, 9)])
    }

    @Test func daysWithOnlyAnIntentionOrReflectionCount() {
        let days = JournalDays.days(blocks: [], noteDays: [day(2026, 3, 5)], from: march.start, to: march.end, now: later)
        #expect(days == [day(2026, 3, 5)])
    }

    @Test func todayIsIncludedWhenInRange() {
        let days = JournalDays.days(blocks: [], noteDays: [], from: march.start, to: march.end,
                                    now: day(2026, 3, 20, 15))
        #expect(days == [day(2026, 3, 20)])
    }

    @Test func entriesOutsideTheMonthAreIgnored() {
        let feb = insertBlock(named: "Old", from: day(2026, 2, 27, 9), to: day(2026, 2, 27, 10), in: context)
        let days = JournalDays.days(blocks: [feb], noteDays: [day(2026, 4, 2)], from: march.start, to: march.end, now: later)
        #expect(days.isEmpty)
    }
}
