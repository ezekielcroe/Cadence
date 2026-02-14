import SwiftUI
import SwiftData

struct TimelineListView: View {
    @Environment(\.modelContext) private var modelContext

    // MARK: - Queries
    // The main data source, strictly limited to the provided date range.
    @Query private var blocks: [TimeBlock]
    @Query private var remarks: [Remark]
    @Query private var schedules: [TimeBlockRule] // Needed for gap calculation (paused modes)

    // MARK: - State Bindings (passed from Parent)
    @Binding var selectedBlock: TimeBlock?
    @Binding var isSelectionMode: Bool
    @Binding var selectedBlockIDs: Set<UUID>
    
    // MARK: - Filter State (passed from Parent)
    // NOTE: 'searchText' is removed here. Search is now handled by SearchListView.
    let selectedActivity: String?
    let selectedTag: String?
    let showArchived: Bool

    // MARK: - Local State
    @State private var gapToResolve: ComputedGap?
    @State private var conflictDetector: ConflictDetector?
    
    // Error Handling
    @State private var showingMergeError = false
    @State private var mergeErrorMessage = ""

    // MARK: - Initialization
    init(
        startDate: Date,
        endDate: Date,
        selectedBlock: Binding<TimeBlock?>,
        isSelectionMode: Binding<Bool>,
        selectedBlockIDs: Binding<Set<UUID>>,
        // searchText: String,  <-- REMOVED
        selectedActivity: String?,
        selectedTag: String?,
        showArchived: Bool
    ) {
        _selectedBlock = selectedBlock
        _isSelectionMode = isSelectionMode
        _selectedBlockIDs = selectedBlockIDs
        // self.searchText = searchText <-- REMOVED
        self.selectedActivity = selectedActivity
        self.selectedTag = selectedTag
        self.showArchived = showArchived

        // Fetch Blocks in Range
        _blocks = Query(
            filter: #Predicate { block in
                block.startTime >= startDate && block.startTime < endDate && block.activityID != nil
            },
            sort: \.startTime,
            order: .reverse
        )
    }

    // MARK: - Derived Data

    private var remarksByBlockID: [UUID: [Remark]] {
        let loadedIDs = Set(blocks.map { $0.id })
        let relevant = remarks.filter { loadedIDs.contains($0.timeBlockID) }
        return Dictionary(grouping: relevant) { $0.timeBlockID }
    }

    private var filteredBlocks: [TimeBlock] {
        var result = blocks

        if let selected = selectedActivity {
            result = result.filter { $0.activityName == selected }
        }

        if let tag = selectedTag {
            let matchingIDs = Set(remarks.filter { $0.tags.contains(tag) }.map { $0.timeBlockID })
            result = result.filter { matchingIDs.contains($0.id) }
        }
        
        // Note: searchText filtering logic is completely removed from here.
        return result
    }

    // MARK: - Timeline Generation

    var groupedTimeline: [String: [TimelineItem]] {
        let calendar = Calendar.current
        
        // We only compute gaps if we aren't filtering the view
        let canComputeGaps = selectedActivity == nil && selectedTag == nil

        let grouped = Dictionary(grouping: filteredBlocks) { block -> String in
            if calendar.isDateInToday(block.startTime) { return "Today" }
            if calendar.isDateInYesterday(block.startTime) { return "Yesterday" }
            return block.startTime.formatted(date: .abbreviated, time: .omitted)
        }

        var result: [String: [TimelineItem]] = [:]

        for (dayLabel, dayBlocks) in grouped {
            let sorted = dayBlocks.sorted { $0.startTime < $1.startTime }
            guard let first = sorted.first else { continue }

            let dayStart = calendar.startOfDay(for: first.startTime)
            let calendarDayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let isToday = calendar.isDateInToday(first.startTime)

            let latestBlockEnd = sorted.compactMap { $0.endTime }.max() ?? calendarDayEnd
            let rawDayEnd: Date = isToday
                ? min(Date(), max(calendarDayEnd, latestBlockEnd))
                : max(calendarDayEnd, latestBlockEnd)

            // Resolve overhead coverage locally
            let effectiveStart = overnightCoverageEnd(before: dayStart) ?? dayStart

            let gaps: [ComputedGap] = canComputeGaps
                ? GapCalculator.computeGaps(in: sorted, rules: schedules, from: effectiveStart, to: rawDayEnd)
                : []

            var items: [TimelineItem] = sorted.map { .activity($0) }
            for gap in gaps { items.append(.gap(gap)) }
            items.sort { $0.startTime > $1.startTime }

            result[dayLabel] = items
        }
        return result
    }

    var sectionKeys: [String] {
        groupedTimeline.keys.sorted { lhs, rhs in
            if lhs == "Today" { return true }
            if rhs == "Today" { return false }
            if lhs == "Yesterday" { return true }
            if rhs == "Yesterday" { return false }
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d, yyyy"
            let d1 = fmt.date(from: lhs) ?? .distantPast
            let d2 = fmt.date(from: rhs) ?? .distantPast
            return d1 > d2
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            // Gap Banner (only for visible month)
            if let gapSummary = calculateGapSummary() {
                GapActionBanner(
                    gapCount: gapSummary.count,
                    totalDuration: gapSummary.duration
                ) {
                    if let first = gapSummary.first { gapToResolve = first }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(Visibility.hidden)
            }

            ForEach(sectionKeys, id: \.self) { section in
                Section(header: Text(section)) {
                    ForEach(groupedTimeline[section] ?? []) { item in
                        switch item {
                        case .activity(let block):
                            AuditRow(
                                block: block,
                                remarks: remarksByBlockID[block.id] ?? [],
                                isSelected: selectedBlockIDs.contains(block.id),
                                isSelectionMode: isSelectionMode,
                                isEditable: true,
                                onTap: { handleBlockTap(block) }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { deleteBlock(block) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                        case .gap(let gap):
                            ComputedGapRow(gap: gap) { gapToResolve = gap }
                                .swipeActions(edge: .leading) {
                                    Button("Resolve") { gapToResolve = gap }
                                        .tint(.orange)
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $gapToResolve) { gap in
            GapResolverSheet(gap: gap) { }
                .presentationDetents([.medium, .large])
        }
        .alert("Cannot Merge", isPresented: $showingMergeError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(mergeErrorMessage)
        }
        .onAppear {
            conflictDetector = ConflictDetector(modelContext: modelContext)
        }
    }

    // MARK: - Actions

    private func handleBlockTap(_ block: TimeBlock) {
        if isSelectionMode {
            if selectedBlockIDs.contains(block.id) { selectedBlockIDs.remove(block.id) }
            else { selectedBlockIDs.insert(block.id) }
        } else {
            selectedBlock = block
        }
    }

    private func deleteBlock(_ block: TimeBlock) {
        let dateToInvalidate = block.startTime
        let blockID = block.id
        
        for remark in remarks where remark.timeBlockID == blockID {
            modelContext.delete(remark)
        }
        modelContext.delete(block)
        try? modelContext.save()
        
        // Notify HistoryManager
        HistoryManager.shared.invalidateDate(dateToInvalidate, in: modelContext)
    }
    
    // Explicitly exposed for Parent View to call
    func mergeSelectedBlocks() {
        let editor = TimeBlockEditor(modelContext: modelContext)
        let blocksToMerge = blocks
            .filter { selectedBlockIDs.contains($0.id) }
            .sorted { $0.startTime < $1.startTime }

        guard let firstBlock = blocksToMerge.first,
              let activityID = firstBlock.activityID else {
            mergeErrorMessage = "Cannot merge these blocks."
            showingMergeError = true
            return
        }

        let descriptor = FetchDescriptor<Activity>(predicate: #Predicate { $0.id == activityID })
        guard let targetActivity = try? modelContext.fetch(descriptor).first else {
            mergeErrorMessage = "Could not find the original activity."
            showingMergeError = true
            return
        }

        do {
            try editor.mergeBlocks(blocksToMerge, intoActivity: targetActivity)
            if let date = blocksToMerge.first?.startTime {
                HistoryManager.shared.invalidateDate(date, in: modelContext)
            }
            selectedBlockIDs.removeAll()
        } catch {
            mergeErrorMessage = error.localizedDescription
            showingMergeError = true
        }
    }
    
    func deleteSelectedBlocks() {
        let toDelete = blocks.filter { selectedBlockIDs.contains($0.id) }
        let ids = Set(toDelete.map { $0.id })
        
        for remark in remarks where ids.contains(remark.timeBlockID) {
            modelContext.delete(remark)
        }
        
        // Invalidate history for all affected days
        let affectedDates = Set(toDelete.map { Calendar.current.startOfDay(for: $0.startTime) })
        
        for block in toDelete { modelContext.delete(block) }
        try? modelContext.save()
        
        for date in affectedDates {
            HistoryManager.shared.invalidateDate(date, in: modelContext)
        }
        
        selectedBlockIDs.removeAll()
    }

    // MARK: - Helpers

    private func calculateGapSummary() -> (count: Int, duration: TimeInterval, first: ComputedGap?)? {
        let allItems = groupedTimeline.values.flatMap { $0 }
        let gapItems = allItems.compactMap { item -> ComputedGap? in
            if case .gap(let g) = item { return g }
            return nil
        }
        
        guard !gapItems.isEmpty else { return nil }
        
        let totalDur = gapItems.reduce(0) { $0 + $1.duration }
        return (gapItems.count, totalDur, gapItems.first)
    }

    private func overnightCoverageEnd(before dayStart: Date) -> Date? {
        let calendar = Calendar.current
        let prevDayStart = calendar.date(byAdding: .day, value: -1, to: dayStart)!
        
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime >= prevDayStart && block.startTime < dayStart && block.activityID != nil
            }
        )
        
        guard let prevBlocks = try? modelContext.fetch(descriptor) else { return nil }
        
        return prevBlocks
            .compactMap { $0.endTime }
            .filter { $0 > dayStart }
            .max()
    }
}
