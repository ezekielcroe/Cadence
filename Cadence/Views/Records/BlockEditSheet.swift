//
//  BlockEditSheet.swift
//  Cadence
//
//  Precision time block editor with conflict detection
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
    
    // Edit state - we edit copies, not the original directly
    @State private var editedStartTime: Date
    @State private var editedEndTime: Date
    @State private var editedActivityID: UUID?
    @State private var editedRemarks: String
    
    // Validation state
    @State private var validationResult: ValidationResult?
    @State private var showingDeleteConfirmation = false
    @State private var showingConflictConfirmation = false
    @State private var showingSplitSheet = false
    @State private var showingActivityPicker = false
    
    init(
        block: TimeBlock,
        conflictDetector: ConflictDetector,
        onSave: @escaping () -> Void,
    ) {
        self.block = block
        self.conflictDetector = conflictDetector
        self.onSave = onSave
        
        // Initialize edit state from block
        _editedStartTime = State(initialValue: block.startTime)
        _editedEndTime = State(initialValue: block.endTime ?? Date())
        _editedActivityID = State(initialValue: block.activityID)
        _editedRemarks = State(initialValue: block.remarks)
    }
    
    private var hasChanges: Bool {
        editedStartTime != block.startTime ||
        editedEndTime != (block.endTime ?? Date()) ||
        editedActivityID != block.activityID ||
        editedRemarks != block.remarks
    }
    
    private var selectedActivity: Activity? {
        activities.first { $0.id == editedActivityID }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Current status header
                Section {
                    currentStatusView
                }
                
                // Activity selection (not for gaps - they use GapResolver)
                if !block.isGap && !block.isPauseBlock {
                    Section("Activity") {
                        activityPickerButton
                    }
                }
                
                // Time editing
                Section("Time") {
                    timeEditors
                }
                
                // Conflict warnings
                if let validation = validationResult, !validation.isValid {
                    Section {
                        conflictWarnings(validation)
                    }
                }
                
                // Remarks
                Section("Notes") {
                    TextEditor(text: $editedRemarks)
                        .frame(minHeight: 80)
                }
                
                // Actions
                Section {
                    Button("Split This Block...") {
                        showingSplitSheet = true
                    }
                    .disabled(block.duration < 120) // Minimum 2 minutes to split
                    
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
            .onChange(of: editedEndTime) { _, _ in validateChanges() }
            .onAppear { validateChanges() }
            .alert("Conflicts Detected", isPresented: $showingConflictConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Save Anyway", role: .destructive) {
                    applyChanges()
                }
            } message: {
                if let validation = validationResult {
                    Text(validation.conflicts.map { $0.description }.joined(separator: "\n"))
                }
            }
            .sheet(isPresented: $showingSplitSheet) {
                SplitBlockSheet(
                    block: block,
                    onSplit: {
                        onSave()
                        dismiss()
                    }
                )
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
                .overlay {
                    if block.isGap {
                        Image(systemName: "questionmark")
                            .foregroundStyle(.white)
                    } else if block.isPauseBlock {
                        Image(systemName: "pause")
                            .foregroundStyle(.white)
                    }
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(block.displayName)
                    .font(.headline)
                
                Text(block.blockType.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(editedDuration.formattedDuration)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                
                if hasChanges {
                    Text("Modified")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
    
    private var activityPickerButton: some View {
        Button {
            showingActivityPicker = true
        } label: {
            HStack {
                if let activity = selectedActivity {
                    // Show selected activity with emoji
                    if let emoji = activity.emoji {
                        Text(emoji)
                            .font(.title3)
                    }
                    
                    Circle()
                        .fill(Color(hex: activity.color))
                        .frame(width: 20, height: 20)
                    
                    Text(activity.name)
                        .foregroundStyle(.primary)
                } else {
                    Text("Select Activity")
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    private var timeEditors: some View {
        Group {
            HStack {
                Text("Start")
                Spacer()
                DatePicker(
                    "",
                    selection: $editedStartTime,
                    in: allowedStartRange,
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            }
            
            HStack {
                Text("End")
                Spacer()
                if block.endTime != nil {
                    DatePicker(
                        "",
                        selection: $editedEndTime,
                        in: allowedEndRange,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                } else {
                    Text("Ongoing")
                        .foregroundStyle(.green)
                        .fontWeight(.medium)
                }
            }
            
            // Duration display
            HStack {
                Text("Duration")
                Spacer()
                Text(editedDuration.formattedDuration)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
    
    private func conflictWarnings(_ validation: ValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(validation.conflicts) { conflict in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: conflict.severity == .blocking ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(conflict.severity == .blocking ? .red : .orange)
                    
                    Text(conflict.description)
                        .font(.subheadline)
                        .foregroundStyle(conflict.severity == .blocking ? .red : .primary)
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var editedDuration: TimeInterval {
        editedEndTime.timeIntervalSince(editedStartTime)
    }
    
    private var canSave: Bool {
        guard hasChanges else { return false }
        guard let validation = validationResult else { return false }
        return validation.canProceedWithConfirmation
    }
    
    // MARK: - Timestamp Boundaries

    /// Allowed range for start time (from previous activity's end to current end)
    private var allowedStartRange: ClosedRange<Date> {
        let (prev, _) = getAdjacentActivityBlocks(for: block)

        let earliest = prev?.endTime ?? Calendar.current.startOfDay(for: block.startTime)
        let latest = editedEndTime

        // FIX: Ensure latest is never smaller than earliest
        return earliest...max(earliest, latest)
    }

    /// Allowed range for end time (from current start to next activity's start)
    private var allowedEndRange: ClosedRange<Date> {
        let (_, next) = getAdjacentActivityBlocks(for: block)

        let earliest = editedStartTime
        let latest = next?.startTime ?? Calendar.current.date(byAdding: .day, value: 1, to: block.startTime)!

        // FIX: Ensure latest is never smaller than earliest
        return earliest...max(earliest, latest)
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
        guard let validation = validationResult else {
            applyChanges()
            return
        }
        
        // If there are warnings, show them but allow proceeding
        if !validation.isValid {
            showingConflictConfirmation = true
        } else {
            applyChanges()
        }
    }
    
    private func applyChanges() {
        // SAVE OLD VALUES BEFORE CHANGING
        let oldStart = block.startTime
        let oldEnd = block.endTime
        
        // Update the block with edited values
        block.startTime = editedStartTime
        if block.endTime != nil {
            block.endTime = editedEndTime
        }
        
        // Update activity if changed
        if let newActivityID = editedActivityID,
           newActivityID != block.activityID,
           let activity = activities.first(where: { $0.id == newActivityID }) {
            block.activityID = activity.id
            block.activityName = activity.name
            block.activityColor = activity.color
            block.activitySetID = activity.setID
            block.blockType = "activity"
        }
        
        block.remarks = editedRemarks
        
        // CALL AUTO-FILL LOGIC
        handleTimestampAdjustments(
            oldStart: oldStart,
            oldEnd: oldEnd,
            newStart: editedStartTime,
            newEnd: editedEndTime
        )
        
        try? modelContext.save()
        onSave()
        dismiss()
    }
    
    // MARK: - Auto-Fill Logic

    /// Handles creation of gaps/pauses when timestamp edits create empty space
    private func handleTimestampAdjustments(
        oldStart: Date,
        oldEnd: Date?,
        newStart: Date,
        newEnd: Date
    ) {
        let (previousActivity, nextActivity) = getAdjacentActivityBlocks(for: block)
        
        // Handle space created BEFORE this block (moved start time forward)
        if newStart > oldStart {
            let spaceStart = previousActivity?.endTime ?? oldStart
            handleSpace(from: spaceStart, to: newStart, extendingBlock: previousActivity)
        }
        
        // Handle space created AFTER this block (moved end time backward)
        if let oldEnd = oldEnd, newEnd < oldEnd {
            let spaceEnd = nextActivity?.startTime ?? oldEnd
            handleSpace(from: newEnd, to: spaceEnd, extendingBlock: block)
        }
        
        // Clean up any absorbed gaps/pauses
        cleanupAbsorbedBlocks(newStart: newStart, newEnd: newEnd)
    }

    /// Creates gap/pause or auto-snaps based on duration
    private func handleSpace(from start: Date, to end: Date, extendingBlock: TimeBlock?) {
        let duration = end.timeIntervalSince(start)
        
        if duration < 60 {
            // < 1 minute: Auto-snap by extending adjacent block
            if let blockToExtend = extendingBlock {
                blockToExtend.endTime = end
            } else {
                // If no block to extend, extend current block backward
                block.startTime = start
            }
        } else if duration < 300 {
            // 1-5 minutes: Create Pause
            let pause = TimeBlock.createPause(startTime: start, endTime: end)
            pause.stopState = "stopped"
            modelContext.insert(pause)
        } else {
            // ≥ 5 minutes: Create Gap
            let gap = TimeBlock.createGap(startTime: start, endTime: end)
            gap.stopState = "stopped"
            modelContext.insert(gap)
        }
    }

    /// Removes gaps/pauses that have been absorbed by timestamp expansion
    private func cleanupAbsorbedBlocks(newStart: Date, newEnd: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: block.startTime)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        // Simplified predicate - fetch all gaps/pauses for the day
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { b in
                b.startTime >= dayStart &&
                b.startTime < dayEnd
            }
        )
        
        guard let allBlocks = try? modelContext.fetch(descriptor) else { return }
        
        // Filter in code instead of in predicate (easier for compiler)
        let gapsAndPauses = allBlocks.filter { candidate in
            candidate.id != block.id &&
            (candidate.blockType == "gap" || candidate.blockType == "pause")
        }
        
        for candidate in gapsAndPauses {
            guard let candidateEnd = candidate.endTime else { continue }
            
            // Fully absorbed (completely inside the edited block)
            if candidate.startTime >= newStart && candidateEnd <= newEnd {
                modelContext.delete(candidate)
            }
            // Partially absorbed from the end (trim it)
            else if candidate.startTime < newStart && candidateEnd > newStart && candidateEnd <= newEnd {
                candidate.endTime = newStart
            }
            // Partially absorbed from the start (trim it)
            else if candidate.startTime >= newStart && candidate.startTime < newEnd && candidateEnd > newEnd {
                candidate.startTime = newEnd
                
                // Re-check duration after trimming - delete if too small
                let newDuration = candidateEnd.timeIntervalSince(newEnd)
                if newDuration < 60 {
                    modelContext.delete(candidate)
                }
            }
        }
    }

    /// Gets adjacent ACTIVITY blocks (skipping gaps/pauses)
    private func getAdjacentActivityBlocks(for block: TimeBlock) -> (previous: TimeBlock?, next: TimeBlock?) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: block.startTime)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { b in
                b.startTime >= dayStart &&
                b.startTime < dayEnd &&
                b.blockType == "activity"  // Only actual activities
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        
        guard let allActivities = try? modelContext.fetch(descriptor),
              let currentIndex = allActivities.firstIndex(where: { $0.id == block.id }) else {
            return (nil, nil)
        }
        
        // Get previous activity (if any)
        let previous = currentIndex > 0 ? allActivities[currentIndex - 1] : nil
        
        // Get next activity (if any)
        let next = currentIndex < allActivities.count - 1 ? allActivities[currentIndex + 1] : nil
        
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
    
    // Group activities by set
    private var groupedActivities: [(set: ActivitySet, activities: [Activity])] {
        activitySets.compactMap { set in
            let setActivities = activities
                .filter { $0.setID == set.id }
                .sorted { $0.name < $1.name } // Alphabetical within set
            
            guard !setActivities.isEmpty else { return nil }
            return (set: set, activities: setActivities)
        }
    }
    
    private var filteredGroupedActivities: [(set: ActivitySet, activities: [Activity])] {
        if searchText.isEmpty {
            return groupedActivities
        }
        
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
                // None option
                Section {
                    Button {
                        selectedActivityID = nil
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "circle.slash")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            
                            Text("None")
                                .foregroundStyle(.primary)
                            
                            Spacer()
                            
                            if selectedActivityID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                
                // Activities grouped by set
                ForEach(filteredGroupedActivities, id: \.set.id) { group in
                    Section {
                        ForEach(group.activities) { activity in
                            Button {
                                selectedActivityID = activity.id
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    // Emoji (if available)
                                    if let emoji = activity.emoji {
                                        Text(emoji)
                                            .font(.title3)
                                            .frame(width: 32)
                                    } else {
                                        // Fallback to colored circle
                                        Circle()
                                            .fill(Color(hex: activity.color))
                                            .frame(width: 20, height: 20)
                                            .frame(width: 32)
                                    }
                                    
                                    // Activity name
                                    Text(activity.name)
                                        .foregroundStyle(.primary)
                                    
                                    Spacer()
                                    
                                    // Checkmark if selected
                                    if selectedActivityID == activity.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
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
