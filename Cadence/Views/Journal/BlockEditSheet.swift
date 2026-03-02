// ============================================================
// FILE: Cadence/Views/Journal/BlockEditSheet.swift
//
// ============================================================

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
    @Query private var blockRemarks: [Remark]

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

    // MARK: - Subviews

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

        // Invalidate (cover both old and new dates in case user moved the block to a new day)
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
        // Search a 48-hour window so we find blocks on the following day that
        // an overnight block might need to stay clear of.
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
}
