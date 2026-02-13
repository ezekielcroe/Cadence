//
//  RecordsView.swift
//  Cadence
//

import SwiftUI
import SwiftData

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext

    // Activity blocks only — gaps are computed, not fetched
    @Query(sort: \TimeBlock.startTime, order: .reverse) private var allTimeBlocks: [TimeBlock]

    // MARK: - Filter & Search State

    @State private var searchText = ""
    @State private var selectedActivity: String? = nil
    @State private var showingFilters = false
    @State private var showArchived = false

    // MARK: - Edit State

    @State private var selectedBlock: TimeBlock?
    @State private var conflictDetector: ConflictDetector?
    @State private var gapToResolve: ComputedGap?   // Value type — computed, never stored

    // MARK: - Multi-Select State

    @State private var isSelectionMode = false
    @State private var selectedBlockIDs: Set<UUID> = []

    // MARK: - Error State

    @State private var showingMergeError = false
    @State private var mergeErrorMessage = ""

    // MARK: - Constants

    private let editCutoffDays = 3

    // MARK: - Computed Properties

    /// Activity blocks after archive / activity / search filters applied.
    /// Never contains gap, pause, or untracked rows — those no longer exist as stored blocks.
    var filteredActivityBlocks: [TimeBlock] {
        var blocks = allTimeBlocks.filter { $0.activityID != nil }

        if !showArchived {
            let cutoff = Calendar.current.date(byAdding: .day, value: -editCutoffDays, to: Date())!
            blocks = blocks.filter { $0.startTime > cutoff }
        }

        if let selected = selectedActivity {
            blocks = blocks.filter { $0.activityName == selected }
        }

        if !searchText.isEmpty {
            blocks = blocks.filter {
                $0.activityName.localizedCaseInsensitiveContains(searchText) ||
                $0.remarks.localizedCaseInsensitiveContains(searchText)
            }
        }

        return blocks
    }

    /// Timeline items (activities + computed gaps) grouped by day label.
    /// Gaps are only interleaved when no activity or search filter is active,
    /// because filters break the contiguous day coverage required for accurate gap computation.
    var groupedTimeline: [String: [TimelineItem]] {
        let calendar = Calendar.current
        let canComputeGaps = selectedActivity == nil && searchText.isEmpty

        let grouped = Dictionary(grouping: filteredActivityBlocks) { block -> String in
            if calendar.isDateInToday(block.startTime)     { return "Today" }
            if calendar.isDateInYesterday(block.startTime) { return "Yesterday" }
            return block.startTime.formatted(date: .abbreviated, time: .omitted)
        }

        var result: [String: [TimelineItem]] = [:]

        for (dayLabel, dayBlocks) in grouped {
            let sorted = dayBlocks.sorted { $0.startTime < $1.startTime }
            guard let first = sorted.first else { continue }

            let dayStart = calendar.startOfDay(for: first.startTime)
            let dayEnd: Date = calendar.isDateInToday(first.startTime)
                ? Date()
                : calendar.date(byAdding: .day, value: 1, to: dayStart)!

            // Only compute gaps on unfiltered views so coverage is accurate
            let gaps: [ComputedGap] = canComputeGaps
                ? GapCalculator.computeGaps(in: sorted, from: dayStart, to: dayEnd)
                : []

            var items: [TimelineItem] = sorted.map { .activity($0) }
            for gap in gaps { items.append(.gap(gap)) }
            items.sort { $0.startTime < $1.startTime }

            result[dayLabel] = items
        }

        return result
    }

    var sectionKeys: [String] {
        groupedTimeline.keys.sorted { key1, key2 in
            if key1 == "Today"     { return true }
            if key2 == "Today"     { return false }
            if key1 == "Yesterday" { return true }
            if key2 == "Yesterday" { return false }

            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            let d1 = formatter.date(from: key1) ?? .distantPast
            let d2 = formatter.date(from: key2) ?? .distantPast
            return d1 > d2
        }
    }

    /// Total number of computed gap rows across all visible days.
    var totalUnresolvedGapCount: Int {
        groupedTimeline.values
            .flatMap { $0 }
            .filter { if case .gap = $0 { return true } else { return false } }
            .count
    }

    /// Total untracked duration across all visible days (for the banner).
    var totalUnresolvedGapDuration: TimeInterval {
        groupedTimeline.values
            .flatMap { $0 }
            .compactMap { item -> TimeInterval? in
                if case .gap(let g) = item { return g.duration }
                return nil
            }
            .reduce(0, +)
    }

    /// First computed gap across all days, for the banner's "Review" action.
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
                                        isSelected: selectedBlockIDs.contains(block.id),
                                        isSelectionMode: isSelectionMode,
                                        isEditable: true,
                                        onTap: { handleBlockTap(block) }
                                    )
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            deleteBlock(block)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }

                                case .gap(let gap):
                                    ComputedGapRow(gap: gap) {
                                        gapToResolve = gap
                                    }
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
                        count: selectedBlockIDs.count,
                        onMerge: mergeSelected,
                        onDelete: deleteSelected,
                        onCancel: {
                            isSelectionMode = false
                            selectedBlockIDs.removeAll()
                        }
                    )
                }
            }
            .navigationTitle("Records")
            .searchable(text: $searchText, prompt: "Search activities or remarks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelectionMode ? "Done" : "Select") {
                        isSelectionMode.toggle()
                        selectedBlockIDs.removeAll()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // "Hide Pauses" removed — pauses are now inline metadata on activity rows
                        Toggle("Show Archived", isOn: $showArchived)
                        Divider()
                        Button("Filter by Activity...", action: { showingFilters = true })
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .symbolVariant(selectedActivity != nil ? .fill : .none)
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
                // ComputedGap is Identifiable so .sheet(item:) works directly
                GapResolverSheet(gap: gap) { }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingFilters) {
                FiltersView(
                    selectedActivity: $selectedActivity,
                    activities: Array(Set(filteredActivityBlocks.map { $0.activityName })).sorted()
                )
                .presentationDetents([.medium])
            }
            .alert("Cannot Merge", isPresented: $showingMergeError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(mergeErrorMessage)
            }
        }
        .onAppear {
            conflictDetector = ConflictDetector(modelContext: modelContext)
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        if totalUnresolvedGapCount > 0 {
            GapActionBanner(
                gapCount: totalUnresolvedGapCount,
                totalDuration: totalUnresolvedGapDuration
            ) {
                if let first = firstUnresolvedGap {
                    gapToResolve = first
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        } else if !filteredActivityBlocks.isEmpty && searchText.isEmpty {
            HStack {
                Spacer()
                Label("Timeline Complete", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                Spacer()
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
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
        modelContext.delete(block)
        try? modelContext.save()
    }

    private func deleteSelected() {
        let toDelete = allTimeBlocks.filter { selectedBlockIDs.contains($0.id) }
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
            mergeErrorMessage = "Cannot merge these blocks. Make sure they are activity blocks."
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
            try? modelContext.save()
            isSelectionMode = false
            selectedBlockIDs.removeAll()
        } catch {
            mergeErrorMessage = error.localizedDescription
            showingMergeError = true
        }
    }
}

// MARK: - Gap Action Banner

struct GapActionBanner: View {
    let gapCount: Int
    let totalDuration: TimeInterval
    let onReview: () -> Void

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
                    Text("Review")
                        .fontWeight(.semibold)
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
    let count: Int
    let onMerge: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Text("\(count) selected")
                    .font(.subheadline)
                    .fontWeight(.medium)
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
    let activities: [String]

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
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
