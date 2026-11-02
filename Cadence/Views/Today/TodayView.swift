//
//  TodayView.swift
//  Cadence
//
//  Step 4 — the home tab. Today reads top to bottom like a diary page:
//
//    Today                         (large title)
//    Monday 2 November             6h 20m logged · mostly Meetings · 3 notes
//    ☀ Intention
//    09:00 ┃ Focused Work   1h 30m
//          ┃ Got the draft done #writing
//    10:30 ┊ 15m
//    10:45 ┃ Meetings         47m
//    ── now ──────────────────────
//    [ 23m since Meetings  ·  Last  ·  Leave blank ]   or the live timer
//    [ activity grid ]
//    ☾ Reflection
//
//  It opens scrolled to the "now" card, and returns there after each tap.
//  Tap an entry to open it; hold for Add note / Edit / Delete.
//

import SwiftUI
import SwiftData
import Combine

struct TodayView: View {
    @ObservedObject var manager: TimeTrackingManager
    @Environment(\.modelContext) private var modelContext

    @Query private var activitySets: [ActivitySet]
    @Query private var dayNotes: [DayNote]
    @AppStorage(Accountability.key) private var accountable = false

    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var path: [EntryRoute] = []

    @State private var editorTarget: JournalEditorTarget?
    @State private var relabelTarget: RelabelTarget?
    @State private var editingBlock: TimeBlock?
    @State private var fillGap: ComputedGap?
    @State private var showingLeaveBlankConfirm = false
    @State private var lastDeleted: DeletedBlock?

    private static let nowAnchor = "now"

    /// Identifies the block the "Change activity" sheet is relabeling.
    struct RelabelTarget: Identifiable {
        let id: UUID          // block ID
        let activityID: UUID?
    }

    // MARK: - Derived state

    /// The post-tap banner shows only while Undo is still possible.
    private var visibleReceipt: LogReceipt? {
        guard !manager.isTimerRunning,
              let receipt = manager.lastReceipt, receipt.canUndo() else { return nil }
        return receipt
    }

    /// The post-start banner, same rule.
    private var visibleTimerReceipt: TimerReceipt? {
        guard manager.isTimerRunning,
              let receipt = manager.lastTimerReceipt, receipt.canUndo() else { return nil }
        return receipt
    }

    /// Changes whenever a bottom card appears or goes, for the animation.
    private var bannerID: UUID? {
        visibleReceipt?.id ?? visibleTimerReceipt?.id ?? lastDeleted?.id
    }

    private var activeSet: ActivitySet? { activitySets.first { $0.isActive } }

