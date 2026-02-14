// ============================================================
// FILE: Cadence/Views/Journal/RemarksTimelineView.swift
// FULL REPLACEMENT
// ============================================================

import SwiftUI
import SwiftData

// MARK: - JournalItem
//
// A view-layer-only enum that merges Remarks and DayNote entries
// (intentions and reflections) into a single chronological stream.
// The DayNote model is never mutated here — display only.
//
// Sort strategy within each day section (chronological, top → bottom):
//   .intention / .intentionPlaceholder  → synthetic 00:00:00 (always first)
//   .remark                             → actual remark.timestamp
//   .reflection / .reflectionPlaceholder → synthetic 23:59:59 (always last)

private enum JournalItem: Identifiable {
    case remark(Remark, TimeBlock?)
    case intention(DayNote)
    case reflection(DayNote)
    case intentionPlaceholder
    case reflectionPlaceholder

    var id: String {
        switch self {
        case .remark(let r, _):      return "remark-\(r.id)"
        case .intention(let n):      return "intention-\(n.id)"
        case .reflection(let n):     return "reflection-\(n.id)"
        case .intentionPlaceholder:  return "placeholder-intention"
        case .reflectionPlaceholder: return "placeholder-reflection"
        }
    }

    func sortTimestamp(forDayStart dayStart: Date) -> Date {
        let cal = Calendar.current
        switch self {
        case .remark(let r, _):      return r.timestamp
        case .intention,
             .intentionPlaceholder:  return dayStart   // 00:00:00
        case .reflection,
             .reflectionPlaceholder: return cal.date(bySettingHour: 23, minute: 59, second: 59, of: dayStart)!
        }
    }
}

// MARK: - RemarksTimelineView

struct RemarksTimelineView: View {
    @Environment(\.modelContext) private var modelContext

    // Remarks sorted forward so grouping logic is straightforward
    @Query(sort: \Remark.timestamp,  order: .forward) private var allRemarks:    [Remark]
    @Query(sort: \DayNote.date,      order: .reverse) private var allDayNotes:   [DayNote]
    @Query private var allTimeBlocks: [TimeBlock]

    @State private var searchText        = ""
    @State private var selectedTag: String? = nil
    @State private var showingTagPicker  = false

    // Sheet state — editingNote is set before presenting so the sheet
    // knows whether to update an existing record or create a new one.
    @State private var showingIntention  = false
    @State private var showingReflection = false
    @State private var editingNote: DayNote? = nil

    // MARK: - Derived state

    private var isFiltered: Bool { selectedTag != nil || !searchText.isEmpty }

    private var blockLookup: [UUID: TimeBlock] {
        Dictionary(uniqueKeysWithValues: allTimeBlocks.compactMap { ($0.id, $0) as (UUID, TimeBlock)? })
    }

