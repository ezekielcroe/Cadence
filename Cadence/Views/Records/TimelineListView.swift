// TimelineListView.swift
// Cadence
//
// REFACTORED: Adds Today visual timeline (Fix #2), Gap Overview mode (Fix #3),
// long-press auto-select (Fix #5), smart selection (Fix #5), and
// swipe-right for inline remark (Fix #1).

import SwiftUI
import SwiftData

struct TimelineListView: View {
    @Environment(\.modelContext) private var modelContext

    // MARK: - Queries
    @Query private var blocks: [TimeBlock]
    @Query private var remarks: [Remark]
    @Query private var schedules: [TimeBlockRule]

    // MARK: - State Bindings
    @Binding var selectedBlock: TimeBlock?
    @Binding var isSelectionMode: Bool
    @Binding var selectedBlockIDs: Set<UUID>

    // MARK: - Filter State
    let selectedActivity: String?
    let selectedTag: String?
    let showArchived: Bool
    let gapOverviewMode: Bool

    // Undo callback
    var onDeleteBlock: ((TimeBlock) -> Void)?

    // MARK: - Local State
    @State private var gapToResolve: ComputedGap?
    @State private var conflictDetector: ConflictDetector?
    @State private var showingMergeError = false
    @State private var mergeErrorMessage = ""

    // Inline remark state (Fix #1 — swipe right)
    @State private var inlineRemarkBlockID: UUID?
    @State private var inlineRemarkText = ""
    @FocusState private var inlineRemarkFocused: Bool

    // MARK: - Initialization
    init(
        startDate: Date,
        endDate: Date,
        selectedBlock: Binding<TimeBlock?>,
        isSelectionMode: Binding<Bool>,
        selectedBlockIDs: Binding<Set<UUID>>,
        selectedActivity: String?,
        selectedTag: String?,
        showArchived: Bool,
        gapOverviewMode: Bool = false,
        onDeleteBlock: ((TimeBlock) -> Void)? = nil
    ) {
        _selectedBlock = selectedBlock
        _isSelectionMode = isSelectionMode
        _selectedBlockIDs = selectedBlockIDs
        self.selectedActivity = selectedActivity
        self.selectedTag = selectedTag
        self.showArchived = showArchived
        self.gapOverviewMode = gapOverviewMode
        self.onDeleteBlock = onDeleteBlock

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

        return result
    }

    // MARK: - Timeline Generation