    private var activeSetActivities: [Activity] {
        (activeSet?.activities ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var isCurrentlyPaused: Bool {
        manager.isTimerRunning && (manager.currentTimeBlock?.isPaused ?? false)
    }

    private var todayNote: DayNote? {
        dayNotes.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private var showsIntentionBanner: Bool {
        guard todayNote?.intention.isEmpty ?? true else { return false }
        return Calendar.current.component(.hour, from: Date()) < 14
    }

    /// "Meetings" when the counter runs from the end of the last entry.
    /// After a Leave blank it runs from that moment instead, so no name.
    private var sinceActivityName: String? {
        guard let last = manager.lastCompleted,
              abs(last.end.timeIntervalSince(manager.retrospectiveAnchor)) < 1 else { return nil }
        return last.activityName
    }

    private var pageActions: DayPageActions {
        DayPageActions(
            open: { path.append(EntryRoute(blockID: $0.id)) },
            addNote: { editorTarget = .newNote(blockID: $0.id) },
            editNote: { editorTarget = .editNote(remarkID: $0.id) },
            editTimes: { editingBlock = $0 },
            delete: { block in
                lastDeleted = BlockDeletion.delete(block, in: modelContext)
                manager.refreshLastCompleted()
            },
            fill: { fillGap = $0 },
            editIntention: { editorTarget = .intention(day: $0) },
            editReflection: { editorTarget = .reflection(day: $0) }
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        intentionSection
                            .padding(.horizontal)

                        TodayPageSection(day: day, accountable: accountable, actions: pageActions)

                        nowSection
                            .id(Self.nowAnchor)

                        BookendRow(kind: .reflection, text: todayNote?.reflection,
                                   placeholder: "How did today go? Write a reflection…") {
                            editorTarget = .reflection(day: day)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
                .onAppear {
                    manager.refreshLastCompleted()   // picks up edits made in the Journal
                    manager.updateIdleTimerState()
                    proxy.scrollTo(Self.nowAnchor, anchor: .bottom)
                }
                .onChange(of: manager.lastReceipt?.id) { _, _ in
                    withAnimation { proxy.scrollTo(Self.nowAnchor, anchor: .bottom) }
                }
                .safeAreaInset(edge: .bottom) { bottomCard }
                .animation(.snappy(duration: 0.3), value: bannerID)
            }
            .navigationTitle("Today")
            .navigationDestination(for: EntryRoute.self) { route in
                EntryDetailView(blockID: route.blockID)
            }
        }
        .onReceive(timer) { _ in
            // The view timer is the only per-second UI driver. Something is
            // always counting: either time since the last entry or a live timer.
            manager.objectWillChange.send()
            let today = Calendar.current.startOfDay(for: Date())
            if today != day { day = today }
        }
        .task(id: lastDeleted?.id) {
            guard lastDeleted != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            lastDeleted = nil
        }
        .fullScreenCover(item: $editorTarget) { target in
            JournalEditorView(target: target)
        }
        .sheet(item: $relabelTarget) { target in
            RelabelActivitySheet(currentActivityID: target.activityID) { activity in
                manager.relabelBlock(id: target.id, to: activity)
            }
        }
        .sheet(item: $editingBlock, onDismiss: { manager.refreshLastCompleted() }) { block in
            QuickEditSheet(block: block,
                           conflictDetector: ConflictDetector(modelContext: modelContext),
                           onSave: { try? modelContext.save() })
        }
        .sheet(item: $fillGap, onDismiss: { manager.refreshLastCompleted() }) { gap in
            AddBlockSheet(date: gap.start, prefilledGap: gap,
                          conflictDetector: ConflictDetector(modelContext: modelContext),
                          onSave: { try? modelContext.save() })
        }
        .sheet(item: Binding(
            get: { manager.pendingLabel },
            set: { if $0 == nil { manager.cancelPendingLabel() } }
        )) { pending in
            LabelConfirmSheet(pending: pending, manager: manager)
                .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Leave \(manager.unlabeledDuration.formattedDuration) blank?",
            isPresented: $showingLeaveBlankConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave Blank") { manager.discardUnlabeledTime() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("It stays in your journal as blank time, and you can fill it in later. The counter starts again from now.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var intentionSection: some View {
        if showsIntentionBanner {
            IntentionBanner { editorTarget = .intention(day: day) }
        } else {
            BookendRow(kind: .intention, text: todayNote?.intention,
                       placeholder: "Set an intention for today…") {
                editorTarget = .intention(day: day)
            }
        }
    }

    @ViewBuilder
    private var nowSection: some View {
        VStack(spacing: 16) {
            if manager.isTimerRunning {
                CurrentActivityCard(
                    block: manager.currentTimeBlock,
                    isPaused: isCurrentlyPaused,
                    onPause:  { manager.handlePauseTap() },
                    onStop:   { manager.handleStopTap() },
                    onResume: { manager.handleResumeTap() },
                    onQuickRemark: {
                        if let block = manager.currentTimeBlock {
                            editorTarget = .newNote(blockID: block.id)
                        }
                    },
                    onSetTarget: { target in
                        if let currentBlock = manager.currentTimeBlock {
                            if target != nil { NotificationPermission.requestIfNeeded() }
                            manager.setTargetDuration(for: currentBlock, duration: target)
                        }
                    }
                )
            } else {
                RetrospectiveCard(
                    anchor: manager.retrospectiveAnchor,
                    unlabeledDuration: manager.unlabeledDuration,
                    sinceActivityName: sinceActivityName,
                    lastLogged: visibleReceipt == nil ? manager.lastCompleted : nil,
                    onLeaveBlank: { showingLeaveBlankConfirm = true },
                    onAddNote: { snapshot in openNote(forBlockID: snapshot.blockID) },
                    onChange: { snapshot in
                        relabelTarget = RelabelTarget(id: snapshot.blockID, activityID: snapshot.activityID)
                    }
                )
            }

            if activitySets.count > 1 {
                ActivitySetPicker(sets: activitySets, manager: manager)
                    .padding(.horizontal)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 12) {
                ForEach(activeSetActivities) { activity in
                    ActivityButton(
                        activity: activity,
                        isActive: manager.isTimerRunning
                            && manager.currentTimeBlock?.activityID == activity.id
                            && !isCurrentlyPaused
                    ) {
                        manager.handleActivityTap(activity)
                    }
                    .contextMenu { timerMenu(for: activity) }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var bottomCard: some View {
        if let receipt = visibleReceipt {
            LogReceiptBanner(
                receipt: receipt,
                onUndo: {
                    if manager.undoLastLog() {
                        HapticManager.shared.notification(type: .warning)
                    }
                },
                onChange: {
                    relabelTarget = RelabelTarget(id: receipt.block.blockID,
                                                  activityID: receipt.block.activityID)
                },
                onAddNote: {
                    manager.dismissReceipt()
                    openNote(forBlockID: receipt.block.blockID)
                },
                onDismiss: { manager.dismissReceipt() }
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let receipt = visibleTimerReceipt {
            TimerReceiptBanner(
                receipt: receipt,
                onUndo: {
                    if manager.undoTimerStart() {
                        HapticManager.shared.notification(type: .warning)
                    }
                },
                onDismiss: { manager.dismissTimerReceipt() }
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let deleted = lastDeleted {
            UndoToast(label: "Deleted \(deleted.activityName)") {
                BlockDeletion.restore(deleted, in: modelContext)
                lastDeleted = nil
                manager.refreshLastCompleted()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Timer menu & note routing

    @ViewBuilder
    private func timerMenu(for activity: Activity) -> some View {
        let isRunningThis = manager.isTimerRunning
            && manager.currentTimeBlock?.activityID == activity.id

        if isRunningThis {
            Button(role: .destructive) { manager.handleStopTap() } label: {
                Label("Stop timer", systemImage: "stop.fill")
            }
        } else {
            Button { manager.startLiveTimer(activity) } label: {
                Label(manager.isTimerRunning ? "Switch timer to \(activity.name)" : "Start timer",
                      systemImage: "play.fill")
            }
            Menu {
                ForEach([15, 25, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") {
                        NotificationPermission.requestIfNeeded()   // so the alarm can sound
                        manager.startLiveTimer(activity, targetDuration: TimeInterval(minutes * 60))
                    }
                }
            } label: {
                Label("Start with goal", systemImage: "bell")
            }
        }
    }

    /// Opens the editor for a new note on a block. Does nothing if the
    /// block was deleted meanwhile (a snapshot can outlive its block).
    private func openNote(forBlockID id: UUID) {
        guard manager.block(withID: id) != nil else { return }
        editorTarget = .newNote(blockID: id)
    }
}

// MARK: - Today's entries

/// Today's finished entries and the blank time between them. Its own view
/// so its queries are keyed to the day, and so the per-second tick of the
/// counter doesn't rebuild the page.
private struct TodayPageSection: View {
    @Query private var blocks: [TimeBlock]
    @Query private var remarks: [Remark]

    let day: Date
    let accountable: Bool
    let actions: DayPageActions

    init(day: Date, accountable: Bool, actions: DayPageActions) {
        self.day = day
        self.accountable = accountable
        self.actions = actions

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let notesFrom = calendar.date(byAdding: .day, value: -1, to: start)!
        let distantFuture = Date.distantFuture

        _blocks = Query(filter: #Predicate<TimeBlock> { block in
            block.startTime < end && (block.endTime ?? distantFuture) > start
        }, sort: \.startTime)
        _remarks = Query(filter: #Predicate<Remark> { $0.timestamp >= notesFrom })
    }

    var body: some View {
        // The running timer lives on the "now" card, and the stretch up to
        // now is the counter, so neither is repeated here.
        let page = DayPageBuilder.make(
            for: day, blocks: blocks, remarks: remarks,
            options: .init(includeRunning: false, minimumGap: 5 * 60, dropTrailingGap: true)
        )

        VStack(alignment: .leading, spacing: 2) {
            DayHeaderView(day: day, summary: page.summary,
                          gapCount: accountable ? page.gapCount : nil,
                          title: day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .padding(.bottom, 6)

            if page.isEmpty {
                Text("Nothing logged yet today. When you finish something, tap it below.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            }

            ForEach(page.items) { item in
                switch item {
                case .entry(let entry):
                    DiaryEntryRow(
                        entry: entry,
                        onOpen: { actions.open(entry.block) },
                        onAddNote: { actions.addNote(entry.block) },
                        onEditNote: actions.editNote,
                        onEditTimes: { actions.editTimes(entry.block) },
                        onDelete: { actions.delete(entry.block) }
                    )
                case .gap(let gap):
                    BlankTimeRow(gap: gap, emphasised: accountable) { actions.fill(gap) }
                }
            }
        }
        .padding(.horizontal)
    }
}
