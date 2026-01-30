// RecordEditSheet 30th Jan 2026

import SwiftUI
import SwiftData

// MARK: - FIXED RecordEditSheet
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
                
                // Convert Gap/Pause to Activity - FIXED VERSION
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

// MARK: - Merge/Split Sheet
struct MergeSplitSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let timeBlock: TimeBlock
    
    @State private var operation: Operation = .split
    @State private var splitTime: Date = Date()
    @State private var allDayBlocks: [TimeBlock] = []
    @State private var mergeTargetActivity: Activity?
    @State private var allActivities: [Activity] = []
    @State private var errorMessage: String?
    
    enum Operation: String, CaseIterable {
        case split = "Split"
        case merge = "Merge"
    }
    
    var adjacentPrevious: TimeBlock? {
        guard let index = allDayBlocks.firstIndex(where: { $0.id == timeBlock.id }),
              index > 0 else { return nil }
        return allDayBlocks[index - 1]
    }
    
    var adjacentNext: TimeBlock? {
        guard let index = allDayBlocks.firstIndex(where: { $0.id == timeBlock.id }),
              index < allDayBlocks.count - 1 else { return nil }
        return allDayBlocks[index + 1]
    }
    
    var canSplit: Bool {
        guard let endTime = timeBlock.endTime else { return false }
        return endTime.timeIntervalSince(timeBlock.startTime) >= 120
    }
    
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
                
                if operation == .split {
                    splitView
                } else {
                    mergeView
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
        }
    }
    
    // MARK: - Split View
    
    @ViewBuilder
    private var splitView: some View {
        if !canSplit {
            ContentUnavailableView(
                "Cannot Split",
                systemImage: "scissors.badge.ellipsis",
                description: Text("Block must be at least 2 minutes long and completed")
            )
        } else if let endTime = timeBlock.endTime {
            Form {
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
                
                Section {
                    DatePicker(
                        "Split at",
                        selection: $splitTime,
                        in: timeBlock.startTime...endTime,
                        displayedComponents: [.hourAndMinute]
                    )
                } header: {
                    Text("Choose Split Point")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle()
                                .fill(Color(hex: timeBlock.activityColor))
                                .frame(width: 8, height: 8)
                            Text("Part 1: \(timeBlock.displayName)")
                                .font(.subheadline)
                            Spacer()
                            Text(splitTime.timeIntervalSince(timeBlock.startTime).formattedDuration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 8, height: 8)
                            Text("Part 2: Gap")
                                .font(.subheadline)
                            Spacer()
                            Text(endTime.timeIntervalSince(splitTime).formattedDuration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Result")
                } footer: {
                    Text("The second part becomes a Gap that you can convert to any activity later.")
                }
                
                Section {
                    Button("Split Block") {
                        performSplit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    // MARK: - Merge View
    
    @ViewBuilder
    private var mergeView: some View {
        Form {
            Section {
                BlockRow(block: timeBlock, label: "Current Block")
            }
            
            if let prev = adjacentPrevious {
                Section {
                    BlockRow(block: prev, label: "Previous Block")
                    
                    Button("Merge with Previous") {
                        mergeWithPrevious(prev)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            
            if let next = adjacentNext {
                Section {
                    BlockRow(block: next, label: "Next Block")
                    
                    Button("Merge with Next") {
                        mergeWithNext(next)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            
            if adjacentPrevious != nil && adjacentNext != nil {
                Section {
                    Button("Merge All Three") {
                        mergeAllThree()
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("Merges previous + current + next into one block")
                }
            }
            
            if adjacentPrevious == nil && adjacentNext == nil {
                ContentUnavailableView(
                    "No Adjacent Blocks",
                    systemImage: "link.badge.plus",
                    description: Text("This block has no adjacent blocks to merge with")
                )
            }
            
            // Select which activity the merged block should become
            if adjacentPrevious != nil || adjacentNext != nil {
                Section {
                    Text("Merged block will become:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button {
                        mergeTargetActivity = nil
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 12, height: 12)
                            Text("Gap")
                            Spacer()
                            if mergeTargetActivity == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    ForEach(allActivities) { activity in
                        Button {
                            mergeTargetActivity = activity
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: activity.color))
                                    .frame(width: 12, height: 12)
                                Text(activity.name)
                                Spacer()
                                if mergeTargetActivity?.id == activity.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                } header: {
                    Text("Merge Into")
                }
            }
        }
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
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text(block.duration.formattedDuration)
                            .font(.caption)
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
        
        // Set default split time to middle
        if let endTime = timeBlock.endTime {
            let duration = endTime.timeIntervalSince(timeBlock.startTime)
            splitTime = timeBlock.startTime.addingTimeInterval(duration / 2)
        }
    }
    
    private func performSplit() {
        let editor = TimeBlockEditor(modelContext: modelContext)
        do {
            try editor.splitBlock(timeBlock, at: splitTime)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func mergeWithPrevious(_ prev: TimeBlock) {
        let editor = TimeBlockEditor(modelContext: modelContext)
        do {
            try editor.mergeBlocks([prev, timeBlock], intoActivity: mergeTargetActivity)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func mergeWithNext(_ next: TimeBlock) {
        let editor = TimeBlockEditor(modelContext: modelContext)
        do {
            try editor.mergeBlocks([timeBlock, next], intoActivity: mergeTargetActivity)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func mergeAllThree() {
        guard let prev = adjacentPrevious,
              let next = adjacentNext else { return }
        
        let editor = TimeBlockEditor(modelContext: modelContext)
        do {
            try editor.mergeBlocks([prev, timeBlock, next], intoActivity: mergeTargetActivity)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
