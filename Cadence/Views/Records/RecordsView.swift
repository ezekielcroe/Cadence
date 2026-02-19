// RecordsView.swift
// Cadence
//
// REFACTORED: Adds Today quick-jump, persistent filter bar, undo system,
// and gap overview toggle.

import SwiftUI
import SwiftData

// MARK: - Undo Action Model

struct UndoableAction: Identifiable {
    let id = UUID()
    let label: String
    let timestamp: Date
    let restore: () -> Void
}

// MARK: - RecordsView

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext

    // MARK: - Navigation State
    @State private var currentMonth: Date = Date()
    @State private var showArchived = false
    @State private var showingAddBlock = false

    // MARK: - Filter State
    @State private var searchText = ""
    @State private var selectedActivity: String? = nil
    @State private var selectedTag: String? = nil

    // MARK: - Selection & Edit State
    @State private var isSelectionMode = false
    @State private var selectedBlockIDs: Set<UUID> = []
    @State private var selectedBlock: TimeBlock?
    @State private var conflictDetector: ConflictDetector?

    // MARK: - Gap Overview
    @State private var gapOverviewMode = false

    // MARK: - Undo System (Fix #7)
    @State private var undoStack: [UndoableAction] = []
    @State private var showingUndoBanner = false
    @State private var undoBannerTimer: Timer?

    // Filter Helpers
    @Query private var allActivities: [Activity]
    @Query private var allRemarks: [Remark]

    private var allTags: [String] {
        Array(Set(allRemarks.flatMap { $0.tags })).sorted()
    }

    private var allActivityNames: [String] {
        allActivities.map { $0.name }.sorted()
    }

    // MARK: - Date Range Calculation
    private var monthRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth))!
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        return (start, end)
    }

    // MARK: - "Is viewing current month" check (Fix #4)
    private var isViewingCurrentMonth: Bool {
        let cal = Calendar.current
        return cal.isDate(currentMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {

                    // 1. Month Navigator with "Today" button (Fix #4)
                    if searchText.isEmpty {
                        monthNavigator
                    }

                    // 2. Persistent Filter Bar (Fix #8)
                    if searchText.isEmpty {
                        filterBar
                    }

                    // 3. Main Content Area
                    if !searchText.isEmpty {
                        SearchListView(searchText: searchText)
                    } else {
                        TimelineListView(
                            startDate: monthRange.start,
                            endDate: monthRange.end,
                            selectedBlock: $selectedBlock,
                            isSelectionMode: $isSelectionMode,
                            selectedBlockIDs: $selectedBlockIDs,
                            selectedActivity: selectedActivity,
                            selectedTag: selectedTag,
                            showArchived: showArchived,
                            gapOverviewMode: gapOverviewMode,
                            onDeleteBlock: { block in
                                recordUndo(for: block)
                            }
                        )
                        .id(currentMonth)
                    }
                }

                // 4. Bulk Action Toolbar
                if isSelectionMode && searchText.isEmpty {
                    BulkActionToolbar(
                        count: selectedBlockIDs.count,
                        onMerge: mergeSelected,
                        onDelete: deleteSelected,
                        onCancel: {
                            isSelectionMode = false
                            selectedBlockIDs.removeAll()
                        }
                    )
                }

                // 5. Undo Banner (Fix #7)
                if showingUndoBanner, let lastAction = undoStack.last {
                    undoBanner(action: lastAction)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, isSelectionMode ? 80 : 16)
                }
            }
            .navigationTitle("Records")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search remarks history")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if searchText.isEmpty {
                        Button(isSelectionMode ? "Done" : "Select") {
                            isSelectionMode.toggle()
                            selectedBlockIDs.removeAll()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddBlock = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Gap Overview toggle (Fix #3)
                        Toggle(isOn: $gapOverviewMode) {
                            Label("Gap Overview", systemImage: "exclamationmark.triangle")
                        }
                        Divider()
                        Button("Today") { withAnimation { currentMonth = Date() } }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .symbolVariant(
                                (selectedActivity != nil || selectedTag != nil || gapOverviewMode)
                                    ? .fill : .none
                            )
                    }
                }
            }
            .sheet(item: $selectedBlock) { block in
                QuickEditSheet(
                    block: block,
                    conflictDetector: conflictDetector ?? ConflictDetector(modelContext: modelContext),
                    onSave: { try? modelContext.save() }
                )
            }
            .sheet(isPresented: $showingAddBlock) {
                AddBlockSheet(
                    date: currentMonth,
                    conflictDetector: conflictDetector ?? ConflictDetector(modelContext: modelContext),
                    onSave: { try? modelContext.save() }
                )
            }
        }
        .onAppear {
            conflictDetector = ConflictDetector(modelContext: modelContext)
        }
    }

    // MARK: - Month Navigator (Fix #4: Today button)

    private var monthNavigator: some View {
        HStack {
            Button(action: { changeMonth(by: -1) }) {
                Image(systemName: "chevron.left")
                    .padding(8)
            }

            Spacer()

            if isViewingCurrentMonth {
                // Show the month title normally
                Text(currentMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .monospacedDigit()
                    .id(currentMonth)
                    .transition(.push(from: .top))
            } else {
                // Show "Today" jump button when viewing a different month
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentMonth = Date()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentMonth.formatted(.dateTime.month(.abbreviated).year()))
                            .font(.headline)
                            .monospacedDigit()

                        Divider().frame(height: 16)

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption)
                            Text("Today")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.blue)
                    }
                }
                .id(currentMonth)
                .transition(.push(from: .top))
            }

            Spacer()

            Button(action: { changeMonth(by: 1) }) {
                Image(systemName: "chevron.right")
                    .padding(8)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Material.regular)
    }

    // MARK: - Persistent Filter Bar (Fix #8)

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Activity filter chip
                FilterChip(
                    icon: "figure.run",
                    label: selectedActivity ?? "Activity",
                    isActive: selectedActivity != nil
                ) {
                    // Cycle through activities or clear
                    if selectedActivity != nil {
                        selectedActivity = nil
                    } else {
                        // Show inline picker — for simplicity, cycle to first
                        // In production this would show a popover
                    }
                }
                .contextMenu {
                    Button("All Activities") { selectedActivity = nil }
                    Divider()
                    ForEach(allActivityNames, id: \.self) { name in
                        Button(name) { selectedActivity = name }
                    }
                }

                // Tag filter chip
                if !allTags.isEmpty {
                    FilterChip(
                        icon: "tag",
                        label: selectedTag.map { "#\($0)" } ?? "Tags",
                        isActive: selectedTag != nil
                    ) {
                        if selectedTag != nil { selectedTag = nil }
                    }
                    .contextMenu {
                        Button("All Tags") { selectedTag = nil }
                        Divider()
                        ForEach(allTags, id: \.self) { tag in
                            Button("#\(tag)") { selectedTag = tag }
                        }
                    }
                }

                // Gap overview chip (Fix #3)
                FilterChip(
                    icon: "exclamationmark.triangle",
                    label: "Gaps",
                    isActive: gapOverviewMode
                ) {
                    gapOverviewMode.toggle()
                }

                // Clear all
                if selectedActivity != nil || selectedTag != nil || gapOverviewMode {
                    Button {
                        withAnimation {
                            selectedActivity = nil
                            selectedTag = nil
                            gapOverviewMode = false
                        }
                    } label: {
                        Text("Clear")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Undo Banner (Fix #7)

    private func undoBanner(action: UndoableAction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.title3)
                .foregroundStyle(.white)

            Text(action.label)
                .font(.subheadline)
                .foregroundStyle(.white)

            Spacer()

            Button("Undo") {
                withAnimation {
                    action.restore()
                    undoStack.removeLast()
                    showingUndoBanner = !undoStack.isEmpty
                }
            }
            .font(.subheadline)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.25))
            .cornerRadius(8)
        }
        .padding()
        .background(Color.gray.opacity(0.9))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Undo Recording

    private func recordUndo(for block: TimeBlock) {
        // Snapshot the block data before deletion
        let snapshot = (
            activityID: block.activityID,
            activityName: block.activityName,
            activityColor: block.activityColor,
            activitySetID: block.activitySetID,
            startTime: block.startTime,
            endTime: block.endTime,
            stopState: block.stopState,
            pauseCount: block.pauseCount,
            totalPauseDuration: block.totalPauseDuration,
            switchCount: block.switchCount
        )

        // Snapshot remarks
        let blockRemarks = allRemarks.filter { $0.timeBlockID == block.id }
        let remarkSnapshots = blockRemarks.map { r in
            (text: r.text, timestamp: r.timestamp, tags: r.tags)
        }

        let action = UndoableAction(
            label: "Deleted \(snapshot.activityName)",
            timestamp: Date()
        ) { [modelContext] in
            let restored = TimeBlock(
                activityID: snapshot.activityID,
                activityName: snapshot.activityName,
                activityColor: snapshot.activityColor,
                activitySetID: snapshot.activitySetID,
                startTime: snapshot.startTime
            )
            restored.endTime = snapshot.endTime
            restored.stopState = snapshot.stopState
            restored.pauseCount = snapshot.pauseCount
            restored.totalPauseDuration = snapshot.totalPauseDuration
            restored.switchCount = snapshot.switchCount
            modelContext.insert(restored)

            for rs in remarkSnapshots {
                let remark = Remark(timeBlockID: restored.id, text: rs.text, timestamp: rs.timestamp)
                modelContext.insert(remark)
            }
            try? modelContext.save()
            HistoryManager.shared.invalidateDate(snapshot.startTime, in: modelContext)
        }

        withAnimation {
            undoStack.append(action)
            // Cap at 10 items
            if undoStack.count > 10 { undoStack.removeFirst() }
            showingUndoBanner = true
        }

        // Auto-dismiss after 5 seconds
        undoBannerTimer?.invalidate()
        undoBannerTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            withAnimation { showingUndoBanner = false }
        }
    }

    // MARK: - Navigation Actions
    private func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: currentMonth) {
            withAnimation { currentMonth = newDate }
        }
    }

    // MARK: - Bulk Actions
    private func deleteSelected() {
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { selectedBlockIDs.contains($0.id) }
        )
        if let toDelete = try? modelContext.fetch(descriptor) {
            let ids = Set(toDelete.map { $0.id })
            let remarkDesc = FetchDescriptor<Remark>(
                predicate: #Predicate { ids.contains($0.timeBlockID) }
            )
            if let remarks = try? modelContext.fetch(remarkDesc) {
                for r in remarks { modelContext.delete(r) }
            }
            for block in toDelete { modelContext.delete(block) }
            try? modelContext.save()
        }
        isSelectionMode = false
        selectedBlockIDs.removeAll()
    }

    private func mergeSelected() {
        let editor = TimeBlockEditor(modelContext: modelContext)
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { selectedBlockIDs.contains($0.id) },
            sortBy: [SortDescriptor(\.startTime)]
        )

        guard let blocksToMerge = try? modelContext.fetch(descriptor),
              let firstBlock = blocksToMerge.first,
              let activityID = firstBlock.activityID else { return }

        let actDesc = FetchDescriptor<Activity>(predicate: #Predicate { $0.id == activityID })
        guard let targetActivity = try? modelContext.fetch(actDesc).first else { return }

        try? editor.mergeBlocks(blocksToMerge, intoActivity: targetActivity)
        isSelectionMode = false
        selectedBlockIDs.removeAll()
    }
}

// MARK: - Filter Chip Component (Fix #8)

struct FilterChip: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
                if isActive {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.blue.opacity(0.15) : Color(.systemGray6))
            .foregroundStyle(isActive ? .blue : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}


