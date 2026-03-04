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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(rule.name).font(.headline)
                }
                Text(rule.timeRangeDisplay)
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Text(rule.daysOfWeekDisplay)
                        .font(.caption).foregroundStyle(.secondary)
                        
                    if rule.linkedSetID != nil {
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
                    Picker("Link to Activity Set", selection: $linkedSetID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(sets) { set in
                            Text(set.name).tag(set.id as UUID?)
                        }
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
            daysOfWeek:   Array(selectedDays),
        )
        modelContext.insert(rule)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - ScheduleEditView
// Renamed from TimeBlockEditView — logic and form unchanged,
// only display strings updated.

// ============================================================
// FILE: Cadence/Views/Sets/SchedulesView.swift
// Refactored to eliminate explicit Tracking Mode selection.
// ============================================================

import SwiftUI
import SwiftData

struct ScheduleEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var activitySets: [ActivitySet]
    
    @Bindable var rule: TimeBlockRule
    @State private var selectedDays: Set<Int> = []

    let daysOfWeek = [
        (1, "Sunday"), (2, "Monday"), (3, "Tuesday"),
        (4, "Wednesday"), (5, "Thursday"), (6, "Friday"), (7, "Saturday")
    ]

    var body: some View {
        Form {
            Section {
                TextField("Schedule Name", text: $rule.name)
            } header: {
                Text("Name")
            }

            Section {
                DatePicker("Start Time", selection: $rule.startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time", selection: $rule.endTime, displayedComponents: .hourAndMinute)
            } header: {
                Text("Time Range")
            }

            // MARK: - Refactored Context Association
            // The logic controlling tracking mode state has been removed entirely.
            // This now solely dictates which context the app switches to.
            Section {
                Picker("Activity Set", selection: $rule.linkedSetID) {
                    Text("None").tag(UUID?.none)
                    ForEach(activitySets) { set in
                        Text(set.name).tag(UUID?.some(set.id))
                    }
                }
            } header: {
                Text("Associated Set")
            } footer: {
                Text("When this schedule is active, the app will automatically track gaps and switch to this set's assigned Entry Mode.")
            }

            // MARK: - Schedules & Enabling Toggles
            Section {
                HStack {
                    Text("Selected Days:")
                    Spacer()
                    Text(selectedDays.isEmpty ? "Every day" : "\(selectedDays.count) days")
                        .foregroundStyle(.secondary)
                }
                ForEach(daysOfWeek, id: \.0) { day in
                    Toggle(day.1, isOn: Binding(
                        get: { selectedDays.contains(day.0) },
                        set: { newValue in
                            if newValue { selectedDays.insert(day.0) }
                            else { selectedDays.remove(day.0) }
                            rule.daysOfWeek = Array(selectedDays).sorted()
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
                Button("Done") {
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .onAppear { selectedDays = Set(rule.daysOfWeek) }
    }
}
