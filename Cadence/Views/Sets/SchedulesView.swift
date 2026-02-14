// ============================================================
// FILE: Cadence/Views/Sets/SchedulesView.swift  (NEW FILE)
// Replaces the "Time Blocks" section from SetsView.
// Renames all display-layer "Time Block" strings to "Schedule".
// The underlying TimeBlockRule model is NOT renamed.
// ============================================================

import SwiftUI
import SwiftData

// MARK: - SchedulesView

struct SchedulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var activitySets: [ActivitySet]
    @Query(sort: \TimeBlockRule.startTime) private var schedules: [TimeBlockRule]

    @State private var showingAddSchedule = false

    var body: some View {
        List {
            Section {
                if schedules.isEmpty {
                    Text("No schedules yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(schedules) { rule in
                    NavigationLink {
                        ScheduleEditView(rule: rule)
                    } label: {
                        ScheduleRuleRow(rule: rule, sets: activitySets)
                    }
                }
                .onDelete(perform: deleteSchedule)

                Button { showingAddSchedule = true } label: {
                    Label("Add Schedule", systemImage: "clock.badge.plus")
                }
            } footer: {
                Text("Schedules control when gaps are tracked and can automatically switch the active Activity Set.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Schedules")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { EditButton() }
        .sheet(isPresented: $showingAddSchedule) {
            AddScheduleView(sets: activitySets)
        }
    }

    private func deleteSchedule(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(schedules[index]) }
        try? modelContext.save()
    }
}

// MARK: - ScheduleRuleRow
// Renamed from TimeBlockRuleRow — logic unchanged.

struct ScheduleRuleRow: View {
    let rule: TimeBlockRule
    let sets: [ActivitySet]
    @Environment(\.modelContext) private var modelContext

    var linkedSetName: String {
        guard let id = rule.linkedSetID,
              let set = sets.first(where: { $0.id == id }) else { return "No set" }
        return set.name
    }

    var trackingModeColor: Color { rule.trackingMode == .on ? .red : .blue }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(rule.name).font(.headline)
                    HStack(spacing: 2) {
                        Image(systemName: rule.trackingMode.icon).font(.caption2)
                        Text(rule.trackingMode.displayName).font(.caption2)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(trackingModeColor.opacity(0.15))
                    .foregroundStyle(trackingModeColor)
                    .cornerRadius(4)
                }
                Text(rule.timeRangeDisplay)
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Text(rule.daysOfWeekDisplay)
                        .font(.caption).foregroundStyle(.secondary)
                    if rule.linkedSetID != nil && rule.trackingMode != .off {
                        Text("→ \(linkedSetName)")
                            .font(.caption).foregroundStyle(.blue)
                    }
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { rule.isEnabled = $0; try? modelContext.save() }
            ))
            .labelsHidden()
        }
    }
}

// MARK: - AddScheduleView
// Renamed from AddTimeBlockView — logic and form unchanged,
// only display strings updated.

