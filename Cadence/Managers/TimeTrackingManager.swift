// TimeTrackingManager.swift
// Cadence
//
// STEP 2: there is no entry mode any more. A tap labels the time since
// the last entry; a live timer is started deliberately (long-press menu)
// and, while one runs, a tap switches it. `isTimerRunning` is the only
// state, and it is visible on screen.
//
// FULL REWRITE. What changed and why:
//
// - Retrospective ("Log") is the default mode. The anchor is DERIVED:
//   end of the last completed block, raised by a discard marker if the
//   user discarded, raised to the tracking-window floor if a window is
//   enabled. Nothing about the anchor needs persisting or recovering —
//   it cannot be forgotten, and no retrospective state lives in
//   UserDefaults anymore (old keys are cleaned up once on launch).
//
// - Long unlabeled spans (default >= 4h) route through `pendingLabel`
//   so the UI can confirm/adjust the start before committing.
//
// - Background auto-stop is GONE. A prospective block's startTime is
//   persisted; it can run for days with the app killed. A forgotten
//   timer is handled on return by the user editing the block — the gap
//   system already exists for exactly this. The 15-minute pause timeout
//   is gone for the same reason.
//
// - Pauses are recorded as PauseSpans via block.beginPause/endPause.
//
// - The 1s timer no longer fires objectWillChange (the view's own timer
//   drives UI refresh); it only checks target completion, and set rules
//   every 30 ticks.
//
// - saveAndInvalidate(block:) invalidates EVERY day the block overlaps.

import Foundation
import SwiftData
import Combine
import UIKit
import UserNotifications
import AudioToolbox
import AVFoundation

// MARK: - PendingLabel

/// A retrospective label awaiting user confirmation because the span is long.
struct PendingLabel: Identifiable {
    let id = UUID()
    let activity: Activity
    let suggestedStart: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(suggestedStart) }
}

// MARK: - LoggedBlockSnapshot

/// A value copy of a finished block, safe to hold in published state:
/// if the block is deleted elsewhere (e.g. Records), the snapshot stays
/// valid where a model reference would not.
struct LoggedBlockSnapshot: Equatable {
    let blockID:       UUID
    let activityID:    UUID?
    let activityName:  String
    let activityColor: String
    let start:         Date
    let end:           Date
    let duration:      TimeInterval

    init?(_ block: TimeBlock) {
        guard let end = block.endTime else { return nil }
        self.blockID       = block.id
        self.activityID    = block.activityID
        self.activityName  = block.activityName
        self.activityColor = block.activityColor
        self.start         = block.startTime
        self.end           = end
        self.duration      = block.duration
    }
}

// MARK: - LogReceipt

/// What the post-tap card shows: the block just logged, plus what's needed
/// to undo it exactly.
struct LogReceipt: Identifiable, Equatable {
    /// How long Undo stays available after a tap.
    static let undoWindow: TimeInterval = 10

    let id = UUID()
    var block: LoggedBlockSnapshot
    let loggedAt: Date
    /// The skip marker that committing this block cleared; undo puts it back.
    let previousDiscardMarker: Date?

    var undoDeadline: Date { loggedAt.addingTimeInterval(Self.undoWindow) }

    func canUndo(at now: Date = Date()) -> Bool { now < undoDeadline }
}

// MARK: - TimerReceipt

/// What the post-start card shows after a live timer is started or
/// switched, plus what's needed to undo it exactly.
struct TimerReceipt: Identifiable, Equatable {

    /// The timer this start switched away from, if one was running.
    struct ReplacedTimer: Equatable {
        let blockID:      UUID
        let activityName: String
        let wasPaused:    Bool
    }

    let id = UUID()
    let blockID:       UUID
    let activityName:  String
    let activityColor: String
    let startedAt:     Date
    let replaced:      ReplacedTimer?
    /// Unlabeled time left behind when starting from idle (shown as a hint).
    let unlabeledBefore: TimeInterval

    var undoDeadline: Date { startedAt.addingTimeInterval(LogReceipt.undoWindow) }

    func canUndo(at now: Date = Date()) -> Bool { now < undoDeadline }
}

// MARK: - TimeTrackingManager

@MainActor
class TimeTrackingManager: ObservableObject {

    // MARK: - Properties

    private var modelContext: ModelContext
    private let defaults: UserDefaults

    @Published var currentTimeBlock: TimeBlock?
    @Published var activeSet: ActivitySet?
    @Published var currentTimeBlockRule: TimeBlockRule?

