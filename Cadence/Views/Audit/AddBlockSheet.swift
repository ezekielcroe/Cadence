//
//  AddBlockSheet.swift
//  Cadence
//
//  Manually add a time block
//

import SwiftUI
import SwiftData

struct AddBlockSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let date: Date
    let conflictDetector: ConflictDetector
    let onSave: () -> Void
    
    @Query private var activities: [Activity]
    
    @State private var selectedActivity: Activity?
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var remarks = ""
    @State private var validationResult: ValidationResult?
    @State private var showingConflictAlert = false
    
    init(date: Date, conflictDetector: ConflictDetector, onSave: @escaping () -> Void) {
        self.date = date
        self.conflictDetector = conflictDetector
        self.onSave = onSave
        
        // Default to current hour
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let startOfHour = calendar.date(from: components) ?? now
        
        _startTime = State(initialValue: startOfHour)
        _endTime = State(initialValue: startOfHour.addingTimeInterval(3600))
    }
    
    private var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    private var canSave: Bool {
        selectedActivity != nil &&
        duration > 0 &&
        (validationResult?.canProceedWithConfirmation ?? false)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Activity selection
                Section("Activity") {
                    if let activity = selectedActivity {
                        HStack {
                            if let emoji = activity.emoji {
                                Text(emoji)
                            }
                            Circle()
                                .fill(Color(activity.color))
                                .frame(width: 20, height: 20)
                            Text(activity.name)
                            Spacer()
                            Button("Change") {
                                selectedActivity = nil
                            }
                            .font(.caption)
                        }
                    } else {
                        ForEach(activities.prefix(8)) { activity in
                            Button {
                                selectedActivity = activity
                            } label: {
                                HStack {
                                    if let emoji = activity.emoji {
                                        Text(emoji)
                                    }
                                    Circle()
                                        .fill(Color(activity.color))
                                        .frame(width: 16, height: 16)
                                    Text(activity.name)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
                
                // Time selection
                Section("Time") {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                    
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(duration.formattedDuration)
                            .foregroundStyle(duration > 0 ? Color.primary : Color.red)
                            .monospacedDigit()
                    }
                }
                
                // Conflicts
                if let validation = validationResult, !validation.isValid {
                    Section {
                        ForEach(validation.conflicts) { conflict in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(conflict.severity == .blocking ? .red : .orange)
                                Text(conflict.description)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                
                // Notes
                Section("Notes (Optional)") {
                    TextField("What were you doing?", text: $remarks, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addBlock()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .onChange(of: startTime) { _, _ in validate() }
            .onChange(of: endTime) { _, _ in validate() }
            .onAppear { validate() }
        }
        .presentationDetents([.large])
    }
    
    private func validate() {
        // Create a temporary block for validation
        let tempBlock = TimeBlock(
            activityID: selectedActivity?.id,
            activityName: selectedActivity?.name ?? "",
            activityColor: selectedActivity?.color ?? "#999999",
            activitySetID: selectedActivity?.setID,
            startTime: startTime
        )
        tempBlock.endTime = endTime
        
        validationResult = conflictDetector.validateEdit(
            block: tempBlock,
            newStart: startTime,
            newEnd: endTime
        )
    }
    
    private func addBlock() {
        guard let activity = selectedActivity else { return }
        
        let newBlock = TimeBlock(activity: activity, startTime: startTime)
        newBlock.endTime = endTime
        newBlock.remarks = remarks
        newBlock.stopState = "stopped"
        
        modelContext.insert(newBlock)
        try? modelContext.save()
        
        onSave()
        dismiss()
    }
}