    /// DayNotes keyed by their normalised (startOfDay) date.
    private var noteByDay: [Date: DayNote] {
        let cal = Calendar.current
        return Dictionary(
            allDayNotes.map { (cal.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }   // prefer earlier insert on duplicate dates
        )
    }

    private var allTags: [String] {
        Array(Set(allRemarks.flatMap { $0.tags })).sorted()
    }

    private var filteredRemarks: [Remark] {
        var results = allRemarks
        if let tag = selectedTag {
            results = results.filter { $0.tags.contains(tag) }
        }
        if !searchText.isEmpty {
            results = results.filter {
                $0.text.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        return results
    }

    // MARK: - Grouped timeline items
    //
    // Sections are newest-first (today at top).
    // Within each section items are chronological (intention → remarks → reflection).

    private var groupedItems: [(dayLabel: String, dayStart: Date, items: [JournalItem])] {
        let cal        = Calendar.current
        let todayStart = cal.startOfDay(for: Date())

        // Collect all calendar days that have content
        var daySet = Set<Date>()

        for remark in filteredRemarks {
            daySet.insert(cal.startOfDay(for: remark.timestamp))
        }

        if !isFiltered {
            // Include days with DayNote content even when no remarks exist
            for note in allDayNotes {
                let day = cal.startOfDay(for: note.date)
                if !note.intention.isEmpty || !note.reflection.isEmpty {
                    daySet.insert(day)
                }
            }
            // Always include today so placeholders can appear
            daySet.insert(todayStart)
        }

        // Build a group per day, newest first
        return daySet
            .sorted(by: >)
            .compactMap { dayStart -> (String, Date, [JournalItem])? in
                let isToday = dayStart == todayStart

                // Remarks for this day
                let remarkItems: [JournalItem] = filteredRemarks
                    .filter { cal.startOfDay(for: $0.timestamp) == dayStart }
                    .map { .remark($0, blockLookup[$0.timeBlockID]) }

                // DayNote items — only when not filtering
                var noteItems: [JournalItem] = []
                if !isFiltered {
                    let note = noteByDay[dayStart]

                    // Intention
                    if let note, !note.intention.isEmpty {
                        noteItems.append(.intention(note))
                    } else if isToday {
                        noteItems.append(.intentionPlaceholder)
                    }

                    // Reflection
                    if let note, !note.reflection.isEmpty {
                        noteItems.append(.reflection(note))
                    } else if isToday {
                        noteItems.append(.reflectionPlaceholder)
                    }
                }

                let allItems = remarkItems + noteItems
                guard !allItems.isEmpty else { return nil }

                // Sort chronologically within the day
                let sorted = allItems.sorted {
                    $0.sortTimestamp(forDayStart: dayStart) <
                    $1.sortTimestamp(forDayStart: dayStart)
                }

                let label: String
                if cal.isDateInToday(dayStart)         { label = "Today" }
                else if cal.isDateInYesterday(dayStart) { label = "Yesterday" }
                else { label = dayStart.formatted(date: .abbreviated, time: .omitted) }

                return (label, dayStart, sorted)
            }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if groupedItems.allSatisfy({ group in
                    group.items.allSatisfy {
                        if case .intentionPlaceholder  = $0 { return true }
                        if case .reflectionPlaceholder = $0 { return true }
                        return false
                    }
                }) && !isFiltered && allRemarks.isEmpty && allDayNotes.isEmpty {
                    emptyState
                } else if groupedItems.isEmpty {
                    emptyState
                } else {
                    timelineList
                }
            }
            .navigationTitle("Journal")
            .searchable(text: $searchText, prompt: "Search remarks or #tags")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingTagPicker = true
                    } label: {
                        Image(systemName: "tag")
                            .symbolVariant(selectedTag != nil ? .fill : .none)
                            .foregroundStyle(selectedTag != nil ? .blue : .primary)
                    }
                    .disabled(allTags.isEmpty)
                }
            }
            // Intention sheet
            .sheet(isPresented: $showingIntention, onDismiss: { editingNote = nil }) {
                IntentionSheet(existingNote: editingNote)
                    .presentationDetents([.medium])
            }
            // Reflection sheet
            .sheet(isPresented: $showingReflection, onDismiss: { editingNote = nil }) {
                ReflectionSheet(existingNote: editingNote)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingTagPicker) {
                TagPickerSheet(allTags: allTags, selectedTag: $selectedTag)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Timeline List

    private var timelineList: some View {
        List {
            // Active tag filter chip
            if let tag = selectedTag {
                Section {
                    Button { selectedTag = nil } label: {
                        HStack {
                            Image(systemName: "tag.fill").foregroundStyle(.blue)
                            Text("#\(tag)").foregroundStyle(.blue)
                            Spacer()
                            Text("Clear").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(groupedItems, id: \.dayLabel) { group in
                Section(header: Text(group.dayLabel).fontWeight(.semibold)) {
                    ForEach(group.items) { item in
                        itemRow(item, dayStart: group.dayStart)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Row routing

    @ViewBuilder
    private func itemRow(_ item: JournalItem, dayStart: Date) -> some View {
        switch item {

        case .remark(let remark, let block):
            RemarkTimelineRow(remark: remark, block: block)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleteRemark(remark) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

        case .intention(let note):
            IntentionTimelineRow(note: note)
                .listRowBackground(Color.orange.opacity(0.07))
                .contentShape(Rectangle())
                .onTapGesture { editingNote = note; showingIntention = true }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { clearIntention(note) } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .tint(.orange)
                    Button { editingNote = note; showingIntention = true } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }

        case .reflection(let note):
            ReflectionTimelineRow(note: note)
                .listRowBackground(Color.indigo.opacity(0.07))
                .contentShape(Rectangle())
                .onTapGesture { editingNote = note; showingReflection = true }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { clearReflection(note) } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .tint(.indigo)
                    Button { editingNote = note; showingReflection = true } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }

        case .intentionPlaceholder:
            IntentionPlaceholderRow {
                editingNote = noteByDay[dayStart]
                showingIntention = true
            }
            .listRowBackground(Color.orange.opacity(0.04))

        case .reflectionPlaceholder:
            ReflectionPlaceholderRow {
                editingNote = noteByDay[dayStart]
                showingReflection = true
            }
            .listRowBackground(Color.indigo.opacity(0.04))
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(isFiltered ? "No remarks match this filter" : "No journal entries yet")
                .font(.title3).fontWeight(.medium)
            Text("Add remarks while tracking, or set an intention to get started.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Actions

    private func deleteRemark(_ remark: Remark) {
        modelContext.delete(remark)
        try? modelContext.save()
    }

    private func clearIntention(_ note: DayNote) {
        note.intention = ""
        note.intentionUpdatedAt = nil
        try? modelContext.save()
    }

    private func clearReflection(_ note: DayNote) {
        note.reflection = ""
        note.reflectionUpdatedAt = nil
        try? modelContext.save()
    }
}

// MARK: - IntentionTimelineRow

struct IntentionTimelineRow: View {
    let note: DayNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sun.horizon.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
                .padding(.top, 2)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Morning Intention")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                    Spacer()
                    if let updatedAt = note.intentionUpdatedAt {
                        Text(updatedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Text(note.intention)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ReflectionTimelineRow

struct ReflectionTimelineRow: View {
    let note: DayNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .foregroundStyle(.indigo)
                .font(.subheadline)
                .padding(.top, 2)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Evening Reflection")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.indigo)
                    Spacer()
                    if let updatedAt = note.reflectionUpdatedAt {
                        Text(updatedAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Text(note.reflection)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - IntentionPlaceholderRow

struct IntentionPlaceholderRow: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "sun.horizon")
                    .foregroundStyle(.orange.opacity(0.5))
                    .font(.subheadline)
                    .frame(width: 20)

                Text("Set today's intention…")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.orange.opacity(0.5))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ReflectionPlaceholderRow

struct ReflectionPlaceholderRow: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars")
                    .foregroundStyle(.indigo.opacity(0.5))
                    .font(.subheadline)
                    .frame(width: 20)

                Text("Write tonight's reflection…")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.indigo.opacity(0.5))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - RemarkTimelineRow (preserved from original, unchanged)

struct RemarkTimelineRow: View {
    let remark: Remark
    let block: TimeBlock?

    private var timeString: String {
        remark.timestamp.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Activity color bar
            if let block {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: block.activityColor))
                    .frame(width: 4)
                    .frame(minHeight: 44)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let block {
                        Text(block.activityName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(timeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Text(remark.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !remark.tags.isEmpty {
                    TagChipRow(tags: remark.tags)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - TagChipRow (preserved from original, unchanged)

struct TagChipRow: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
        }
    }
}

// MARK: - TagPickerSheet (preserved from original, unchanged)

struct TagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let allTags: [String]
    @Binding var selectedTag: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedTag = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("All Remarks")
                            Spacer()
                            if selectedTag == nil {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section("Tags") {
                    ForEach(allTags, id: \.self) { tag in
                        Button {
                            selectedTag = tag
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundStyle(.blue)
                                    .font(.caption)
                                Text("#\(tag)")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedTag == tag {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter by Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