    var groupedTimeline: [String: [TimelineItem]] {
        let calendar = Calendar.current
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

    // MARK: - Section gap info (Fix #3)

    private func gapInfo(for section: String) -> (count: Int, duration: TimeInterval)? {
        guard let items = groupedTimeline[section] else { return nil }
        let gaps = items.compactMap { item -> ComputedGap? in
            if case .gap(let g) = item { return g }
            return nil
        }
        guard !gaps.isEmpty else { return nil }
        return (gaps.count, gaps.reduce(0) { $0 + $1.duration })
    }

    // MARK: - Body

    var body: some View {
        List {
            // Gap Banner
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

            // Smart Selection Bar (Fix #5)
            if isSelectionMode {
                smartSelectionBar
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            ForEach(sectionKeys, id: \.self) { section in
                Section {
                    // Today section gets visual timeline (Fix #2)
                    if section == "Today", !gapOverviewMode {
                        todayTimelineSection(items: groupedTimeline[section] ?? [])
                    }

                    // Standard list rows
                    ForEach(groupedTimeline[section] ?? []) { item in
                        switch item {
                        case .activity(let block):
                            if gapOverviewMode {
                                // Fix #3: Collapsed activity rows in gap overview
                                compactActivityRow(block: block)
                            } else {
                                // Standard row with inline remark support
                                activityRow(block: block)
                            }

                        case .gap(let gap):
                            if gapOverviewMode {
                                // Fix #3: Expanded gap cards
                                expandedGapCard(gap: gap)
                            } else {
                                ComputedGapRow(gap: gap) { gapToResolve = gap }
                                    .swipeActions(edge: .leading) {
                                        Button("Resolve") { gapToResolve = gap }
                                            .tint(.orange)
                                    }
                            }
                        }
                    }
                } header: {
                    // Fix #3: Gap count in section header
                    HStack {
                        Text(section)
                        Spacer()
                        if let info = gapInfo(for: section) {
                            Text("\(info.count) gap\(info.count == 1 ? "" : "s") · \(info.duration.formattedDuration)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
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

    // MARK: - Today Visual Timeline (Fix #2)

    @ViewBuilder
    private func todayTimelineSection(items: [TimelineItem]) -> some View {
        let sortedItems = items.sorted { $0.startTime < $1.startTime }

        VStack(spacing: 0) {
            ForEach(sortedItems) { item in
                HStack(alignment: .top, spacing: 0) {
                    // Left: Time label
                    Text(item.startTime.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                        .padding(.trailing, 8)

                    // Right: Proportional block
                    switch item {
                    case .activity(let block):
                        let height = max(24, min(120, CGFloat(block.duration / 60)))
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: block.activityColor))
                                .frame(width: 4)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.activityName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(block.duration.formattedDuration)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: block.activityColor).opacity(0.1))
                        .cornerRadius(6)
                        .onTapGesture { handleBlockTap(block) }

                    case .gap(let gap):
                        let height = max(20, min(60, CGFloat(gap.duration / 60)))
                        HStack(spacing: 6) {
                            Rectangle()
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                                .foregroundStyle(Color.orange.opacity(0.5))
                                .frame(width: 4)

                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text("Gap · \(gap.duration.formattedDuration)")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }

                            Spacer()

                            Button("Fill") { gapToResolve = gap }
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.05))
                        .cornerRadius(6)
                    }
                }
                .padding(.vertical, 1)
            }

            // "Now" indicator
            HStack(spacing: 0) {
                Text("now")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .fontWeight(.semibold)
                    .frame(width: 50, alignment: .trailing)
                    .padding(.trailing, 8)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Rectangle()
                        .fill(Color.green.opacity(0.3))
                        .frame(height: 1)
                }
            }
            .padding(.vertical, 4)
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        .listRowSeparator(.hidden)
    }

    // MARK: - Standard Activity Row with Swipe & Long-Press

    @ViewBuilder
    private func activityRow(block: TimeBlock) -> some View {
        VStack(spacing: 0) {
            AuditRow(
                block: block,
                remarks: remarksByBlockID[block.id] ?? [],
                isSelected: selectedBlockIDs.contains(block.id),
                isSelectionMode: isSelectionMode,
                isEditable: true,
                onTap: { handleBlockTap(block) }
            )
            // Fix #5: Long-press to auto-enter selection mode
            .onLongPressGesture {
                if !isSelectionMode {
                    isSelectionMode = true
                    selectedBlockIDs.removeAll()
                }
                selectedBlockIDs.insert(block.id)
            }
            // Fix #1: Inline remark field
            .swipeActions(edge: .leading) {
                Button {
                    withAnimation {
                        inlineRemarkBlockID = block.id
                        inlineRemarkText = ""
                        inlineRemarkFocused = true
                    }
                } label: {
                    Label("Remark", systemImage: "note.text.badge.plus")
                }
                .tint(.blue)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    onDeleteBlock?(block)
                    deleteBlock(block)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            // Inline remark input (Fix #1)
            if inlineRemarkBlockID == block.id {
                inlineRemarkField(for: block)
            }
        }
    }

    // MARK: - Inline Remark Field (Fix #1)

    private func inlineRemarkField(for block: TimeBlock) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.caption)
                .foregroundStyle(.blue)

            TextField("Quick remark… (#tags)", text: $inlineRemarkText, axis: .vertical)
                .font(.subheadline)
                .focused($inlineRemarkFocused)
                .lineLimit(1...3)
                .submitLabel(.done)
                .onSubmit { saveInlineRemark(for: block) }

            if !inlineRemarkText.isEmpty {
                Button {
                    saveInlineRemark(for: block)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }

            Button {
                withAnimation {
                    inlineRemarkBlockID = nil
                    inlineRemarkText = ""
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.05))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func saveInlineRemark(for block: TimeBlock) {
        let trimmed = inlineRemarkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let remark = Remark(timeBlockID: block.id, text: trimmed)
        modelContext.insert(remark)
        try? modelContext.save()

        withAnimation {
            inlineRemarkBlockID = nil
            inlineRemarkText = ""
        }
    }

    // MARK: - Compact Activity Row (Gap Overview — Fix #3)

    private func compactActivityRow(block: TimeBlock) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: block.activityColor))
                .frame(width: 3, height: 20)

            Text(block.activityName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(block.duration.formattedDuration)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .listRowBackground(Color(.systemBackground))
        .onTapGesture { handleBlockTap(block) }
    }

    // MARK: - Expanded Gap Card (Gap Overview — Fix #3)

    private func expandedGapCard(gap: ComputedGap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Untracked Gap")
                        .font(.headline)
                    Text(
                        "\(gap.start.formatted(date: .omitted, time: .shortened)) → " +
                        "\(gap.end.formatted(date: .omitted, time: .shortened))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(gap.duration.formattedDuration)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(.orange)
            }

            // Quick action buttons
            HStack(spacing: 12) {
                Button {
                    gapToResolve = gap
                } label: {
                    Label("Assign Activity", systemImage: "plus.circle")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08))
        .cornerRadius(12)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
    }

    // MARK: - Smart Selection Bar (Fix #5)

    private var smartSelectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Select all today
                Button {
                    let calendar = Calendar.current
                    let todayIDs = blocks
                        .filter { calendar.isDateInToday($0.startTime) }
                        .map { $0.id }
                    selectedBlockIDs.formUnion(todayIDs)
                } label: {
                    Label("All Today", systemImage: "calendar")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                }
                .buttonStyle(.plain)

                // Select all of same activity (if 1 is selected)
                if let firstSelectedID = selectedBlockIDs.first,
                   let firstBlock = blocks.first(where: { $0.id == firstSelectedID }) {
                    Button {
                        let sameActivity = blocks
                            .filter { $0.activityName == firstBlock.activityName }
                            .map { $0.id }
                        selectedBlockIDs.formUnion(sameActivity)
                    } label: {
                        Label("All \(firstBlock.activityName)", systemImage: "square.stack")
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }

                // Select none
                Button {
                    selectedBlockIDs.removeAll()
                } label: {
                    Label("Clear", systemImage: "xmark")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color.blue.opacity(0.05))
    }

    // MARK: - Actions

    private func handleBlockTap(_ block: TimeBlock) {
        if isSelectionMode {
            if selectedBlockIDs.contains(block.id) {
                selectedBlockIDs.remove(block.id)
            } else {
                selectedBlockIDs.insert(block.id)
            }
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

        HistoryManager.shared.invalidateDate(dateToInvalidate, in: modelContext)
    }

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
