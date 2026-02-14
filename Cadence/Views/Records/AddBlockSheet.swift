// ============================================================
// FILE: Cadence/Views/Records/AddBlockSheet.swift

// Change: Added `spansNextDay` Bool state and a "Spans midnight" toggle.
// When toggled on, the end time is interpreted as being on the next calendar
// day. The duration display and Save validation update accordingly.
// No changes to the conflict detection or save logic — those already accept
// cross-day ranges now that ConflictDetector.exceedsDayBoundary is removed.
// ============================================================

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
    @State private var spansNextDay      = false    // "Spans midnight" toggle
    @State private var remarkText        = ""
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

    /// The resolved end time. When spansNextDay is on, the end DatePicker's
    /// hour/minute value is applied to the day after startTime.
    private var resolvedEndTime: Date {
        guard spansNextDay else { return endTime }
        let cal         = Calendar.current
        let nextDay     = cal.date(byAdding: .day, value: 1, to: startTime)!
        let endComps    = cal.dateComponents([.hour, .minute], from: endTime)
        return cal.date(bySettingHour: endComps.hour ?? 0,
                        minute:        endComps.minute ?? 0,
                        second:        0,
                        of:            nextDay) ?? nextDay
    }

    private var duration: TimeInterval {
        resolvedEndTime.timeIntervalSince(startTime)
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
                        .onChange(of: startTime) { _, _ in validate() }

                    Toggle(isOn: $spansNextDay) {
                        Label("Spans midnight", systemImage: "moon.fill")
                    }
                    .tint(.indigo)
                    .onChange(of: spansNextDay) { _, _ in validate() }

                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                        .onChange(of: endTime) { _, _ in validate() }

                    HStack {
                        Text("Duration")
                        Spacer()
                        if spansNextDay {
                            Text("next day · \(duration > 0 ? duration.formattedDuration : "—")")
                                .foregroundStyle(duration > 0 ? Color.secondary : Color.red)
                                .monospacedDigit()
                        } else {
                            Text(duration > 0 ? duration.formattedDuration : "—")
                                .foregroundStyle(duration > 0 ? Color.primary : Color.red)
                                .monospacedDigit()
                        }
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
            newEnd: resolvedEndTime
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
        block.endTime   = resolvedEndTime
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
