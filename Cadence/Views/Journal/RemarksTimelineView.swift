// RemarksTimelineView.swift
// Cadence
//
// REDESIGN v2: Search & Tag Browser.
//
// Now that the main timeline shows remarks inline (the journal IS the
// Records tab), this view focuses on what a separate tab does best:
// cross-cutting search and tag-based browsing across all time.
//
// Layout:
//   [Search bar]
//   [Tag chips — horizontal scroll]
//   ── Results ──
//   Grouped by day, each remark shows its parent activity context.
//
// Removed:
// - Full day-by-day journal layout (now in TimelineListView)
// - Intention/reflection placeholders for today (now in TimelineListView)
// - Complex JournalItem enum, JournalListView, JournalRowDispatch
//
// Kept:
// - Global search across all remarks
// - Tag filtering
// - Intention/reflection display (read-only, for historical days)
// - Edit tap targets for intentions/reflections

import SwiftUI
import SwiftData

// MARK: - RemarksTimelineView

struct RemarksTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var selectedTag: String? = nil

    @Query(sort: \Remark.timestamp, order: .reverse) private var allRemarks: [Remark]
    @Query(sort: \DayNote.date, order: .reverse) private var allNotes: [DayNote]
    @Query private var allBlocks: [TimeBlock]

    private var allTags: [String] {
        Array(Set(allRemarks.flatMap { $0.tags })).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tag chip bar (always visible unless searching)
                if searchText.isEmpty && !allTags.isEmpty {
                    tagBar
                }

                // Content
                if !searchText.isEmpty {
                    SearchListView(searchText: searchText)
                } else {
                    filteredRemarksList
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search all remarks…")
        }
    }

    // MARK: - Tag Bar

    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                tagChip(label: "All", isSelected: selectedTag == nil) {
                    withAnimation { selectedTag = nil }
                }

                ForEach(allTags, id: \.self) { tag in
                    tagChip(label: "#\(tag)", isSelected: selectedTag == tag) {
                        withAnimation { selectedTag = selectedTag == tag ? nil : tag }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func tagChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption).fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.blue.opacity(0.15) : Color(.systemGray5))
                .foregroundStyle(isSelected ? .blue : .secondary)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtered Remarks List

    private var blockLookup: [UUID: TimeBlock] {
        Dictionary(uniqueKeysWithValues: allBlocks.compactMap { ($0.id, $0) })
    }

    private var filteredRemarks: [Remark] {
        guard let tag = selectedTag else { return allRemarks }
        return allRemarks.filter { $0.tags.contains(tag) }
    }

    private var groupedByDay: [(label: String, remarks: [Remark], note: DayNote?)] {
        let cal = Calendar.current

        let notesByDay = Dictionary(
            allNotes.map { (cal.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { a, _ in a }
        )

        let grouped = Dictionary(grouping: filteredRemarks) { cal.startOfDay(for: $0.timestamp) }

        var allDays = Set(grouped.keys)
        // Include days with notes if no tag filter
        if selectedTag == nil {
            for note in allNotes where !note.intention.isEmpty || !note.reflection.isEmpty {
                allDays.insert(cal.startOfDay(for: note.date))
            }
        }

        return allDays.sorted(by: >).compactMap { dayStart -> (String, [Remark], DayNote?)? in
            let rawRemarks = grouped[dayStart] ?? []
            
            // Refactored sorting logic applied here
            let dayRemarks = rawRemarks.sorted { a, b in
                let blockA = blockLookup[a.timeBlockID]
                let blockB = blockLookup[b.timeBlockID]
                
                let actA = blockA?.startTime ?? a.timestamp
                let actB = blockB?.startTime ?? b.timestamp
                
                if abs(actA.timeIntervalSince(actB)) > 0.1 {
                    return actA > actB
                }
                return a.timestamp > b.timestamp
            }
            
            let note = notesByDay[dayStart]

            // Skip empty days when tag-filtering
            if selectedTag != nil && dayRemarks.isEmpty { return nil }
            // Skip days with neither remarks nor notes
            if dayRemarks.isEmpty && (note == nil || (note!.intention.isEmpty && note!.reflection.isEmpty)) { return nil }

            let label: String
            if cal.isDateInToday(dayStart) { label = "Today" }
            else if cal.isDateInYesterday(dayStart) { label = "Yesterday" }
            else { label = dayStart.formatted(date: .abbreviated, time: .omitted) }

            return (label, dayRemarks, note)
        }
    }

    @ViewBuilder
    private var filteredRemarksList: some View {
        if groupedByDay.isEmpty {
            emptyState
        } else {
            List {
                ForEach(groupedByDay, id: \.label) { group in
                    Section(header: Text(group.label).fontWeight(.semibold).textCase(nil)) {
                        // Reflection (if present and no tag filter)
                        if selectedTag == nil, let note = group.note, !note.reflection.isEmpty {
                            compactBookend(icon: "moon.stars.fill", tint: .indigo,
                                           label: "Reflection", text: note.reflection)
                        }

                        // Remarks
                        ForEach(group.remarks) { remark in
                            remarkRow(remark)
                        }
                        .onDelete { offsets in
                            for i in offsets { modelContext.delete(group.remarks[i]) }
                            try? modelContext.save()
                        }

                        // Intention (if present and no tag filter)
                        if selectedTag == nil, let note = group.note, !note.intention.isEmpty {
                            compactBookend(icon: "sun.horizon.fill", tint: .orange,
                                           label: "Intention", text: note.intention)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Remark Row

    private func remarkRow(_ remark: Remark) -> some View {
        let block = blockLookup[remark.timeBlockID]

        return HStack(alignment: .top, spacing: 10) {
            // Activity context bar
            if let block {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(hex: block.activityColor))
                    .frame(width: 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Activity name + time
                HStack(alignment: .firstTextBaseline) {
                    if let block {
                        Text(block.activityName)
                            .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(remark.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }

                // Remark text
                Text(remark.displayText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // Tags
                if !remark.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(remark.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundStyle(.blue.opacity(0.7))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.08))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Compact Bookend Row

    private func compactBookend(icon: String, tint: Color, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint.opacity(0.6))
                .font(.caption)
                .padding(.top, 2)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2).fontWeight(.semibold).foregroundStyle(tint.opacity(0.7))
                Text(text)
                    .font(.subheadline).foregroundStyle(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 3)
        .listRowBackground(tint.opacity(0.03))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32)).foregroundStyle(.quaternary)
            if selectedTag != nil {
                Text("No remarks with this tag")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Clear filter") { selectedTag = nil }
                    .font(.caption)
            } else {
                Text("No remarks yet")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Add notes to your activities from the Records tab")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