    /// Set when a retrospective tap covers a span >= confirmThreshold.
    /// The UI presents a confirm sheet bound to this.
    @Published var pendingLabel: PendingLabel?

    /// The block the last retrospective tap created. Drives the post-tap
    /// card (Undo · Change · Add note). Cleared by Undo, Skip, a mode
    /// switch, or the next tap replacing it.
    @Published private(set) var lastReceipt: LogReceipt?

    /// The most recently finished block, for the "Last: …" row. A snapshot,
    /// refreshed on every write path and whenever the Timer tab appears.
    @Published private(set) var lastCompleted: LoggedBlockSnapshot?

    /// The live timer just started or switched. Drives the post-start card.
    @Published private(set) var lastTimerReceipt: TimerReceipt?

    /// True while a live timer (a block with no end) is running. This is
    /// the only "mode" left: what a tap does follows from it.
    var isTimerRunning: Bool {
        guard let block = currentTimeBlock else { return false }
        return block.endTime == nil
    }

    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: "notificationsEnabled") }
        set { defaults.set(newValue, forKey: "notificationsEnabled") }
    }

    /// Spans at or above this length open the confirm sheet instead of
    /// committing directly. Guards the forgot-the-app-for-a-day case.
    var confirmThreshold: TimeInterval {
        let saved = defaults.double(forKey: "retroConfirmThreshold")
        return saved > 0 ? saved : 4 * 3600
    }

    private var timer: Timer?
    private var timerTick = 0
    private let historyManager = HistoryManager.shared
    private var audioPlayer: AVAudioPlayer?

    /// Cache of the last completed block's end, so `retrospectiveAnchor`
    /// (read every second by the UI) doesn't hit the store each tick.
    /// Refreshed on every write path.
    private var cachedLastCompletedEnd: Date?

    // MARK: - Initialization

    init(modelContext: ModelContext, defaults: UserDefaults = .standard) {
        self.modelContext = modelContext
        self.defaults = defaults

        if defaults.object(forKey: "notificationsEnabled") == nil {
            notificationsEnabled = true
        }

        cleanUpLegacyState()
        refreshLastCompleted()
        resumeActiveTimeBlock()
        startTimer()
        setupLifecycleObservers()
        checkAndApplyCurrentTimeBlockRule()
    }

    /// Removes state the old architecture persisted. One-shot, idempotent.
    private func cleanUpLegacyState() {
        let d = defaults
        for key in ["retrospectiveAnchorTime", "retrospectivePauseDuration",
                    "retrospectiveIsPaused", "retrospectivePauseStart",
                    "backgroundEnteredTime", "maxBackgroundDuration",
                    "savedEntryMode"] {   // Step 2: Start/Log switch removed
            d.removeObject(forKey: key)
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["backgroundReminder", "pauseTimeout"]
        )
    }

    // MARK: - Retrospective Anchor (derived, never stored)

    /// The start of currently-unlabeled time:
    ///   max(end of last completed block, discard marker, window floor),
    /// falling back to start-of-day when no block exists and no window
    /// is set. With the window disabled, the anchor may lie in a previous
    /// day — waking up and tapping Sleep labels the whole night.
    var retrospectiveAnchor: Date {
        let now = Date()
        var anchor = cachedLastCompletedEnd
            ?? Calendar.current.startOfDay(for: now)

        if let marker = discardMarker, marker > anchor {
            anchor = marker
        }
        if let floor = TrackingWindow.load(from: defaults).anchorFloor(on: now), anchor < floor {
            anchor = floor
        }
        return min(anchor, now)
    }

    var unlabeledDuration: TimeInterval {
        max(0, Date().timeIntervalSince(retrospectiveAnchor))
    }

    /// The one piece of retrospective state that cannot be derived:
    /// "the user explicitly skipped the span up to this moment".
    private var discardMarker: Date? {
        get {
            guard let ts = defaults.object(forKey: "retroDiscardMarker") as? Double
            else { return nil }
            return Date(timeIntervalSince1970: ts)
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: "retroDiscardMarker")
            } else {
                defaults.removeObject(forKey: "retroDiscardMarker")
            }
        }
    }

    /// Re-reads the last finished block. Call when blocks may have changed
    /// outside the manager (the Timer tab does this on appear), so deleting
    /// the newest block in Records moves the anchor back immediately.
    func refreshLastCompleted() {
        let last = getLastCompletedBlock()
        cachedLastCompletedEnd = last?.endTime
        let snapshot = last.flatMap(LoggedBlockSnapshot.init)
        if snapshot != lastCompleted { lastCompleted = snapshot }
    }

    // MARK: - Unified Tap Handlers

    /// One tap behaviour:
    ///   • no timer running → label the time since the last entry,
    ///   • a timer running  → switch it to this activity (tapping the
    ///                        running activity resumes it if paused).
    func handleActivityTap(_ activity: Activity) {
        guard isTimerRunning, let current = currentTimeBlock else {
            labelRetrospectiveSpan(activity: activity)
            return
        }
        if current.activityID == activity.id {
            if current.isPaused { resumeFromPause() }
            return
        }
        startLiveTimer(activity)
    }

    func handlePauseTap() {
        guard isTimerRunning else { return }
        pauseCurrentActivity()
    }

    func handleResumeTap() {
        guard isTimerRunning else { return }
        resumeFromPause()
    }

    func handleStopTap() {
        guard isTimerRunning else { return }
        stopCurrentActivity()
    }

    // MARK: - Retrospective Tracking

    private func labelRetrospectiveSpan(activity: Activity) {
        let now = Date()
        let anchor = retrospectiveAnchor
        let span = now.timeIntervalSince(anchor)

        guard span >= 1 else { return }   // double-tap guard

        if span >= confirmThreshold {
            pendingLabel = PendingLabel(activity: activity, suggestedStart: anchor, end: now)
            return
        }
        commitRetrospectiveBlock(activity: activity, from: anchor, to: now)
    }

    /// Called by the confirm sheet. `start` may have been moved later than
    /// the suggestion — the skipped leading span simply becomes a gap,
    /// which is the correct record of it.
    func commitPendingLabel(start: Date) {
        guard let pending = pendingLabel else { return }
        let clamped = min(max(start, pending.suggestedStart), pending.end)
        commitRetrospectiveBlock(activity: pending.activity, from: clamped, to: pending.end)
        pendingLabel = nil
    }

    func cancelPendingLabel() {
        pendingLabel = nil
    }

    private func commitRetrospectiveBlock(activity: Activity, from start: Date, to end: Date) {
        let previousMarker = discardMarker
        let block = TimeBlock(activity: activity, startTime: start)
        block.endTime = end
        block.stopState = "stopped"
        modelContext.insert(block)

        discardMarker = nil   // superseded: the anchor now derives from this block
        saveAndInvalidate(block: block)
        updateIdleTimerState()

        lastTimerReceipt = nil
        if let snapshot = LoggedBlockSnapshot(block) {
            lastReceipt = LogReceipt(block: snapshot, loggedAt: Date(),
                                     previousDiscardMarker: previousMarker)
        }
    }

    // MARK: - Post-tap actions (Undo · Change · Add note)

    /// Reverses the last retrospective tap exactly: the block (and any note
    /// added to it) is deleted and the skip marker it cleared is restored,
    /// so the unlabeled counter resumes from where it was before the tap.
    /// Only within `LogReceipt.undoWindow` of the tap.
    @discardableResult
    func undoLastLog(now: Date = Date()) -> Bool {
        guard let receipt = lastReceipt else { return false }
        lastReceipt = nil
        guard receipt.canUndo(at: now),
              let block = self.block(withID: receipt.block.blockID) else { return false }

        let blockID = block.id
        let notes = FetchDescriptor<Remark>(predicate: #Predicate { $0.timeBlockID == blockID })
        for note in (try? modelContext.fetch(notes)) ?? [] { modelContext.delete(note) }
        modelContext.delete(block)

        discardMarker = receipt.previousDiscardMarker
        saveContext()
        refreshLastCompleted()
        invalidateDays(from: receipt.block.start, to: receipt.block.end)
        updateIdleTimerState()
        return true
    }

    /// Changes which activity a finished block belongs to — the fix for
    /// tapping the wrong button. Times are untouched.
    func relabelBlock(id: UUID, to activity: Activity) {
        guard let block = self.block(withID: id), block.activityID != activity.id else { return }
        block.activityID    = activity.id
        block.activityName  = activity.name
        block.activityColor = activity.color
        block.activitySetID = activity.sets.first(where: { $0.isActive })?.id
        saveAndInvalidate(block: block)

        if var receipt = lastReceipt, receipt.block.blockID == id,
           let snapshot = LoggedBlockSnapshot(block) {
            receipt.block = snapshot
            lastReceipt = receipt
        }
    }

    /// Hides the post-tap card without undoing anything.
    func dismissReceipt() {
        lastReceipt = nil
    }

    func block(withID id: UUID) -> TimeBlock? {
        var descriptor = FetchDescriptor<TimeBlock>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Regenerates the summary of every day in [start, end]. Used where the
    /// block itself no longer exists (after a delete).
    private func invalidateDays(from start: Date, to end: Date) {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        while day <= lastDay {
            historyManager.invalidateDate(day, in: modelContext)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
    }

    /// "I'm done accounting for the span behind me." Moves the anchor to
    /// now; the skipped span stays visible as a gap in the ledger rather
    /// than silently vanishing.
    func discardUnlabeledTime() {
        lastReceipt = nil
        discardMarker = Date()
        objectWillChange.send()
        updateIdleTimerState()
    }

    func getLastCompletedBlock() -> TimeBlock? {
        var descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.endTime != nil },
            sortBy: [SortDescriptor(\.endTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Live timer (started from the long-press menu)

    /// Starts a live timer for `activity`, switching away from any timer
    /// already running, and shows the post-start card with Undo.
    /// Unlabeled time before it is left as is (it stays a gap you can fill).
    func startLiveTimer(_ activity: Activity, targetDuration: TimeInterval? = nil) {
        let previous = isTimerRunning ? currentTimeBlock : nil
        let replaced = previous.map {
            TimerReceipt.ReplacedTimer(blockID: $0.id, activityName: $0.activityName,
                                       wasPaused: $0.isPaused)
        }
        let unlabeled = previous == nil ? unlabeledDuration : 0

        lastReceipt = nil
        startActivity(activity, targetDuration: targetDuration)
        guard let block = currentTimeBlock else { return }

        lastTimerReceipt = TimerReceipt(
            blockID: block.id, activityName: block.activityName,
            activityColor: block.activityColor, startedAt: block.startTime,
            replaced: replaced, unlabeledBefore: unlabeled
        )
    }

    /// Reverses the last start/switch within the Undo window: the new
    /// block is deleted and a timer it replaced runs again exactly as it
    /// was (including a pause that was open at the switch).
    @discardableResult
    func undoTimerStart(now: Date = Date()) -> Bool {
        guard let receipt = lastTimerReceipt else { return false }
        lastTimerReceipt = nil
        guard receipt.canUndo(at: now),
              let block = self.block(withID: receipt.blockID),
              block.endTime == nil else { return false }

        let blockID = block.id
        let notes = FetchDescriptor<Remark>(predicate: #Predicate { $0.timeBlockID == blockID })
        for note in (try? modelContext.fetch(notes)) ?? [] { modelContext.delete(note) }
        modelContext.delete(block)
        currentTimeBlock = nil
        cancelTargetAlarm()

        if let replaced = receipt.replaced, let previous = self.block(withID: replaced.blockID) {
            reopen(previous, wasPaused: replaced.wasPaused)
            currentTimeBlock = previous
        }

        saveContext()
        refreshLastCompleted()
        invalidateDays(from: receipt.startedAt, to: now)
        if let current = currentTimeBlock {
            historyManager.invalidate(block: current, in: modelContext)
            rescheduleTargetAlarmIfNeeded()
        } else {
            scheduleInactivityReminder()
        }
        updateIdleTimerState()
        return true
    }

    /// Makes a switched-away block live again. If it was paused at the
    /// switch, the pause that the switch closed is reopened.
    private func reopen(_ block: TimeBlock, wasPaused: Bool) {
        block.endTime = nil
        block.stopState = "ongoing"
        guard wasPaused, let idx = block.pauseSpans.lastIndex(where: { $0.end != nil }) else { return }
        var spans = block.pauseSpans
        spans[idx].end = nil
        block.pauseSpans = spans
        block.isPaused = true
        block.pauseStartTime = spans[idx].start
    }

    /// Hides the post-start card without undoing anything.
    func dismissTimerReceipt() {
        lastTimerReceipt = nil
    }

    // MARK: - Live timer mechanics

    func startActivity(_ activity: Activity, targetDuration: TimeInterval? = nil) {
        let now = Date()

        if let current = currentTimeBlock, current.endTime == nil {
            if current.isPaused { current.endPause(at: now) }
            current.endTime = now
            current.stopState = "switched"
            saveAndInvalidate(block: current)
        }

        let newBlock = TimeBlock(activity: activity, startTime: now)
        newBlock.targetDuration = targetDuration
        modelContext.insert(newBlock)
        currentTimeBlock = newBlock

        cancelInactivityReminder()
        saveAndInvalidate(block: newBlock)
        updateIdleTimerState()

        if let target = targetDuration {
            scheduleTargetAlarm(duration: target, activityName: activity.name)
        } else {
            cancelTargetAlarm()
        }
    }

    func stopCurrentActivity() {
        guard let current = currentTimeBlock else { return }
        lastTimerReceipt = nil
        let now = Date()
        if current.isPaused { current.endPause(at: now) }

        current.endTime = now
        current.stopState = "stopped"
        currentTimeBlock = nil

        saveAndInvalidate(block: current)
        cancelTargetAlarm()
        updateIdleTimerState()
        scheduleInactivityReminder()
    }

    func pauseCurrentActivity() {
        guard let current = currentTimeBlock,
              !current.isPaused,
              current.endTime == nil else { return }

        current.beginPause()
        if current.targetDuration != nil { cancelTargetAlarm() }
        saveContext()
        updateIdleTimerState()
    }

    func resumeFromPause() {
        guard let current = currentTimeBlock, current.isPaused else { return }
        current.endPause()
        saveContext()
        updateIdleTimerState()
        rescheduleTargetAlarmIfNeeded()
    }

    // MARK: - Target Duration

    func setTargetDuration(for block: TimeBlock, duration: TimeInterval?) {
        block.targetDuration = duration
        saveContext()

        if let target = duration {
            let remaining = max(0, target - block.duration)
            if remaining > 0 {
                scheduleTargetAlarm(duration: remaining, activityName: block.activityName)
            }
        } else {
            cancelTargetAlarm()
        }
    }

    private func checkTargetDuration() {
        guard let current = currentTimeBlock,
              let target = current.targetDuration,
              !current.isPaused else { return }

        if current.duration >= target {
            current.targetDuration = nil
            stopCurrentActivity()
            HapticManager.shared.notification(type: .success)
            playTimerCompletionSound()
        }
    }

    private func scheduleTargetAlarm(duration: TimeInterval, activityName: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["targetAlarm"])
        guard duration > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time's Up!"
        content.body = "Your \(activityName) session has ended."
        content.sound = UNNotificationSound.defaultCritical
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: duration, repeats: false)
        center.add(UNNotificationRequest(identifier: "targetAlarm", content: content, trigger: trigger))
    }

    private func cancelTargetAlarm() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["targetAlarm"])
    }

    private func rescheduleTargetAlarmIfNeeded() {
        guard let current = currentTimeBlock,
              let target = current.targetDuration,
              !current.isPaused else {
            if currentTimeBlock?.targetDuration != nil { cancelTargetAlarm() }
            return
        }
        let remaining = max(0, target - current.duration)
        if remaining > 0 {
            scheduleTargetAlarm(duration: remaining, activityName: current.activityName)
        }
    }

    private func playTimerCompletionSound() {
        if let url = findAlertSoundURL() {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.play()
                return
            } catch { /* fall through */ }
        }
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }

    private func findAlertSoundURL() -> URL? {
        let paths = [
            "/System/Library/Audio/UISounds/alarm.caf",
            "/System/Library/Audio/UISounds/nano/alarm_nightstand_haptic.caf",
            "/System/Library/Audio/UISounds/SIMToolkitCallDropped.caf"
        ]
        return paths.compactMap { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Timer
    // Drives target-completion checks and rule application only. UI refresh
    // is the view's job — no objectWillChange spam from here.

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.timerTick += 1
                self.checkTargetDuration()
                if self.timerTick % 30 == 0 {
                    self.checkAndApplyCurrentTimeBlockRule()
                }
            }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Lifecycle
    // Persistence only. Blocks survive background/termination by virtue of
    // being persisted rows — nothing gets auto-stopped anymore.

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification, object: nil)
    }

    @objc private func appDidEnterBackground() { saveContext() }
    @objc private func appWillTerminate()      { saveContext() }

    @objc private func appWillEnterForeground() {
        refreshLastCompleted()
        checkAndApplyCurrentTimeBlockRule()

        // Target elapsed while away → close the block retroactively at the
        // exact target moment, not at "now".
        if let current = currentTimeBlock,
           let target = current.targetDuration,
           !current.isPaused,
           current.duration >= target {
            completeTargetRetroactively(current, target: target)
        } else {
            rescheduleTargetAlarmIfNeeded()
        }
        objectWillChange.send()
    }

    // MARK: - Session Recovery

    private func resumeActiveTimeBlock() {
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        guard let activeBlock = try? modelContext.fetch(descriptor).first else { return }
        currentTimeBlock = activeBlock

        if let target = activeBlock.targetDuration,
           !activeBlock.isPaused,
           activeBlock.duration >= target {
            completeTargetRetroactively(activeBlock, target: target)
            notifyTimerCompletedWhileAway(activityName: activeBlock.activityName)
            return
        }

        updateIdleTimerState()
        rescheduleTargetAlarmIfNeeded()
    }

    private func completeTargetRetroactively(_ block: TimeBlock, target: TimeInterval) {
        block.targetDuration = nil
        block.endTime = block.startTime.addingTimeInterval(target + block.pauseDuration)
        block.stopState = "stopped"
        currentTimeBlock = nil
        saveAndInvalidate(block: block)
        cancelTargetAlarm()
        updateIdleTimerState()
        scheduleInactivityReminder()
    }

    // MARK: - Set Auto-Switching

    func getActiveTimeBlockRule() -> TimeBlockRule? {
        let descriptor = FetchDescriptor<TimeBlockRule>(
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        guard let rules = try? modelContext.fetch(descriptor) else { return nil }
        return rules.first(where: { $0.isActiveNow() })
    }

    func manualSwitchToSet(_ set: ActivitySet) {
        executeSetSwitch(to: set)
    }

    private func executeSetSwitch(to targetSet: ActivitySet) {
        let sets = try? modelContext.fetch(FetchDescriptor<ActivitySet>())
        sets?.forEach { $0.isActive = false }
        targetSet.isActive = true
        activeSet = targetSet
        saveContext()
    }

    func checkAndApplyCurrentTimeBlockRule() {
        let activeRule = getActiveTimeBlockRule()
        let previousRule = currentTimeBlockRule
        currentTimeBlockRule = activeRule

        guard let rule = activeRule,
              let setID = rule.linkedSetID,
              previousRule?.id != rule.id else { return }

        let sets = try? modelContext.fetch(FetchDescriptor<ActivitySet>())
        let currentActiveSet = sets?.first { $0.isActive }

        if currentActiveSet?.id != setID,
           let targetSet = sets?.first(where: { $0.id == setID }) {
            executeSetSwitch(to: targetSet)
            notifySetSwitch(setName: targetSet.name, ruleName: rule.name)
        }
    }

    // MARK: - Keep Screen On

    func updateIdleTimerState() {
        let keepScreenOn = defaults.bool(forKey: "keepScreenOnWhileTracking")
        let isProspectiveTracking = currentTimeBlock != nil && currentTimeBlock?.endTime == nil
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && isProspectiveTracking
    }

    // MARK: - Data Queries

    func getTodaysTimeBlocks() -> [TimeBlock] {
        LedgerBuilder.makeLedger(for: Date(), context: modelContext).blocks.map(\.block)
    }

    func getTodaysStats() -> DayStats {
        LedgerBuilder.makeLedger(for: Date(), context: modelContext).stats
    }

    func todaysLedger() -> DayLedger {
        LedgerBuilder.makeLedger(for: Date(), context: modelContext)
    }

    // MARK: - Notifications

    private func notifySetSwitch(setName: String, ruleName: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Activity Set Changed"
        content.body = "\(ruleName): Switched to \(setName)"
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "setSwitch", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    private func notifyTimerCompletedWhileAway(activityName: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Timer Completed"
        content.body = "Your \(activityName) session ended while the app was closed."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "timerCompletedWhileAway", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    private func scheduleInactivityReminder() {
        guard notificationsEnabled,
              defaults.bool(forKey: "inactivityReminderEnabled") else { return }

        let interval = defaults.double(forKey: "inactivityReminderInterval")
        let reminderInterval = interval > 0 ? interval : 1800

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["inactivityReminder"])

        let content = UNMutableNotificationContent()
        content.title = "Time to log?"
        content.body = "It's been \(reminderInterval.formattedDuration) since your last entry. Tap an activity to log what you've been doing."
        content.sound = .default

        center.add(UNNotificationRequest(
            identifier: "inactivityReminder", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: reminderInterval, repeats: false)))
    }

    private func cancelInactivityReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["inactivityReminder"])
    }

    // MARK: - Persistence

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("[Cadence] Failed to save context: \(error)")
        }
    }

    /// Saves, refreshes the anchor cache, and invalidates the summary of
    /// EVERY day the block overlaps — an overnight block touches two.
    func saveAndInvalidate(block: TimeBlock) {
        saveContext()
        refreshLastCompleted()
        historyManager.invalidate(block: block, in: modelContext)
    }
}
