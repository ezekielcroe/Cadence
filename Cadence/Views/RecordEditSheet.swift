// RecordEditSheet - Updated with Fixed Merge/Split

import SwiftUI
import SwiftData

// MARK: - RecordEditSheet
struct RecordEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var timeBlock: TimeBlock
    
    @Query private var allActivities: [Activity]
    @State private var showingConvertConfirmation = false
    @State private var selectedActivity: Activity?
    
    var body: some View {
        NavigationStack {
            Form {
                // Activity Info
                Section("Current Status") {
                    HStack {
                        Circle()
                            .fill(Color(hex: timeBlock.activityColor))
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading) {
                            Text(timeBlock.displayName)
                                .font(.headline)
                            
                            Text(timeBlock.blockType.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if timeBlock.isGap || timeBlock.isPauseBlock {
                            Text("Can Convert")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                }
                
                // Convert Gap/Pause to Activity
                if timeBlock.isGap || timeBlock.isPauseBlock {
                    Section {
                        Text("Convert this \(timeBlock.blockType) to a tracked activity:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // List of all activities
                        ForEach(allActivities) { activity in
                            Button {
                                selectedActivity = activity
                                showingConvertConfirmation = true
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: activity.color))
                                        .frame(width: 16, height: 16)
                                    
                                    Text(activity.name)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                        
                        if allActivities.isEmpty {
                            Text("No activities available. Create activities in the Sets tab first.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } header: {
                        Text("Convert to Activity")
                    } footer: {
                        Text("⚠️ Once converted, this block cannot be merged or split.")
                            .foregroundColor(.orange)
                    }
                }
                
                // Time (immutable)
                Section {
                    LabeledContent("Start") {
                        Text(timeBlock.startTime, format: .dateTime)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let endTime = timeBlock.endTime {
                        LabeledContent("End") {
                            Text(endTime, format: .dateTime)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent("End") {
                            Text("Ongoing")
                                .foregroundStyle(.green)
                        }
                    }
                    
                    LabeledContent("Duration") {
                        Text(timeBlock.duration.detailedFormattedDuration)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Time")
                } footer: {
                    Text("Timestamps cannot be edited in the app.")
                }
                
                // Activity Details
                if timeBlock.switchCount > 0 || timeBlock.totalPauseDuration > 0 {
                    Section("Activity Details") {
                        if timeBlock.switchCount > 0 {
                            LabeledContent("Switches/Resumes") {
                                Text("\(timeBlock.switchCount)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if timeBlock.totalPauseDuration > 0 {
                            LabeledContent("Total Paused") {
                                Text(timeBlock.totalPauseDuration.formattedDuration)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        LabeledContent("Stop State") {
                            Text(timeBlock.stopState.capitalized)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Remarks
                Section {
                    TextEditor(text: $timeBlock.remarks)
                        .frame(minHeight: 100)
                } header: {
                    Text("Remarks")
                } footer: {
                    Text("Add notes about this activity session")
                }
            }
            .navigationTitle("Edit Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .alert("Convert to \(selectedActivity?.name ?? "Activity")?", isPresented: $showingConvertConfirmation) {
                Button("Cancel", role: .cancel) {
                    selectedActivity = nil
                }
                Button("Convert") {
                    if let activity = selectedActivity {
                        convertToActivity(activity)
                    }
                }
            } message: {
                Text("This will change this \(timeBlock.blockType) into '\(selectedActivity?.name ?? "")'. You won't be able to merge or split this block afterward.")
            }
        }
        .presentationDetents([.large])
    }
    
    private func convertToActivity(_ activity: Activity) {
        let editor = TimeBlockEditor(modelContext: modelContext)
        do {
            try editor.convertToActivity(timeBlock, activity: activity)
            dismiss()
        } catch {
            print("Error converting: \(error)")
        }
    }
}

// MARK: - Merge/Split Sheet (Fixed)
struct MergeSplitSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let timeBlock: TimeBlock
    
    @State private var operation: Operation = .merge
    @State private var splitPercentage: Double = 50.0
    @State private var allDayBlocks: [TimeBlock] = []
    @State private var selectedMergeTarget: MergeTarget = .gap
    @State private var allActivities: [Activity] = []
    @State private var errorMessage: String?
    @State private var showingError = false
    
    // Threshold for "short" activities (5 minutes)
    private let shortActivityThreshold: TimeInterval = 300
    
    enum Operation: String, CaseIterable {
        case merge = "Merge"
        case split = "Split"
    }
    
    enum MergeTarget: Hashable {
        case gap
        case activity(UUID, String, String) // id, name, color
    }
    
    // MARK: - Computed Properties
    
    /// Find the truly adjacent previous block (end time matches start time)
    var adjacentPrevious: TimeBlock? {
        guard let index = allDayBlocks.firstIndex(where: { $0.id == timeBlock.id }),
              index > 0 else { return nil }
        let prev = allDayBlocks[index - 1]
        // Check if truly adjacent (within 1 second tolerance)
        guard let prevEnd = prev.endTime else { return nil }
        let timeDiff = abs(prevEnd.timeIntervalSince(timeBlock.startTime))
        return timeDiff < 1.0 ? prev : nil
    }
    
    /// Find the truly adjacent next block (start time matches end time)
    var adjacentNext: TimeBlock? {
        guard let index = allDayBlocks.firstIndex(where: { $0.id == timeBlock.id }),
              index < allDayBlocks.count - 1,
              let currentEnd = timeBlock.endTime else { return nil }
        let next = allDayBlocks[index + 1]
        let timeDiff = abs(next.startTime.timeIntervalSince(currentEnd))
        return timeDiff < 1.0 ? next : nil
    }
    
    /// Check if the current block can participate in a merge
    /// Merge is allowed for: gaps, pauses, or short activities (<5 min)
    var canMergeCurrentBlock: Bool {
        if timeBlock.isGap || timeBlock.isPauseBlock {
            return true
        }
        // Short activity (< 5 minutes)
        return timeBlock.duration < shortActivityThreshold
    }
    
    /// Check if a given block can participate in a merge
    func canMergeBlock(_ block: TimeBlock) -> Bool {
        if block.isGap || block.isPauseBlock {
            return true
        }
        return block.duration < shortActivityThreshold
    }
    
    /// Check if merge with previous is possible
    var canMergeWithPrevious: Bool {
        guard let prev = adjacentPrevious else { return false }
        // At least one of the blocks must be mergeable
        return canMergeCurrentBlock || canMergeBlock(prev)
    }
    
    /// Check if merge with next is possible
    var canMergeWithNext: Bool {
        guard let next = adjacentNext else { return false }
        return canMergeCurrentBlock || canMergeBlock(next)
    }
    
    /// Check if the block can be split
    /// Now allows ANY completed block with ≥2 min duration to be split
    var canSplit: Bool {
        guard let endTime = timeBlock.endTime else { return false }
        let duration = endTime.timeIntervalSince(timeBlock.startTime)
        return duration >= 120 // At least 2 minutes
    }
    
    /// Get the calculated split time based on percentage
    var splitTime: Date {
        guard let endTime = timeBlock.endTime else { return timeBlock.startTime }
        let duration = endTime.timeIntervalSince(timeBlock.startTime)
        return timeBlock.startTime.addingTimeInterval(duration * splitPercentage / 100.0)
    }
    
    /// Get available merge targets from the blocks being merged
    func getMergeTargets(blocks: [TimeBlock]) -> [MergeTarget] {
        var targets: [MergeTarget] = [.gap]
        var seenActivityIDs: Set<UUID> = []
        
        for block in blocks {
            if let activityID = block.activityID, !seenActivityIDs.contains(activityID) {
                seenActivityIDs.insert(activityID)
                targets.append(.activity(activityID, block.activityName, block.activityColor))
            }
        }
        
        return targets
    }
    
    /// Check if the selected merge target is valid for the given blocks
    func isValidTarget(_ target: MergeTarget, for blocks: [TimeBlock]) -> Bool {
        let validTargets = getMergeTargets(blocks: blocks)
        return validTargets.contains(target)
    }
    
    /// Get the default merge target for a set of blocks
    func getDefaultMergeTarget(for blocks: [TimeBlock]) -> MergeTarget {
        // Prefer the first activity found, otherwise gap
        for block in blocks {
            if let activityID = block.activityID {
                return .activity(activityID, block.activityName, block.activityColor)
            }
        }
        return .gap
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Operation Picker
                Picker("Operation", selection: $operation) {
                    ForEach(Operation.allCases, id: \.self) { op in
                        Text(op.rawValue).tag(op)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                if operation == .merge {
                    mergeView
                } else {
                    splitView
                }
            }
            .navigationTitle("Edit Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                loadData()
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
    }
    
    // MARK: - Merge View
    
    @ViewBuilder
    private var mergeView: some View {
        Form {
            // Current block info
            Section {
                BlockRow(block: timeBlock, label: "Current Block")
                
                if !canMergeCurrentBlock {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("This is a long activity (≥5 min). Can only merge with adjacent gaps/pauses/short activities.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Merge with Previous
            if let prev = adjacentPrevious {
                Section {
                    BlockRow(block: prev, label: "Previous Block")
                    
                    if canMergeWithPrevious {
                        let blocks = [prev, timeBlock]
                        let targets = getMergeTargets(blocks: blocks)
                        
                        // Target picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Merged block will become:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(targets, id: \.self) { target in
                                Button {
                                    selectedMergeTarget = target
                                } label: {
                                    HStack {
                                        switch target {
                                        case .gap:
                                            Circle()
                                                .fill(Color.gray)
                                                .frame(width: 12, height: 12)
                                            Text("Gap")
                                        case .activity(_, let name, let color):
                                            Circle()
                                                .fill(Color(hex: color))
                                                .frame(width: 12, height: 12)
                                            Text(name)
                                        }
                                        
                                        Spacer()
                                        
                                        if selectedMergeTarget == target {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                        
                        Button("Merge with Previous") {
                            // Ensure valid target before merging
                            if !isValidTarget(selectedMergeTarget, for: blocks) {
                                selectedMergeTarget = getDefaultMergeTarget(for: blocks)
                            }
                            performMerge(blocks: blocks)
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("Cannot merge: both blocks are long activities (≥5 min)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("Previous Block")
                }
            }
            
            // Merge with Next
            if let next = adjacentNext {
                Section {
                    BlockRow(block: next, label: "Next Block")
                    
                    if canMergeWithNext {
                        let blocks = [timeBlock, next]
                        let targets = getMergeTargets(blocks: blocks)
                        
                        // Target picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Merged block will become:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(targets, id: \.self) { target in
                                Button {
                                    selectedMergeTarget = target
                                } label: {
                                    HStack {
                                        switch target {
                                        case .gap:
                                            Circle()
                                                .fill(Color.gray)
                                                .frame(width: 12, height: 12)
                                            Text("Gap")
                                        case .activity(_, let name, let color):
                                            Circle()
                                                .fill(Color(hex: color))
                                                .frame(width: 12, height: 12)
                                            Text(name)
                                        }
                                        
                                        Spacer()
                                        
                                        if selectedMergeTarget == target {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                        
                        Button("Merge with Next") {
                            if !isValidTarget(selectedMergeTarget, for: blocks) {
                                selectedMergeTarget = getDefaultMergeTarget(for: blocks)
                            }
                            performMerge(blocks: blocks)
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("Cannot merge: both blocks are long activities (≥5 min)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("Next Block")
                }
            }
            
            // Merge All Three
            if let prev = adjacentPrevious, let next = adjacentNext {
                let allThree = [prev, timeBlock, next]
                let canMergeAll = canMergeBlock(prev) || canMergeCurrentBlock || canMergeBlock(next)
                
                Section {
                    if canMergeAll {
                        let targets = getMergeTargets(blocks: allThree)
                        
                        // Target picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Merged block will become:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(targets, id: \.self) { target in
                                Button {
                                    selectedMergeTarget = target
                                } label: {
                                    HStack {
                                        switch target {
                                        case .gap:
                                            Circle()
                                                .fill(Color.gray)
                                                .frame(width: 12, height: 12)
                                            Text("Gap")
                                        case .activity(_, let name, let color):
                                            Circle()
                                                .fill(Color(hex: color))
                                                .frame(width: 12, height: 12)
                                            Text(name)
                                        }
                                        
                                        Spacer()
                                        
                                        if selectedMergeTarget == target {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                        
                        Button("Merge All Three") {
                            if !isValidTarget(selectedMergeTarget, for: allThree) {
                                selectedMergeTarget = getDefaultMergeTarget(for: allThree)
                            }
                            performMerge(blocks: allThree)
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("Cannot merge: all blocks are long activities (≥5 min)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("Merge All")
                } footer: {
                    Text("Combines previous + current + next into one block")
                }
            }
            
            // No adjacent blocks message
            if adjacentPrevious == nil && adjacentNext == nil {
                Section {
                    ContentUnavailableView(
                        "No Adjacent Blocks",
                        systemImage: "link.badge.plus",
                        description: Text("This block has no adjacent blocks to merge with. Blocks must be directly connected (no time gaps between them).")
                    )
                }
            }
        }
    }
    
    // MARK: - Split View
    
    @ViewBuilder
    private var splitView: some View {
        if !canSplit {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "Cannot Split",
                    systemImage: "scissors.badge.ellipsis",
                    description: Text(splitUnavailableReason)
                )
            }
        } else if let endTime = timeBlock.endTime {
            Form {
                // Block info
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(timeBlock.displayName)
                                .font(.headline)
                            Text("\(timeBlock.startTime, style: .time) → \(endTime, style: .time)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(timeBlock.duration.formattedDuration)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Block to Split")
                }
                
                // Split slider
                Section {
                    VStack(spacing: 16) {
                        // Slider
                        VStack(spacing: 8) {
                            Slider(value: $splitPercentage, in: 10...90, step: 1) {
                                Text("Split Point")
                            } minimumValueLabel: {
                                Text("10%")
                                    .font(.caption2)
                            } maximumValueLabel: {
                                Text("90%")
                                    .font(.caption2)
                            }
                            
                            // Split time display
                            HStack {
                                Text("Split at:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(splitTime, style: .time)
                                    .font(.headline)
                                    .monospacedDigit()
                            }
                        }
                    }
                } header: {
                    Text("Choose Split Point")
                }
                
                // Preview result - now shows same activity for both parts if it's an activity
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle()
                                .fill(Color(hex: timeBlock.activityColor))
                                .frame(width: 10, height: 10)
                            Text("Part 1: \(timeBlock.displayName)")
                                .font(.subheadline)
                            Spacer()
                            Text(splitTime.timeIntervalSince(timeBlock.startTime).formattedDuration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        
                        HStack {
                            Circle()
                                .fill(Color(hex: timeBlock.activityColor))
                                .frame(width: 10, height: 10)
                            Text("Part 2: \(timeBlock.displayName)")
                                .font(.subheadline)
                            Spacer()
                            Text(endTime.timeIntervalSince(splitTime).formattedDuration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Result Preview")
                } footer: {
                    if timeBlock.isRegularActivity {
                        Text("Both parts will remain as '\(timeBlock.activityName)'.")
                    } else {
                        Text("Both parts will remain as \(timeBlock.blockType)s.")
                    }
                }
                
                // Split button
                Section {
                    Button("Split Block") {
                        performSplit()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    /// Reason why split is unavailable
    private var splitUnavailableReason: String {
        guard let endTime = timeBlock.endTime else {
            return "Cannot split an ongoing block."
        }
        
        let duration = endTime.timeIntervalSince(timeBlock.startTime)
        
        if duration < 120 {
            return "Block must be at least 2 minutes long to split."
        }
        
        return "This block cannot be split."
    }
    
    // MARK: - Helper Views
    
    struct BlockRow: View {
        let block: TimeBlock
        let label: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Circle()
                        .fill(Color(hex: block.activityColor))
                        .frame(width: 10, height: 10)
                    
                    Text(block.displayName)
                        .font(.subheadline)
                    
                    // Block type badge
                    if block.isGap {
                        Text("Gap")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(3)
                    } else if block.isPauseBlock {
                        Text("Pause")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(3)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(block.duration.formattedDuration)
                            .font(.caption)
                            .monospacedDigit()
                        if let endTime = block.endTime {
                            Text("\(block.startTime, style: .time) → \(endTime, style: .time)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadData() {
        // Load all blocks for the day
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: timeBlock.startTime)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime >= dayStart && block.startTime < dayEnd
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        
        allDayBlocks = (try? modelContext.fetch(descriptor)) ?? []
        
        // Load activities
        allActivities = (try? modelContext.fetch(FetchDescriptor<Activity>())) ?? []
        
        // Set default split percentage to 50%
        splitPercentage = 50.0
        
        // Set default merge target based on current block
        if let activityID = timeBlock.activityID {
            selectedMergeTarget = .activity(activityID, timeBlock.activityName, timeBlock.activityColor)
        } else {
            selectedMergeTarget = .gap
        }
    }
    
    private func performSplit() {
        let editor = TimeBlockEditor(modelContext: modelContext)
        do {
            try editor.splitBlock(timeBlock, at: splitTime)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func performMerge(blocks: [TimeBlock]) {
        let editor = TimeBlockEditor(modelContext: modelContext)
        
        // Convert MergeTarget to Activity?
        let targetActivity: Activity?
        switch selectedMergeTarget {
        case .gap:
            targetActivity = nil
        case .activity(let id, _, _):
            targetActivity = allActivities.first { $0.id == id }
        }
        
        do {
            try editor.mergeBlocks(blocks, intoActivity: targetActivity)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
