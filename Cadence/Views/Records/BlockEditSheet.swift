//
//  BlockEditSheet.swift
//  Cadence
//

import SwiftUI
import SwiftData

struct BlockEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var block: TimeBlock
    let conflictDetector: ConflictDetector
    let onSave: () -> Void

    @Query private var activities: [Activity]
    @Query private var activitySets: [ActivitySet]
    @Query private var allRemarks: [Remark]   // filtered in computed prop below

    // Edit state
    @State private var editedStartTime: Date
    @State private var editedEndTime: Date
    @State private var editedActivityID: UUID?

    // Inline new-remark state
    @State private var newRemarkText = ""
    @FocusState private var remarkFieldFocused: Bool

    // UI state
    @State private var validationResult: ValidationResult?
    @State private var showingConflictConfirmation = false
    @State private var showingSplitSheet = false
    @State private var showingActivityPicker = false

    // Remarks for this block only
    private var blockRemarks: [Remark] {
        allRemarks
            .filter { $0.timeBlockID == block.id }
            .sorted { $0.timestamp < $1.timestamp }
    }

    init(block: TimeBlock, conflictDetector: ConflictDetector, onSave: @escaping () -> Void) {
        self.block            = block
        self.conflictDetector = conflictDetector
        self.onSave           = onSave
        _editedStartTime      = State(initialValue: block.startTime)
        _editedEndTime        = State(initialValue: block.endTime ?? Date())
        _editedActivityID     = State(initialValue: block.activityID)
    }

    // MARK: - Computed

    private var hasChanges: Bool {
        editedStartTime  != block.startTime  ||
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
            Form {
                Section {
                    currentStatusView
                }

                Section("Activity") {
                    activityPickerButton
                }

                Section("Time") {
                    timeEditors
                }

                if let validation = validationResult, !validation.isValid {
                    Section { conflictWarnings(validation) }
                }

                // MARK: Remarks Section
                Section {
                    ForEach(blockRemarks) { remark in
                        RemarkRow(remark: remark) {
                            deleteRemark(remark)
                        }
                    }

                    // Inline add field
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.secondary)
                            .font(.body)
                            .padding(.top, 2)

                        TextField("Add a remark… (#tags supported)", text: $newRemarkText, axis: .vertical)
                            .focused($remarkFieldFocused)
                            .lineLimit(1...4)
                            .submitLabel(.done)
                            .onSubmit { addRemark() }

                        if !newRemarkText.isEmpty {
                            Button("Add") { addRemark() }
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                } header: {
                    Text("Remarks")
                } footer: {
                    if blockRemarks.isEmpty {
                        Text("Use #tags to create searchable categories")
                    }
                }

                Section {
                    Button("Split This Block…") { showingSplitSheet = true }
                        .disabled(block.duration < 120)
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
                SplitBlockSheet(block: block, onSplit: { onSave(); dismiss() })
            }
            .sheet(isPresented: $showingActivityPicker) {
                ActivityPickerSheet(
                    activities: activities,
                    activitySets: activitySets,
                    selectedActivityID: $editedActivityID
                )
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Subviews (unchanged from original)

    private var currentStatusView: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: block.activityColor))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(block.activityName).font(.headline)
                if block.pauseCount > 0 {
                    Text("\(block.pauseCount) pause\(block.pauseCount == 1 ? "" : "s") · \(block.totalPauseDuration.formattedDuration) paused")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No pauses").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(editedDuration.formattedDuration)
                    .font(.title2).fontWeight(.bold).monospacedDigit()
                if hasChanges {
                    Text("Modified").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

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

    private var timeEditors: some View {
        Group {
            HStack {
                Text("Start")
                Spacer()
                DatePicker("", selection: $editedStartTime, in: allowedStartRange, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            HStack {
                Text("End")
                Spacer()
                if block.endTime != nil {
                    DatePicker("", selection: $editedEndTime, in: allowedEndRange, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                } else {
                    Text("Ongoing").foregroundStyle(.green).fontWeight(.medium)
                }
            }
            HStack {
                Text("Duration")
                Spacer()
                Text(editedDuration.formattedDuration).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func conflictWarnings(_ validation: ValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(validation.conflicts) { conflict in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: conflict.severity == .blocking ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(conflict.severity == .blocking ? .red : .orange)
                    Text(conflict.description).font(.subheadline)
                        .foregroundStyle(conflict.severity == .blocking ? .red : .primary)
                }
            }
        }
    }

    // MARK: - Timestamp Boundaries

    private var allowedStartRange: ClosedRange<Date> {
        let (prev, _) = getAdjacentActivityBlocks(for: block)
        let earliest  = prev?.endTime ?? Calendar.current.startOfDay(for: block.startTime)
        let latest    = editedEndTime
        return earliest...max(earliest, latest)
    }

    private var allowedEndRange: ClosedRange<Date> {
        let (_, next) = getAdjacentActivityBlocks(for: block)
        let earliest  = editedStartTime
        let latest    = next?.startTime ?? Calendar.current.date(byAdding: .day, value: 1, to: block.startTime)!
        return earliest...max(earliest, latest)
    }

    // MARK: - Actions

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

    private func validateChanges() {
        validationResult = conflictDetector.validateEdit(
            block: block, newStart: editedStartTime, newEnd: editedEndTime
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
            // Store the set ID from the most relevant set
            block.activitySetID = activity.sets.first(where: { $0.isActive })?.id ?? activity.sets.first?.id
        }

        handleTimestampAdjustments(oldStart: oldStart, oldEnd: oldEnd,
                                   newStart: editedStartTime, newEnd: editedEndTime)
        try? modelContext.save()
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
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: block.startTime)
        let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { b in
                b.startTime >= dayStart && b.startTime < dayEnd && b.activityID != nil
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
        return self.filteredGroupedActivities.compactMap { group in
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

