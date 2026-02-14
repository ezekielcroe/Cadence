import SwiftUI
import SwiftData

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TimeBlock.startTime, order: .reverse) private var allTimeBlocks: [TimeBlock]
    @Query(sort: \Remark.timestamp,    order: .forward)  private var allRemarks:    [Remark]

    // MARK: - Filter & Search State
    @State private var searchText       = ""
    @State private var selectedActivity: String? = nil
    @State private var selectedTag: String?      = nil
    @State private var showingFilters   = false
    @State private var showArchived     = false

    // MARK: - Edit State
    @State private var selectedBlock:     TimeBlock?
    @State private var conflictDetector:  ConflictDetector?
    @State private var gapToResolve:      ComputedGap?

    // MARK: - Multi-Select
    @State private var isSelectionMode   = false
    @State private var selectedBlockIDs: Set<UUID> = []

    // MARK: - Error / Sheet State
    @State private var showingMergeError = false
    @State private var mergeErrorMessage = ""
    @State private var showingAddBlock   = false

    private let editCutoffDays = 3

    // MARK: - Derived: Remarks

    private var remarksByBlockID: [UUID: [Remark]] {
        Dictionary(grouping: allRemarks) { $0.timeBlockID }
    }

    private var allTags: [String] {
        Array(Set(allRemarks.flatMap { $0.tags })).sorted()
    }

    // MARK: - Derived: Filtered Blocks

    var filteredActivityBlocks: [TimeBlock] {
        var blocks = allTimeBlocks.filter { $0.activityID != nil }

        if !showArchived {
            let cutoff = Calendar.current.date(byAdding: .day, value: -editCutoffDays, to: Date())!
            blocks = blocks.filter { $0.startTime > cutoff }
        }

        if let selected = selectedActivity {
            blocks = blocks.filter { $0.activityName == selected }
        }

        if let tag = selectedTag {
            let matchingIDs = Set(allRemarks.filter { $0.tags.contains(tag) }.map { $0.timeBlockID })
            blocks = blocks.filter { matchingIDs.contains($0.id) }
        }

        if !searchText.isEmpty {
            let matchingRemarkBlockIDs = Set(
                allRemarks
                    .filter { $0.text.localizedCaseInsensitiveContains(searchText) }
                    .map { $0.timeBlockID }
            )
            blocks = blocks.filter {
                $0.activityName.localizedCaseInsensitiveContains(searchText) ||
                matchingRemarkBlockIDs.contains($0.id)
            }
        }

        return blocks
    }

    // MARK: - Derived: Grouped Timeline

    var groupedTimeline: [String: [TimelineItem]] {
        let calendar         = Calendar.current
        let canComputeGaps   = selectedActivity == nil && searchText.isEmpty && selectedTag == nil

        let grouped = Dictionary(grouping: filteredActivityBlocks) { block -> String in
            if calendar.isDateInToday(block.startTime)     { return "Today" }
            if calendar.isDateInYesterday(block.startTime) { return "Yesterday" }
            return block.startTime.formatted(date: .abbreviated, time: .omitted)
        }

        var result: [String: [TimelineItem]] = [:]

        for (dayLabel, dayBlocks) in grouped {
            let sorted = dayBlocks.sorted { $0.startTime < $1.startTime }
            guard let first = sorted.first else { continue }

            let dayStart       = calendar.startOfDay(for: first.startTime)
            let calendarDayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let isToday        = calendar.isDateInToday(first.startTime)

            // Extend end past midnight if any block ends later
            let latestBlockEnd = sorted.compactMap { $0.endTime }.max() ?? calendarDayEnd
            let rawDayEnd: Date = isToday
                ? min(Date(), max(calendarDayEnd, latestBlockEnd))
                : max(calendarDayEnd, latestBlockEnd)

            // Advance gap start past overnight coverage from the previous day
            let effectiveStart = overnightCoverageEnd(before: dayStart) ?? dayStart

            let gaps: [ComputedGap] = canComputeGaps
                ? GapCalculator.computeGaps(in: sorted, from: effectiveStart, to: rawDayEnd)
                : []

            var items: [TimelineItem] = sorted.map { .activity($0) }
            for gap in gaps { items.append(.gap(gap)) }
            items.sort { $0.startTime > $1.startTime }

            result[dayLabel] = items
        }
        return result
    }

    // MARK: - Derived: Section Keys (newest first)

    var sectionKeys: [String] {
        groupedTimeline.keys.sorted { lhs, rhs in
            if lhs == "Today"     { return true  }
            if rhs == "Today"     { return false }
            if lhs == "Yesterday" { return true  }
            if rhs == "Yesterday" { return false }
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d, yyyy"
            let d1 = fmt.date(from: lhs) ?? .distantPast
            let d2 = fmt.date(from: rhs) ?? .distantPast
            return d1 > d2
        }
    }

    // MARK: - Derived: Gap Summary (for the banner)

    var totalUnresolvedGapCount: Int {
        groupedTimeline.values.flatMap { $0 }
            .filter { if case .gap = $0 { return true } else { return false } }
            .count
    }

    var totalUnresolvedGapDuration: TimeInterval {
        groupedTimeline.values.flatMap { $0 }.compactMap { item -> TimeInterval? in
            if case .gap(let g) = item { return g.duration }
            return nil
        }.reduce(0, +)
    }

    var firstUnresolvedGap: ComputedGap? {
        for key in sectionKeys {
            if let items = groupedTimeline[key] {
                for item in items {
                    if case .gap(let g) = item { return g }
                }
            }
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    headerSection

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

                if isSelectionMode {
                    BulkActionToolbar(
                        count:    selectedBlockIDs.count,
                        onMerge:  mergeSelected,
                        onDelete: deleteSelected,
                        onCancel: { isSelectionMode = false; selectedBlockIDs.removeAll() }
                    )
                }
            }
            .navigationTitle("Records")
            .searchable(text: $searchText, prompt: "Search activities, remarks, or #tags")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelectionMode ? "Done" : "Select") {
                        isSelectionMode.toggle()
                        selectedBlockIDs.removeAll()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddBlock = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Show Archived", isOn: $showArchived)
                        Divider()
                        Button("Filter…") { showingFilters = true }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .symbolVariant(selectedActivity != nil || selectedTag != nil ? .fill : .none)
                    }
                }
            }
            .sheet(item: $selectedBlock) { block in
                BlockEditSheet(
                    block: block,
                    conflictDetector: conflictDetector ?? ConflictDetector(modelContext: modelContext),
                    onSave: { try? modelContext.save() }
                )
            }
            .sheet(item: $gapToResolve) { gap in
                GapResolverSheet(gap: gap) { }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingFilters) {
                FiltersView(
                    selectedActivity: $selectedActivity,
                    selectedTag:      $selectedTag,
                    activities:       Array(Set(filteredActivityBlocks.map { $0.activityName })).sorted(),
                    allTags:          allTags
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingAddBlock) {
                AddBlockSheet(
                    date:             Date(),
                    conflictDetector: conflictDetector ?? ConflictDetector(modelContext: modelContext),
                    onSave:           { try? modelContext.save() }
                )
            }
            .alert("Cannot Merge", isPresented: $showingMergeError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(mergeErrorMessage)
            }
        }
        .onAppear { conflictDetector = ConflictDetector(modelContext: modelContext) }
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        if let tag = selectedTag {
            HStack {
                Image(systemName: "tag.fill").foregroundStyle(.blue).font(.caption)
                Text("#\(tag)").foregroundStyle(.blue).font(.subheadline)
                Spacer()
                Button { selectedTag = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .listRowSeparator(Visibility.hidden)
            .listRowBackground(Color.blue.opacity(0.05))
        }

        if totalUnresolvedGapCount > 0 {
            GapActionBanner(
                gapCount:      totalUnresolvedGapCount,
                totalDuration: totalUnresolvedGapDuration
            ) {
                if let first = firstUnresolvedGap { gapToResolve = first }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(Visibility.hidden)
        } else if !filteredActivityBlocks.isEmpty && searchText.isEmpty && selectedTag == nil {
            HStack {
                Spacer()
                Label("Timeline Complete", systemImage: "checkmark.seal.fill")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                Spacer()
            }
            .listRowSeparator(Visibility.hidden)
            .listRowBackground(Color.clear)
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
        let blockID = block.id
        for remark in allRemarks where remark.timeBlockID == blockID {
            modelContext.delete(remark)
        }
        modelContext.delete(block)
        try? modelContext.save()
    }

    private func deleteSelected() {
        let toDelete = allTimeBlocks.filter { selectedBlockIDs.contains($0.id) }
        let ids = Set(toDelete.map { $0.id })
        for remark in allRemarks where ids.contains(remark.timeBlockID) {
            modelContext.delete(remark)
        }
        for block in toDelete { modelContext.delete(block) }
        try? modelContext.save()
        isSelectionMode = false
        selectedBlockIDs.removeAll()
    }

    private func mergeSelected() {
        let editor = TimeBlockEditor(modelContext: modelContext)
        let blocksToMerge = allTimeBlocks
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
            isSelectionMode = false
            selectedBlockIDs.removeAll()
        } catch {
            mergeErrorMessage = error.localizedDescription
            showingMergeError = true
        }
    }

    // MARK: - Overnight Coverage Helper
    //
    // Returns the endTime of the latest block that started on the previous
    // calendar day and ended after `dayStart` (i.e. an overnight block).
    // Used to advance the gap-calculation start so morning hours already
    // covered by sleep don't appear as untracked gaps.

    private func overnightCoverageEnd(before dayStart: Date) -> Date? {
        let calendar     = Calendar.current
        let prevDayStart = calendar.date(byAdding: .day, value: -1, to: dayStart)!

        let overnightEnds: [Date] = allTimeBlocks.compactMap { block in
            guard block.activityID != nil            else { return nil }
            guard block.startTime >= prevDayStart    else { return nil }
            guard block.startTime <  dayStart        else { return nil }
            guard let end = block.endTime            else { return nil }
            guard end > dayStart                     else { return nil }
            return end
        }
        return overnightEnds.max()
    }
}

// MARK: - Gap Action Banner

struct GapActionBanner: View {
    let gapCount:      Int
    let totalDuration: TimeInterval
    let onReview:      () -> Void

    var body: some View {
        Button(action: onReview) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Unaccounted Time")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(gapCount) gap\(gapCount == 1 ? "" : "s") · \(totalDuration.formattedDuration) total")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Review").fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.2))
                .cornerRadius(8)
            }
            .padding()
            .background(Color.orange)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bulk Action Toolbar

struct BulkActionToolbar: View {
    let count:    Int
    let onMerge:  () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Text("\(count) selected")
                    .font(.subheadline).fontWeight(.medium)
                Spacer()
                HStack(spacing: 20) {
                    Button(action: onMerge) {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.merge")
                            Text("Merge").font(.caption2)
                        }
                    }
                    .disabled(count < 2)

                    Button(role: .destructive, action: onDelete) {
                        VStack(spacing: 2) {
                            Image(systemName: "trash")
                            Text("Delete").font(.caption2)
                        }
                    }
                    .disabled(count == 0)
                }
            }
            .padding()
            .background(.regularMaterial)
        }
    }
}

// MARK: - Filters View

struct FiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedActivity: String?
    @Binding var selectedTag:      String?
    let activities: [String]
    let allTags:    [String]

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    Picker("Filter by Activity", selection: $selectedActivity) {
                        Text("All Activities").tag(nil as String?)
                        ForEach(activities, id: \.self) { activity in
                            Text(activity).tag(activity as String?)
                        }
                    }
                    .pickerStyle(.inline)
                }

                if !allTags.isEmpty {
                    Section("Tag") {
                        Picker("Filter by Tag", selection: $selectedTag) {
                            Text("All Tags").tag(nil as String?)
                            ForEach(allTags, id: \.self) { tag in
                                Label("#\(tag)", systemImage: "tag").tag(tag as String?)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") {
                        selectedActivity = nil
                        selectedTag      = nil
                    }
                    .disabled(selectedActivity == nil && selectedTag == nil)
                }
            }
        }
    }
}
