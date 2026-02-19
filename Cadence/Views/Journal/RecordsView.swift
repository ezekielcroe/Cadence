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
    @State private var prefilledGap: ComputedGap? = nil // FIX: Track intended gap fill

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

    // MARK: - Undo System
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

    private var isViewingCurrentMonth: Bool {
        let cal = Calendar.current
        return cal.isDate(currentMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {

                    // 1. Month Navigator
                    if searchText.isEmpty {
                        monthNavigator
                    }

                    // 2. Persistent Filter Bar
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
                            onDeleteBlock: { block in recordUndo(for: block) },
                            onFillGap: { gap in
                                prefilledGap = gap
                                showingAddBlock = true
                            }
                        )
                        .id(currentMonth)
                    }
                }

                // 4. Undo Banner
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
                    prefilledGap: prefilledGap,
                    conflictDetector: conflictDetector ?? ConflictDetector(modelContext: modelContext),
                    onSave: {
                        try? modelContext.save()
                        prefilledGap = nil
                    }
                )
                .onDisappear { prefilledGap = nil } // Clear gap state when dismissed
            }
        }
        .onAppear {
            conflictDetector = ConflictDetector(modelContext: modelContext)
        }
    }

    // MARK: - Month Navigator
    private var monthNavigator: some View {
        HStack {
            Button(action: { changeMonth(by: -1) }) {
                Image(systemName: "chevron.left")
                    .padding(8)
            }

            Spacer()

            if isViewingCurrentMonth {
                Text(currentMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .monospacedDigit()
                    .id(currentMonth)
                    .transition(.push(from: .top))
            } else {
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

    // MARK: - Persistent Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Activity filter chip - Using Menu
                Menu {
                    Button("All Activities") { selectedActivity = nil }
                    Divider()
                    ForEach(allActivityNames, id: \.self) { name in
                        Button(name) { selectedActivity = name }
                    }
                } label: {
                    FilterChipLabel(
                        icon: "figure.run",
                        label: selectedActivity ?? "Activity",
                        isActive: selectedActivity != nil
                    )
                }

                // Tag filter chip - Using Menu
                if !allTags.isEmpty {
                    Menu {
                        Button("All Tags") { selectedTag = nil }
                        Divider()
                        ForEach(allTags, id: \.self) { tag in
                            Button("#\(tag)") { selectedTag = tag }
                        }
                    } label: {
                        FilterChipLabel(
                            icon: "tag",
                            label: selectedTag.map { "#\($0)" } ?? "Tags",
                            isActive: selectedTag != nil
                        )
                    }
                }

                // Gap overview chip - Direct toggle
                Button {
                    withAnimation { gapOverviewMode.toggle() }
                } label: {
                    FilterChipLabel(
                        icon: "exclamationmark.triangle",
                        label: "Gaps",
                        isActive: gapOverviewMode
                    )
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

    // MARK: - Undo Recording

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

    private func recordUndo(for block: TimeBlock) {
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
            if undoStack.count > 10 { undoStack.removeFirst() }
            showingUndoBanner = true
        }

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

// MARK: - Filter Chip Component

struct FilterChipLabel: View {
    let icon: String
    let label: String
    let isActive: Bool

    var body: some View {
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
}


