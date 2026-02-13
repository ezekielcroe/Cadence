//
//  RemarksTimelineView.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 13/2/26.
//


import SwiftUI
import SwiftData

// MARK: - RemarksTimelineView
//
// A chronological narrative view of all Remarks.
// Grouped by date, each entry shows the remark text, its timestamp,
// and the activity context (color bar + name) it belongs to.
// Filterable by hashtag.

struct RemarksTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Remark.timestamp, order: .reverse) private var allRemarks: [Remark]
    @Query private var allTimeBlocks: [TimeBlock]

    @State private var searchText       = ""
    @State private var selectedTag: String? = nil
    @State private var showingTagPicker = false

    // Block lookup — built once per render, O(n) to query
    private var blockLookup: [UUID: TimeBlock] {
        Dictionary(uniqueKeysWithValues: allTimeBlocks.compactMap { block in
            (block.id, block) as (UUID, TimeBlock)?
        })
    }

    // All unique tags across all remarks
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
                $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            }
        }

        return results
    }

    // Group remarks by calendar day, preserving reverse-chronological order
    private var groupedRemarks: [(dayLabel: String, remarks: [Remark])] {
        let calendar = Calendar.current
        var grouped: [(dayLabel: String, remarks: [Remark])] = []
        var currentLabel = ""
        var currentGroup: [Remark] = []

        for remark in filteredRemarks {
            let label: String
            if calendar.isDateInToday(remark.timestamp)     { label = "Today" }
            else if calendar.isDateInYesterday(remark.timestamp) { label = "Yesterday" }
            else { label = remark.timestamp.formatted(date: .abbreviated, time: .omitted) }

            if label != currentLabel {
                if !currentGroup.isEmpty { grouped.append((currentLabel, currentGroup)) }
                currentLabel = label
                currentGroup = [remark]
            } else {
                currentGroup.append(remark)
            }
        }
        if !currentGroup.isEmpty { grouped.append((currentLabel, currentGroup)) }
        return grouped
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredRemarks.isEmpty {
                    emptyState
                } else {
                    remarksList
                }
            }
            .navigationTitle("Remarks")
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
            .sheet(isPresented: $showingTagPicker) {
                TagPickerSheet(allTags: allTags, selectedTag: $selectedTag)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Remarks List

    private var remarksList: some View {
        List {
            if let tag = selectedTag {
                Section {
                    Button {
                        selectedTag = nil
                    } label: {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundStyle(.blue)
                            Text("#\(tag)")
                                .foregroundStyle(.blue)
                            Spacer()
                            Text("Clear")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(groupedRemarks, id: \.dayLabel) { group in
                Section(header: Text(group.dayLabel)) {
                    ForEach(group.remarks) { remark in
                        RemarkTimelineRow(
                            remark: remark,
                            block: blockLookup[remark.timeBlockID]
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteRemark(remark)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(selectedTag != nil || !searchText.isEmpty
                 ? "No remarks match this filter"
                 : "No remarks yet")
                .font(.title3)
                .fontWeight(.medium)
            Text("Add remarks while tracking using the Quick Remark button")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Actions

    private func deleteRemark(_ remark: Remark) {
        modelContext.delete(remark)
        try? modelContext.save()
    }
}

// MARK: - RemarkTimelineRow

struct RemarkTimelineRow: View {
    let remark: Remark
    let block: TimeBlock?

    private var timeString: String {
        remark.timestamp.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Activity color bar
            if let block = block {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: block.activityColor))
                    .frame(width: 4)
                    .frame(minHeight: 44)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Activity name + time
                HStack {
                    if let block = block {
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

                // Remark text
                Text(remark.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // Tags
                if !remark.tags.isEmpty {
                    TagChipRow(tags: remark.tags)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tag Chip Row

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

// MARK: - Tag Picker Sheet

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