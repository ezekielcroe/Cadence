//
//  JournalView.swift
//  Cadence
//
//  Step 5 — one place for every past day, replacing the Records and
//  Remarks tabs.
//
//    Diary   each day as a page: intention, entries with notes in full,
//            quiet blank time, reflection. Days newest first; each day
//            reads top to bottom.
//    Ledger  the same days as compact rows for fixing them: blank time
//            with Fill, swipe to edit or delete, Select → Merge / Delete.
//
//  One search (notes), one filter (activity and/or tag), one month
//  navigator. Tap an entry to open it; everything else is a swipe or the
//  long-press menu.
//

import SwiftUI
import SwiftData

struct JournalView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Activity.name) private var allActivities: [Activity]
    @Query private var allRemarks: [Remark]
    @AppStorage(Accountability.key) private var accountable = false
    @AppStorage("journal.mode") private var modeRaw = JournalMode.diary.rawValue

    @State private var month = Date()
    @State private var path: [EntryRoute] = []
    @State private var searchText = ""
    @State private var selectedActivity: String?
    @State private var selectedTag: String?

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingMergeError = false

    @State private var editorTarget: JournalEditorTarget?
    @State private var editingBlock: TimeBlock?
    @State private var addMode: AddEntryMode?
    @State private var lastDeleted: [DeletedBlock] = []
    @State private var lastDeletedID = UUID()

    enum JournalMode: String, CaseIterable, Identifiable {
        case diary, ledger
        var id: String { rawValue }
        var title: String { self == .diary ? "Diary" : "Ledger" }
    }

    enum AddEntryMode: Identifiable {
        case manual
        case fill(ComputedGap)

        var id: String {
            switch self {
            case .manual:          return "manual"
            case .fill(let gap):   return "fill-\(gap.id)"
            }
        }

        var gap: ComputedGap? {
            if case .fill(let gap) = self { return gap }
            return nil
        }
    }

    // MARK: - Derived

    private var mode: JournalMode { JournalMode(rawValue: modeRaw) ?? .diary }

    private var monthRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        return (start, cal.date(byAdding: .month, value: 1, to: start)!)
    }

    private var isViewingCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    private var allTags: [String] { TagIndex.uniqueSorted(allRemarks.map(\.tags)) }
    private var activityNames: [String] { Array(Set(allActivities.map(\.name))).sorted() }
    private var isFiltering: Bool { selectedActivity != nil || selectedTag != nil }

    private var selectedBlocks: [TimeBlock] {
        let ids = selectedIDs
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { ids.contains($0.id) },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private var actions: DayPageActions {
        DayPageActions(
            open: { path.append(EntryRoute(blockID: $0.id)) },
            addNote: { editorTarget = .newNote(blockID: $0.id) },
            editNote: { editorTarget = .editNote(remarkID: $0.id) },
            editTimes: { editingBlock = $0 },
            delete: { block in
                guard BlockDeletion.canDelete(block) else { return }
                showUndo([BlockDeletion.delete(block, in: modelContext)])
            },
            fill: { addMode = .fill($0) },
            editIntention: { editorTarget = .intention(day: $0) },
            editReflection: { editorTarget = .reflection(day: $0) }
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if searchText.isEmpty {
                    monthNavigator
                    controlsBar
                    JournalMonthList(
                        start: monthRange.start,
                        end: monthRange.end,
                        mode: mode,
                        activityName: selectedActivity,
                        tag: selectedTag,
                        accountable: accountable,
                        isSelecting: isSelecting,
                        selectedIDs: $selectedIDs,
                        actions: actions
                    )
                    .id(monthRange.start)
                } else {
                    SearchListView(searchText: searchText)
                }
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search notes")
            .toolbar { toolbar }
            .navigationDestination(for: EntryRoute.self) { route in
                EntryDetailView(blockID: route.blockID)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .animation(.snappy(duration: 0.3), value: isSelecting)
            .animation(.snappy(duration: 0.3), value: lastDeleted.isEmpty)
        }
        .onChange(of: modeRaw) { _, _ in endSelection() }
        .task(id: lastDeletedID) {
            guard !lastDeleted.isEmpty else { return }
            try? await Task.sleep(for: .seconds(6))
            lastDeleted = []
        }
        .fullScreenCover(item: $editorTarget) { target in
            JournalEditorView(target: target)
        }
        .sheet(item: $editingBlock) { block in
            QuickEditSheet(block: block,
                           conflictDetector: ConflictDetector(modelContext: modelContext),
                           onSave: { try? modelContext.save() })
        }
        .sheet(item: $addMode) { addMode in
            AddBlockSheet(date: addMode.gap?.start ?? defaultAddDate,
                          prefilledGap: addMode.gap,
                          conflictDetector: ConflictDetector(modelContext: modelContext),
                          onSave: { try? modelContext.save() })
        }
        .alert("Can't merge these entries", isPresented: $showingMergeError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Only finished entries that follow each other with no blank time between them can be merged.")
        }
    }

    /// Manual add starts on the month being viewed (today for this month).
    private var defaultAddDate: Date {
        isViewingCurrentMonth ? Date() : monthRange.start.addingTimeInterval(9 * 3600)
    }

    // MARK: - Month navigator

    private var monthNavigator: some View {
        HStack {
            Button { changeMonth(by: -1) } label: {
                Image(systemName: "chevron.left").padding(8)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            if isViewingCurrentMonth {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { month = Date() }
                } label: {
                    HStack(spacing: 6) {
                        Text(month.formatted(.dateTime.month(.abbreviated).year()))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Divider().frame(height: 16)
                        Label("This month", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }

            Spacer()

            Button { changeMonth(by: 1) } label: {
                Image(systemName: "chevron.right").padding(8)
            }
            .disabled(isViewingCurrentMonth)
            .opacity(isViewingCurrentMonth ? 0.3 : 1)
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func changeMonth(by value: Int) {
        endSelection()
        withAnimation(.easeInOut(duration: 0.25)) {
            month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
        }
    }

    // MARK: - Mode + filters

    private var controlsBar: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("View", selection: $modeRaw) {
                    ForEach(JournalMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                Spacer()

                filterMenu
            }

            if isFiltering {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let activity = selectedActivity {
                            filterChip(activity, icon: "circle.fill") { selectedActivity = nil }
                        }
                        if let tag = selectedTag {
                            filterChip("#\(tag)", icon: "number") { selectedTag = nil }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var filterMenu: some View {
        Menu {
            Menu("Activity") {
                Button("All Activities") { selectedActivity = nil }
                Divider()
                ForEach(activityNames, id: \.self) { name in
                    Button {
                        selectedActivity = name
                    } label: {
                        if selectedActivity == name { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
            }
            if !allTags.isEmpty {
                Menu("Tag") {
                    Button("All Tags") { selectedTag = nil }
                    Divider()
                    ForEach(allTags, id: \.self) { tag in
                        Button {
                            selectedTag = tag
                        } label: {
                            if selectedTag == tag { Label("#\(tag)", systemImage: "checkmark") } else { Text("#\(tag)") }
                        }
                    }
                }
            }
            if isFiltering {
                Divider()
                Button("Clear Filters", role: .destructive) {
                    selectedActivity = nil
                    selectedTag = nil
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .symbolVariant(isFiltering ? .fill : .none)
                .font(.title3)
        }
        .accessibilityLabel("Filter")
    }

    private func filterChip(_ label: String, icon: String, onClear: @escaping () -> Void) -> some View {
        Button(action: { withAnimation { onClear() } }) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption).lineLimit(1)
                Image(systemName: "xmark.circle.fill").font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove filter \(label)")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if mode == .ledger && searchText.isEmpty {
                Button(isSelecting ? "Done" : "Select") {
                    if isSelecting { endSelection() } else { isSelecting = true }
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { addMode = .manual } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add an entry")
        }
    }

    // MARK: - Bottom bar (selection / undo)

    @ViewBuilder
    private var bottomBar: some View {
        if isSelecting {
            let blocks = selectedBlocks
            let canMerge = TimeBlockEditor(modelContext: modelContext).canMerge(blocks)
            HStack(spacing: 12) {
                Text(selectedIDs.isEmpty ? "Select entries" : "\(selectedIDs.count) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if canMerge { merge(blocks) } else { showingMergeError = true }
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .disabled(blocks.count < 2)
                Button(role: .destructive) {
                    let deleted = BlockDeletion.delete(blocks, in: modelContext)
                    endSelection()
                    showUndo(deleted)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(blocks.isEmpty)
            }
            .buttonStyle(.bordered)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if !lastDeleted.isEmpty {
            UndoToast(label: lastDeleted.count == 1
                      ? "Deleted \(lastDeleted[0].activityName)"
                      : "Deleted \(lastDeleted.count) entries") {
                for deleted in lastDeleted { BlockDeletion.restore(deleted, in: modelContext) }
                lastDeleted = []
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func showUndo(_ deleted: [DeletedBlock]) {
        guard !deleted.isEmpty else { return }
        lastDeleted = deleted
        lastDeletedID = UUID()   // restarts the 6-second timer
    }

    private func endSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func merge(_ blocks: [TimeBlock]) {
        guard let first = blocks.first, let activityID = first.activityID else {
            showingMergeError = true
            return
        }
        let descriptor = FetchDescriptor<Activity>(predicate: #Predicate { $0.id == activityID })
        guard let activity = try? modelContext.fetch(descriptor).first else {
            showingMergeError = true
            return
        }
        do {
            try TimeBlockEditor(modelContext: modelContext).mergeBlocks(blocks, intoActivity: activity)
            endSelection()
        } catch {
            showingMergeError = true
        }
    }
}

// MARK: - The month's days

/// The days of one month, newest first, as Diary pages or Ledger rows.
/// Its own view so the queries are scoped to the month.
private struct JournalMonthList: View {
    @Query private var blocks: [TimeBlock]
    @Query private var remarks: [Remark]
    @Query private var dayNotes: [DayNote]

    let mode: JournalView.JournalMode
    let activityName: String?
    let tag: String?
    let accountable: Bool
    let isSelecting: Bool
    @Binding var selectedIDs: Set<UUID>
    let actions: DayPageActions

    private let start: Date
    private let end: Date

    init(start: Date, end: Date, mode: JournalView.JournalMode,
         activityName: String?, tag: String?, accountable: Bool,
         isSelecting: Bool, selectedIDs: Binding<Set<UUID>>, actions: DayPageActions) {
        self.start = start
        self.end = end
        self.mode = mode
        self.activityName = activityName
        self.tag = tag
        self.accountable = accountable
        self.isSelecting = isSelecting
        self._selectedIDs = selectedIDs
        self.actions = actions

        let distantFuture = Date.distantFuture
        let notesFrom = Calendar.current.date(byAdding: .day, value: -1, to: start)!
        _blocks = Query(filter: #Predicate<TimeBlock> { block in
            block.startTime < end && (block.endTime ?? distantFuture) > start
        }, sort: \.startTime)
        _remarks = Query(filter: #Predicate<Remark> { $0.timestamp >= notesFrom })
        _dayNotes = Query(filter: #Predicate<DayNote> { $0.date >= start && $0.date < end })
    }

    private var filtering: Bool { activityName != nil || tag != nil }

    private var options: DayPageBuilder.Options {
        var options = DayPageBuilder.Options()
        options.includeRunning = true
        options.dropTrailingGap = true
        options.minimumGap = mode == .diary ? 5 * 60 : ComputedGap.minimumDisplayDuration
        options.activityName = activityName
        options.tag = tag
        return options
    }

    var body: some View {
        let calendar = Calendar.current
        let notesByDay = Dictionary(dayNotes.map { (calendar.startOfDay(for: $0.date), $0) },
                                    uniquingKeysWith: { first, _ in first })
        let writtenNoteDays = dayNotes
            .filter { !$0.intention.isEmpty || !$0.reflection.isEmpty }
            .map(\.date)
        let days = JournalDays.days(blocks: blocks, noteDays: writtenNoteDays, from: start, to: end)
        let pages: [DayPage] = days.map {
            DayPageBuilder.make(for: $0, blocks: blocks, remarks: remarks, options: options)
        }
        let visible = pages.filter { !filtering || !$0.entries.isEmpty }

        List {
            ForEach(visible, id: \.day) { page in
                let note = notesByDay[page.day]
                Section {
                    dayContent(page, note: note)
                } header: {
                    DayHeaderView(day: page.day, summary: page.summary,
                                  gapCount: accountable ? page.gapCount : nil)
                        .padding(.top, 8)
                }
            }

            if visible.isEmpty {
                emptyState
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - A day

    @ViewBuilder
    private func dayContent(_ page: DayPage, note: DayNote?) -> some View {
        let isRecent = Calendar.current.isDateInToday(page.day) || Calendar.current.isDateInYesterday(page.day)
        let compact = mode == .ledger

        if !filtering, let intention = note?.intention, !intention.isEmpty {
            BookendRow(kind: .intention, text: intention, compact: compact) {
                actions.editIntention(page.day)
            }
            .journalRow()
        }

        ForEach(page.items) { item in
            switch item {
            case .entry(let entry):
                entryRow(entry)
            case .gap(let gap):
                BlankTimeRow(gap: gap, emphasised: mode == .ledger || accountable) {
                    actions.fill(gap)
                }
                .journalRow()
            }
        }

        if page.items.isEmpty && !filtering {
            Text("Nothing logged")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 68)
                .journalRow()
        }

        if !filtering {
            if let reflection = note?.reflection, !reflection.isEmpty {
                BookendRow(kind: .reflection, text: reflection, compact: compact) {
                    actions.editReflection(page.day)
                }
                .journalRow()
            } else if isRecent && mode == .diary {
                BookendRow(kind: .reflection, text: nil, placeholder: "Add a reflection…") {
                    actions.editReflection(page.day)
                }
                .journalRow()
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: DayPage.Entry) -> some View {
        let canEdit = BlockDeletion.canDelete(entry.block)

        switch mode {
        case .diary:
            DiaryEntryRow(
                entry: entry,
                onOpen: { actions.open(entry.block) },
                onAddNote: { actions.addNote(entry.block) },
                onEditNote: actions.editNote,
                onEditTimes: canEdit ? { actions.editTimes(entry.block) } : nil,
                onDelete: canEdit ? { actions.delete(entry.block) } : nil
            )
            .journalRow()
            .swipeActions(edge: .trailing) {
                if canEdit {
                    Button(role: .destructive) { actions.delete(entry.block) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

        case .ledger:
            let isSelected = selectedIDs.contains(entry.id)
            LedgerEntryRow(entry: entry, isSelecting: isSelecting, isSelected: isSelected)
                .onTapGesture {
                    if isSelecting {
                        guard canEdit else { return }
                        if isSelected { selectedIDs.remove(entry.id) } else { selectedIDs.insert(entry.id) }
                    } else {
                        actions.open(entry.block)
                    }
                }
                .journalRow()
                .swipeActions(edge: .trailing) {
                    if canEdit && !isSelecting {
                        Button(role: .destructive) { actions.delete(entry.block) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .swipeActions(edge: .leading) {
                    if canEdit && !isSelecting {
                        Button { actions.editTimes(entry.block) } label: {
                            Label("Edit", systemImage: "slider.horizontal.3")
                        }
                        .tint(.orange)
                    }
                }
                .contextMenu {
                    if !isSelecting {
                        Button { actions.open(entry.block) } label: { Label("Open Entry", systemImage: "doc.text") }
                        Button { actions.addNote(entry.block) } label: { Label("Add Note", systemImage: "square.and.pencil") }
                        if canEdit {
                            Button { actions.editTimes(entry.block) } label: {
                                Label("Edit Times & Activity", systemImage: "slider.horizontal.3")
                            }
                            Button(role: .destructive) { actions.delete(entry.block) } label: {
                                Label("Delete Entry", systemImage: "trash")
                            }
                        }
                    }
                }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text(filtering ? "Nothing matches this filter" : "Nothing this month")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(filtering ? "Try another month, or clear the filter." : "Entries you log on the Today tab appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - Row styling

private extension View {
    /// Edge-to-edge row with no separators; the time gutter does the aligning.
    func journalRow() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
    }
}
