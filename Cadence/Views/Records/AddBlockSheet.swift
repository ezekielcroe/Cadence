//
//  AddBlockSheet.swift
//  Cadence
//

import SwiftUI
import SwiftData

struct AddBlockSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    let date:              Date
    let conflictDetector:  ConflictDetector
    let onSave:            () -> Void

    @Query private var activities: [Activity]

    @State private var selectedActivity: Activity?
    @State private var startTime:        Date
    @State private var endTime:          Date
    @State private var remarkText        = ""   // saved as a Remark record on add
    @State private var validationResult: ValidationResult?

    init(date: Date, conflictDetector: ConflictDetector, onSave: @escaping () -> Void) {
        self.date             = date
        self.conflictDetector = conflictDetector
        self.onSave           = onSave

        let calendar   = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let startOfHour = calendar.date(from: components) ?? Date()

        _startTime = State(initialValue: startOfHour)
        _endTime   = State(initialValue: startOfHour.addingTimeInterval(3600))
    }

    // MARK: - Computed

    private var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    private var canSave: Bool {
        selectedActivity != nil &&
        duration > 0 &&
        (validationResult?.canProceedWithConfirmation ?? false)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Activity
                Section("Activity") {
                    if let activity = selectedActivity {
                        HStack {
                            if let emoji = activity.emoji { Text(emoji) }
                            Circle()
                                .fill(Color(hex: activity.color))
                                .frame(width: 20, height: 20)
                            Text(activity.name)
                            Spacer()
                            Button("Change") { selectedActivity = nil }
                                .font(.caption)
                        }
                    } else {
                        ForEach(activities.prefix(8)) { activity in
                            Button {
                                selectedActivity = activity
                                validate()
                            } label: {
                                HStack {
                                    if let emoji = activity.emoji { Text(emoji) }
                                    Circle()
                                        .fill(Color(hex: activity.color))
                                        .frame(width: 16, height: 16)
                                    Text(activity.name)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }

                // MARK: Time
                Section("Time") {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End",   selection: $endTime,   displayedComponents: .hourAndMinute)

                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(duration.formattedDuration)
                            .foregroundStyle(duration > 0 ? Color.primary : Color.red)
                            .monospacedDigit()
                    }
                }

                // MARK: Conflicts
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

                // MARK: Remark
                Section {
                    TextField("What were you doing? (#tags supported)", text: $remarkText, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Remark (Optional)")
                } footer: {
                    Text("Saved as a remark on this block. Use #tags to make it searchable.")
                        .opacity(remarkText.isEmpty ? 1 : 0)
                }
            }
            .navigationTitle("Add Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addBlock() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onChange(of: startTime) { _, _ in validate() }
            .onChange(of: endTime)   { _, _ in validate() }
            .onAppear { validate() }
        }
        .presentationDetents([.large])
    }

    // MARK: - Validation

    private func validate() {
        let tempBlock = TimeBlock(
            activityID:    selectedActivity?.id,
            activityName:  selectedActivity?.name  ?? "",
            activityColor: selectedActivity?.color ?? "#999999",
            activitySetID: selectedActivity?.sets.first(where: { $0.isActive })?.id,
            startTime:     startTime
        )
        tempBlock.endTime = endTime

        validationResult = conflictDetector.validateEdit(
            block:    tempBlock,
            newStart: startTime,
            newEnd:   endTime
        )
    }

    // MARK: - Save

    private func addBlock() {
        guard let activity = selectedActivity else { return }

        let newBlock       = TimeBlock(activity: activity, startTime: startTime)
        newBlock.endTime   = endTime
        newBlock.stopState = "stopped"
        modelContext.insert(newBlock)

        // Create a Remark record if the user typed something
        let trimmed = remarkText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let remark = Remark(timeBlockID: newBlock.id, text: trimmed)
            modelContext.insert(remark)
        }

        try? modelContext.save()
        onSave()
        dismiss()
    }
}

