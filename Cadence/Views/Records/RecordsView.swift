//
//  RecordsView.swift
//  Cadence
//
//

import SwiftUI
import SwiftData

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeBlock.startTime, order: .reverse) private var allTimeBlocks: [TimeBlock]
    
    // Filters & Search
    @State private var searchText = ""
    @State private var selectedActivity: String? = nil
    @State private var showingFilters = false
    @State private var hidePauses = false
    @State private var showArchived = false
    
    // Edit state
    @State private var selectedBlock: TimeBlock?
    @State private var conflictDetector: ConflictDetector?
    @State private var gapToResolve: TimeBlock?
    
    // Multi-select for bulk operations
    @State private var isSelectionMode = false
    @State private var selectedBlockIDs: Set<UUID> = []
    
    // Error Handling state
    @State private var showingMergeError = false
    @State private var mergeErrorMessage = ""
    
    // MARK: - Computed Properties
    
    private let editCutoffDays = 3
    
    var filteredBlocks: [TimeBlock] {
        var blocks = allTimeBlocks
        
        // 1. Archive Filter
        if !showArchived {
            let cutoff = Calendar.current.date(byAdding: .day, value: -editCutoffDays, to: Date())!
            blocks = blocks.filter { $0.startTime > cutoff }
        }
        
        // 2. Pause Filter
        if hidePauses {
            blocks = blocks.filter { !$0.isPauseBlock }
        }
        
        // 3. Activity Filter
        if let selected = selectedActivity {
            blocks = blocks.filter { $0.activityName == selected }
        }
        
        // 4. Search
        if !searchText.isEmpty {
            blocks = blocks.filter { $0.activityName.localizedCaseInsensitiveContains(searchText) || $0.remarks.localizedCaseInsensitiveContains(searchText) }
        }
        
        return blocks
    }
    
    // Identify gaps that need attention
    var unresolvedGaps: [TimeBlock] {
        filteredBlocks.filter { $0.isGap }
    }
    
    var groupedBlocks: [String: [TimeBlock]] {
        Dictionary(grouping: filteredBlocks) { block in
            if Calendar.current.isDateInToday(block.startTime) {
                return "Today"
            } else if Calendar.current.isDateInYesterday(block.startTime) {
                return "Yesterday"
            } else {
                return block.startTime.formatted(date: .abbreviated, time: .omitted)
            }
        }
    }
    
    var sectionKeys: [String] {
        // Custom sort to keep Today/Yesterday at top, then descending dates
        groupedBlocks.keys.sorted { key1, key2 in
            if key1 == "Today" { return true }
            if key2 == "Today" { return false }
            if key1 == "Yesterday" { return true }
            if key2 == "Yesterday" { return false }
            
            // Parse dates for remaining
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy" // Adjust based on locale
            let d1 = formatter.date(from: key1) ?? Date.distantPast
            let d2 = formatter.date(from: key2) ?? Date.distantPast
            return d1 > d2
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                List {
                    // FIX 1: Extracted header logic to reduce compiler complexity
                    headerSection
                    
                    // Timeline Sections
                    ForEach(sectionKeys, id: \.self) { section in
                        Section(header: Text(section)) {
                            ForEach(groupedBlocks[section] ?? []) { block in
                                AuditRow(
                                    block: block,
                                    isSelected: selectedBlockIDs.contains(block.id),
                                    isSelectionMode: isSelectionMode,
                                    isEditable: true,
                                    onTap: { handleBlockTap(block) },
                                    onResolveGap: { gapToResolve = block }
                                )
                                .swipeActions(edge: .leading) {
                                    if block.isGap {
                                        Button("Resolve") { gapToResolve = block }
                                            .tint(.orange)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteBlock(block)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                
                // Bulk Actions Toolbar
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
                        Toggle("Hide Pauses", isOn: $hidePauses)
                        Toggle("Show Archived", isOn: $showArchived)
                        Divider()
                        Button("Filter by Activity...", action: { showingFilters = true })
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .symbolVariant(selectedActivity != nil || hidePauses ? .fill : .none)
                    }
                }
            }
            // Sheets
            .sheet(item: $selectedBlock) { block in
                BlockEditSheet(
                    block: block,
                    conflictDetector: conflictDetector ?? ConflictDetector(modelContext: modelContext),
                    onSave: { try? modelContext.save() }
                )
            }
            .sheet(item: $gapToResolve) { gap in
                GapResolverSheet(gap: gap) {
                    try? modelContext.save()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingFilters) {
                // FIX 2: Ensure FiltersView is defined (see bottom of file)
                FiltersView(
                    selectedActivity: $selectedActivity,
                    activities: Array(Set(allTimeBlocks.map { $0.activityName })).sorted()
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
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private var headerSection: some View {
        if !unresolvedGaps.isEmpty {
            GapActionBanner(gaps: unresolvedGaps) {
                if let firstGap = unresolvedGaps.first {
                    gapToResolve = firstGap
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        } else if filteredBlocks.count > 0 && searchText.isEmpty {
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
            if block.isGap {
                gapToResolve = block
            } else {
                selectedBlock = block
            }
        }
    }
    
    private func deleteBlock(_ block: TimeBlock) {
        modelContext.delete(block)
        try? modelContext.save()
    }
    
    private func deleteSelected() {
        let blocksToDelete = allTimeBlocks.filter { selectedBlockIDs.contains($0.id) }
        for block in blocksToDelete {
            modelContext.delete(block)
        }
        try? modelContext.save()
        isSelectionMode = false
        selectedBlockIDs.removeAll()
    }
    
    private func mergeSelected() {
        let editor = TimeBlockEditor(modelContext: modelContext)
        // Sort blocks by start time
        let blocksToMerge = allTimeBlocks
            .filter { selectedBlockIDs.contains($0.id) }
            .sorted { $0.startTime < $1.startTime }
        
        // FIX 3: Fetch the activity from the first block to pass to mergeBlocks
        guard let firstBlock = blocksToMerge.first,
              let activityID = firstBlock.activityID else {
            mergeErrorMessage = "Cannot merge these blocks. Make sure they are activities, not gaps."
            showingMergeError = true
            return
        }
        
        // We need the actual Activity object to pass to the editor
        let descriptor = FetchDescriptor<Activity>(predicate: #Predicate { $0.id == activityID })
        guard let targetActivity = try? modelContext.fetch(descriptor).first else {
            mergeErrorMessage = "Could not find original activity."
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
    let gaps: [TimeBlock]
    let onResolve: () -> Void
    
    var totalGapDuration: TimeInterval {
        gaps.reduce(0) { $0 + $1.duration }
    }
    
    var body: some View {
        Button(action: onResolve) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Unaccounted Time")
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text("\(gaps.count) gaps totaling \(totalGapDuration.formattedDuration)")
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

// MARK: - Bulk Action Toolbar (Helper)

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

// MARK: - Filters View (FIX 2)

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
