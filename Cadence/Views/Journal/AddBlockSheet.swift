// ============================================================
// FILE: Cadence/Views/Journal/AddBlockSheet.swift
// ============================================================

import SwiftUI
import SwiftData

struct AddBlockSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    let date:              Date
    let conflictDetector:  ConflictDetector
    let onSave:            () -> Void

    @Query private var activities:   [Activity]
    @Query private var activitySets: [ActivitySet]

    @State private var selectedActivity: Activity?
    @State private var selectedSet:      ActivitySet?   // NEW: two-step selection
    @State private var startTime:        Date
    @State private var endTime:          Date
    @State private var remarkText        = ""
    @State private var validationResult: ValidationResult?

    // FIX: Accept an optional prefilled gap to populate times immediately
    init(date: Date, prefilledGap: ComputedGap? = nil, conflictDetector: ConflictDetector, onSave: @escaping () -> Void) {
        self.date             = date
        self.conflictDetector = conflictDetector
        self.onSave           = onSave

        if let gap = prefilledGap {
            _startTime = State(initialValue: gap.start)
            _endTime   = State(initialValue: gap.end)
        } else {
            let calendar   = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            let startOfHour = calendar.date(from: components) ?? Date()

            _startTime = State(initialValue: startOfHour)
            _endTime   = State(initialValue: startOfHour.addingTimeInterval(3600))
        }
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

    /// Activities belonging to the currently selected set, sorted by name.
    private var activitiesForSelectedSet: [Activity] {
        guard let set = selectedSet else { return [] }
        return activities
            .filter { $0.sets.contains(where: { $0.id == set.id }) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Activity — two-step: pick set, then pick activity
                Section("Activity") {
                    if let activity = selectedActivity {
                        // Show selected activity with Change button
                        HStack {
                            if let emoji = activity.emoji { Text(emoji) }
                            Circle()
                                .fill(Color(hex: activity.color))
                                .frame(width: 20, height: 20)
                            Text(activity.name)
                            Spacer()
                            Button("Change") {
                                selectedActivity = nil
                                selectedSet = nil
                            }
                            .font(.caption)
                        }
                    } else if let set = selectedSet {
                        // Step 2: Show activities in the chosen set
                        HStack {
                            Text(set.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Back") { selectedSet = nil }
                                .font(.caption)
                        }

                        if activitiesForSelectedSet.isEmpty {
                            Text("No activities in this set")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(activitiesForSelectedSet) { activity in
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
                    } else {
                        // Step 1: Show activity sets
                        ForEach(activitySets.sorted(by: { $0.name < $1.name })) { set in
                            Button {
                                selectedSet = set
                            } label: {
                                HStack {
                                    Text(set.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if set.isActive {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        if activitySets.isEmpty {
                            Text("No activity sets configured")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                // MARK: Time — full date + time pickers
                Section("Time") {
                    DatePicker("Start", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: startTime) { _, _ in validate() }

                    DatePicker("End", selection: $endTime, displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: endTime) { _, _ in validate() }

                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(duration > 0 ? duration.formattedDuration : "—")
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
                    TextField("Optional remark… (#tags supported)", text: $remarkText, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Remark")
                } footer: {
                    Text("Saved as a remark attached to this block.")
                }
            }
            .navigationTitle("Add Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear { validate() }
        }
        .presentationDetents([.large])
    }

    // MARK: - Actions

    private func validate() {
        guard let activity = selectedActivity else {
            validationResult = nil
            return
        }
        _ = activity  // suppress unused warning; activity selection gates canSave
        validationResult = conflictDetector.validateEdit(
            block: TimeBlock(
                activityID: selectedActivity?.id,
                activityName: selectedActivity?.name ?? "",
                activityColor: selectedActivity?.color ?? "#000000",
                activitySetID: nil,
                startTime: startTime
            ),
            newStart: startTime,
            newEnd: endTime
        )
    }

    private func save() {
        guard let activity = selectedActivity else { return }

        let block = TimeBlock(
            activityID: activity.id,
            activityName: activity.name,
            activityColor: activity.color,
            activitySetID: activity.sets.first(where: { $0.isActive })?.id,
            startTime: startTime
        )
        block.endTime   = endTime
        block.stopState = "stopped"
        modelContext.insert(block)

        let trimmed = remarkText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let remark = Remark(timeBlockID: block.id, text: trimmed)
            modelContext.insert(remark)
        }

        try? modelContext.save()
        onSave()
        dismiss()
    }
}
