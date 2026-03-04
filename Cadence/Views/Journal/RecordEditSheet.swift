// ============================================================
// FILE: Cadence/Views/Journal/RecordEditSheet.swift
// ============================================================

import SwiftUI
import SwiftData

struct QuickEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var block: TimeBlock
    let conflictDetector: ConflictDetector
    let onSave: () -> Void

    @Query private var activities: [Activity]
    @Query private var activitySets: [ActivitySet]
    @Query private var blockRemarks: [Remark]

    // Edit state
    @State private var editedStartTime: Date
    @State private var editedEndTime: Date
    @State private var editedActivityID: UUID?

    // UI state
    @State private var validationResult: ValidationResult?
    @State private var showingConflictConfirmation = false
    @State private var showingActivityPicker = false
    @State private var showingSplitSheet = false

    // Remarks state
    @State private var newRemarkText = ""
    @FocusState private var remarkFieldFocused: Bool

    init(block: TimeBlock, conflictDetector: ConflictDetector, onSave: @escaping () -> Void) {
        self.block            = block
        self.conflictDetector = conflictDetector
        self.onSave           = onSave
        _editedStartTime  = State(initialValue: block.startTime)
        _editedEndTime    = State(initialValue: block.endTime ?? Date())
        _editedActivityID = State(initialValue: block.activityID)

        let blockID = block.id
        _blockRemarks = Query(
            filter: #Predicate<Remark> { $0.timeBlockID == blockID },
            sort: \.timestamp
        )
    }

    // MARK: - Computed

    private var hasChanges: Bool {
        editedStartTime  != block.startTime     ||
        editedEndTime    != (block.endTime ?? Date()) ||
        editedActivityID != block.activityID
    }

    private var selectedActivity: Activity? { activities.first { $0.id == editedActivityID } }
    private var editedDuration: TimeInterval { editedEndTime.timeIntervalSince(editedStartTime) }

    private var canSave: Bool {
        guard hasChanges, let validation = validationResult else { return false }
        return validation.canProceedWithConfirmation
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Card — shows current activity and duration
                headerCard
                    .padding()

                Divider()

                // Core edits — auto expands sheet when scrolled
                Form {
                    // --- QUICK EDIT ITEMS ---
                    
                    Section {
                        activityPickerButton
                    }

                    Section {
                        timeEditors
                    }

                    if let validation = validationResult, !validation.isValid {
                        Section {
                            conflictWarnings(validation)
                        }
                    }

                    // --- FULL EDIT ITEMS (Revealed on Scroll/Swipe Up) ---
                    
                    Section {
                        ForEach(blockRemarks) { remark in
                            RemarkRow(remark: remark, onDelete: { deleteRemark(remark) })
                        }
                        
                        HStack {
                            TextField("Add a remark...", text: $newRemarkText)
                                .focused($remarkFieldFocused)
                                .onSubmit { addRemark() }
                            
                            if !newRemarkText.isEmpty {
                                Button(action: addRemark) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Remarks")
                    }
                    
                    Section {
                        Button {
                            showingSplitSheet = true
                        } label: {
                            Label("Split Block", systemImage: "scissors")
                        }
                    } header: {
                        Text("Advanced")
                    } footer: {
                        Text("Split this block into two separate activities.")
                    }
                }
            }
            .navigationTitle("Edit Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onChange(of: editedStartTime) { _, _ in validateChanges() }
            .onChange(of: editedEndTime)   { _, _ in validateChanges() }
            .onAppear { validateChanges() }
            .alert("Conflicts Detected", isPresented: $showingConflictConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Save Anyway", role: .destructive) { applyChanges() }
            } message: {
                if let validation = validationResult {
                    Text(validation.conflicts.map { $0.description }.joined(separator: "\n"))
                }
            }
            .sheet(isPresented: $showingSplitSheet) {
                SplitBlockSheet(block: block, onSplit: {
                    onSave()
                    dismiss()
                })
            }
            .sheet(isPresented: $showingActivityPicker) {
                ActivityPickerSheet(
                    activities: activities,
                    activitySets: activitySets,
                    selectedActivityID: $editedActivityID
                )
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: block.activityColor))
                .frame(width: 44, height: 44)
                .overlay {
                    if let act = selectedActivity, let emoji = act.emoji {
                        Text(emoji).font(.title3)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedActivity?.name ?? block.activityName)
                    .font(.headline)

                if block.pauseCount > 0 {
                    Text("\(block.pauseCount) pause\(block.pauseCount == 1 ? "" : "s") · \(block.totalPauseDuration.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(editedDuration.formattedDuration)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                if hasChanges {
                    Text("Modified")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Activity Picker Button

    private var activityPickerButton: some View {
        Button { showingActivityPicker = true } label: {
            HStack {
                if let activity = selectedActivity {
                    if let emoji = activity.emoji { Text(emoji).font(.title3) }
                    Circle().fill(Color(hex: activity.color)).frame(width: 20, height: 20)
                    Text(activity.name).foregroundStyle(.primary)
                } else {
                    Text("Select Activity").foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Time Editors

    @ViewBuilder
    private var timeEditors: some View {
        DatePicker("Start", selection: $editedStartTime,
                   displayedComponents: [.date, .hourAndMinute])

        if block.endTime != nil {
            DatePicker("End", selection: $editedEndTime,
                       displayedComponents: [.date, .hourAndMinute])
        } else {
            HStack {
                Text("End")
                Spacer()
                Text("Ongoing").foregroundStyle(.green).fontWeight(.medium)
            }
        }

        HStack {
            Text("Duration")
            Spacer()
            Text(editedDuration > 0 ? editedDuration.formattedDuration : "—")
                .foregroundStyle(editedDuration > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                .monospacedDigit()
        }
    }

    // MARK: - Conflict Warnings

    private func conflictWarnings(_ validation: ValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(validation.conflicts) { conflict in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: conflict.severity == .blocking
                          ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(conflict.severity == .blocking ? .red : .orange)
                    Text(conflict.description).font(.subheadline)
                        .foregroundStyle(conflict.severity == .blocking ? .red : .primary)
                }
            }
        }
    }

    // MARK: - Actions

    private func validateChanges() {
        validationResult = conflictDetector.validateEdit(
            block: block,
            newStart: editedStartTime,
            newEnd: editedEndTime
        )
    }

    private func saveChanges() {
        guard let validation = validationResult else { applyChanges(); return }
        if !validation.isValid { showingConflictConfirmation = true }
        else { applyChanges() }
    }

    private func applyChanges() {
        let oldStart = block.startTime
        let oldEnd   = block.endTime

        block.startTime = editedStartTime
        if block.endTime != nil { block.endTime = editedEndTime }

        if let newID = editedActivityID,
           newID != block.activityID,
           let activity = activities.first(where: { $0.id == newID }) {
            block.activityID    = activity.id
            block.activityName  = activity.name
            block.activityColor = activity.color
            block.activitySetID = activity.sets.first(where: { $0.isActive })?.id ?? activity.sets.first?.id
        }

        handleTimestampAdjustments(oldStart: oldStart, oldEnd: oldEnd,
                                   newStart: editedStartTime, newEnd: editedEndTime)
        try? modelContext.save()

        HistoryManager.shared.invalidateDate(oldStart, in: modelContext)
        if !Calendar.current.isDate(oldStart, inSameDayAs: editedStartTime) {
            HistoryManager.shared.invalidateDate(editedStartTime, in: modelContext)
        }
        onSave()
        dismiss()
    }

    private func handleTimestampAdjustments(oldStart: Date, oldEnd: Date?,
                                             newStart: Date, newEnd: Date) {
        let (previousBlock, nextBlock) = getAdjacentActivityBlocks(for: block)

        if newStart > oldStart {
            let spaceStart    = previousBlock?.endTime ?? oldStart
            let spaceDuration = newStart.timeIntervalSince(spaceStart)
            if spaceDuration > 0 && spaceDuration < 60 { previousBlock?.endTime = newStart }
        }

        if let oldEnd, newEnd < oldEnd {
            let spaceEnd      = nextBlock?.startTime ?? oldEnd
            let spaceDuration = spaceEnd.timeIntervalSince(newEnd)
            if spaceDuration > 0 && spaceDuration < 60 { block.endTime = spaceEnd }
        }
    }

    private func getAdjacentActivityBlocks(for block: TimeBlock) -> (previous: TimeBlock?, next: TimeBlock?) {
        let calendar  = Calendar.current
        let dayStart  = calendar.startOfDay(for: block.startTime)
        let searchEnd = calendar.date(byAdding: .day, value: 2, to: dayStart)!

        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { b in
                b.startTime >= dayStart && b.startTime < searchEnd && b.activityID != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )

        guard let allBlocks = try? modelContext.fetch(descriptor),
              let idx = allBlocks.firstIndex(where: { $0.id == block.id })
        else { return (nil, nil) }

        let previous = idx > 0 ? allBlocks[idx - 1] : nil
        let next     = idx < allBlocks.count - 1 ? allBlocks[idx + 1] : nil
        return (previous, next)
    }
    
    // MARK: - Remarks Actions
    
    private func addRemark() {
        let trimmed = newRemarkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let remark = Remark(timeBlockID: block.id, text: trimmed)
        modelContext.insert(remark)
        try? modelContext.save()
        newRemarkText = ""
        remarkFieldFocused = false
    }

    private func deleteRemark(_ remark: Remark) {
        modelContext.delete(remark)
        try? modelContext.save()
    }
}

// MARK: - RemarkRow

struct RemarkRow: View {
    let remark: Remark
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(remark.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
            }

            Text(remark.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !remark.tags.isEmpty {
                TagChipRow(tags: remark.tags)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Activity Picker Sheet

struct ActivityPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let activities: [Activity]
    let activitySets: [ActivitySet]
    @Binding var selectedActivityID: UUID?

    @State private var searchText = ""

    private var groupedActivities: [(set: ActivitySet, activities: [Activity])] {
        activitySets.compactMap { set in
            let setActivities = activities
                .filter { $0.sets.contains(where: { $0.id == set.id }) }
                .sorted { $0.name < $1.name }
            guard !setActivities.isEmpty else { return nil }
            return (set: set, activities: setActivities)
        }
    }

    private var filteredGroupedActivities: [(set: ActivitySet, activities: [Activity])] {
        guard !searchText.isEmpty else { return groupedActivities }
        return groupedActivities.compactMap { group in
            let filtered = group.activities.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
            guard !filtered.isEmpty else { return nil }
            return (set: group.set, activities: filtered)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedActivityID = nil
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "circle.slash")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text("None").foregroundStyle(.primary)
                            Spacer()
                            if selectedActivityID == nil {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                    }
                }

                ForEach(filteredGroupedActivities, id: \.set.id) { group in
                    Section {
                        ForEach(group.activities) { activity in
                            Button {
                                selectedActivityID = activity.id
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    if let emoji = activity.emoji {
                                        Text(emoji).font(.title3).frame(width: 32)
                                    } else {
                                        Circle()
                                            .fill(Color(hex: activity.color))
                                            .frame(width: 20, height: 20)
                                            .frame(width: 32)
                                    }
                                    Text(activity.name).foregroundStyle(.primary)
                                    Spacer()
                                    if selectedActivityID == activity.id {
                                        Image(systemName: "checkmark").foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(group.set.name)
                            if group.set.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search activities")
            .navigationTitle("Choose Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