struct AddScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let sets: [ActivitySet]

    @State private var name          = ""
    @State private var startTime     = Date()
    @State private var endTime       = Date()
    @State private var linkedSetID: UUID? = nil
    @State private var selectedDays: Set<Int> = []
    @State private var trackingMode: TrackingMode = .on

    let daysOfWeek = [
        (1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"),
        (5, "Thu"), (6, "Fri"), (7, "Sat")
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g., 'Work Hours')", text: $name)

                Section("Time Range") {
                    DatePicker("Start Time", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End Time",   selection: $endTime,   displayedComponents: .hourAndMinute)
                }

                Section {
                    Picker("Mode", selection: $trackingMode) {
                        Label("Tracking", systemImage: "clock.badge.checkmark").tag(TrackingMode.on)
                        Label("Paused",   systemImage: "clock.badge.xmark").tag(TrackingMode.off)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Tracking Mode")
                } footer: {
                    Text(trackingMode == .on
                         ? "Tracks activities and creates gaps"
                         : "Tracker is paused during this schedule")
                }

                Section {
                    Picker("Link to Activity Set", selection: $linkedSetID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(sets) { set in
                            Text(set.name).tag(set.id as UUID?)
                        }
                    }
                } header: {
                    Text("Auto-Switch")
                } footer: {
                    if trackingMode == .off {
                        Text("Auto-switch is disabled when tracking mode is Off")
                            .foregroundStyle(.orange)
                    } else {
                        Text("When this schedule starts, automatically switch to the selected Activity Set.")
                    }
                }

                Section {
                    if selectedDays.isEmpty {
                        Text("Every day").foregroundStyle(.secondary)
                    }
                    ForEach(daysOfWeek, id: \.0) { day in
                        Toggle(day.1, isOn: Binding(
                            get: { selectedDays.contains(day.0) },
                            set: { newValue in
                                if newValue { selectedDays.insert(day.0) }
                                else        { selectedDays.remove(day.0) }
                            }
                        ))
                    }
                } header: {
                    Text("Days of Week")
                } footer: {
                    Text("Leave all unchecked for every day, or select specific days.")
                }
            }
            .navigationTitle("New Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addSchedule() }
                        .disabled(name.isEmpty)
                }
            }
        }
    }

    private func addSchedule() {
        let rule = TimeBlockRule(
            name:         name,
            startTime:    startTime,
            endTime:      endTime,
            linkedSetID:  trackingMode == .off ? nil : linkedSetID,
            daysOfWeek:   Array(selectedDays),
            trackingMode: trackingMode
        )
        modelContext.insert(rule)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - ScheduleEditView
// Renamed from TimeBlockEditView — logic and form unchanged,
// only display strings updated.

struct ScheduleEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var sets: [ActivitySet]

    @Bindable var rule: TimeBlockRule

    @State private var selectedDays: Set<Int> = []

    let daysOfWeek = [
        (1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"),
        (5, "Thu"), (6, "Fri"), (7, "Sat")
    ]

    private var trackingModeFooter: String {
        switch rule.trackingMode {
        case .on:  return "Tracks activities and creates gaps"
        case .off: return "Tracker is paused during this schedule"
        }
    }

    var body: some View {
        Form {
            TextField("Name", text: $rule.name)

            Section("Time Range") {
                DatePicker("Start Time", selection: $rule.startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time",   selection: $rule.endTime,   displayedComponents: .hourAndMinute)
            }

            Section {
                Picker("Mode", selection: $rule.trackingMode) {
                    Label("Tracking", systemImage: "clock.badge.checkmark").tag(TrackingMode.on)
                    Label("Paused",   systemImage: "clock.badge.xmark").tag(TrackingMode.off)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Tracking Mode")
            } footer: {
                Text(trackingModeFooter)
            }

            Section {
                Picker("Link to Activity Set", selection: $rule.linkedSetID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(sets) { set in
                        Text(set.name).tag(set.id as UUID?)
                    }
                }
            } header: {
                Text("Auto-Switch")
            } footer: {
                if rule.trackingMode == .off {
                    Text("Auto-switch is disabled when tracking mode is Off")
                        .foregroundStyle(.orange)
                } else {
                    Text("When this schedule starts, automatically switch to the selected Activity Set.")
                }
            }

            Section {
                if selectedDays.isEmpty {
                    Text("Every day").foregroundStyle(.secondary)
                }
                ForEach(daysOfWeek, id: \.0) { day in
                    Toggle(day.1, isOn: Binding(
                        get: { selectedDays.contains(day.0) },
                        set: { newValue in
                            if newValue { selectedDays.insert(day.0) }
                            else        { selectedDays.remove(day.0) }
                            rule.daysOfWeek = Array(selectedDays)
                        }
                    ))
                }
            } header: {
                Text("Days of Week")
            } footer: {
                Text("Leave all unchecked for every day, or select specific days.")
            }

            Section {
                Toggle("Enabled", isOn: $rule.isEnabled)
            } footer: {
                Text("Disable to temporarily stop this schedule from activating.")
            }

            Section {
                Button("Delete Schedule", role: .destructive) {
                    modelContext.delete(rule)
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .navigationTitle("Edit Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { try? modelContext.save(); dismiss() }
            }
        }
        .onAppear { selectedDays = Set(rule.daysOfWeek) }
    }
}
