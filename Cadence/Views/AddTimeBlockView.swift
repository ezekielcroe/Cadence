//
//  AddTimeBlockView.swift
//  Cadence
//

import SwiftUI
import SwiftData

// MARK: - Add Time Block View
struct AddTimeBlockView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let sets: [ActivitySet]
    
    @State private var name = ""
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var linkedSetID: UUID? = nil
    @State private var selectedDays: Set<Int> = []
    @State private var trackingMode: TrackingMode = .relaxed
    
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
                    DatePicker("End Time", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                
                // Tracking Mode
                Section {
                    Picker("Tracking Mode", selection: $trackingMode) {
                        ForEach(TrackingMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Tracking Mode")
                } footer: {
                    Text(trackingModeFooter)
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
                        Text("When this time block starts, automatically switch to the selected activity set")
                    }
                }
                
                Section {
                    if selectedDays.isEmpty {
                        Text("Every day")
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(daysOfWeek, id: \.0) { day in
                        Toggle(day.1, isOn: Binding(
                            get: { selectedDays.contains(day.0) },
                            set: { newValue in
                                if newValue {
                                    selectedDays.insert(day.0)
                                } else {
                                    selectedDays.remove(day.0)
                                }
                            }
                        ))
                    }
                } header: {
                    Text("Days of Week")
                } footer: {
                    Text("Leave all unchecked for every day, or select specific days")
                }
            }
            .navigationTitle("New Time Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addTimeBlock()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private var trackingModeFooter: String {
        switch trackingMode {
        case .strict:
            return "Track activities and gaps. Best for work hours."
        case .relaxed:
            return "Track activities but no gaps. Best for personal time."
        case .off:
            return "Manual tracking only. Best for sleep or downtime."
        }
    }
    
    private func addTimeBlock() {
        let rule = TimeBlockRule(
            name: name,
            startTime: startTime,
            endTime: endTime,
            linkedSetID: trackingMode == .off ? nil : linkedSetID,
            daysOfWeek: Array(selectedDays),
            trackingMode: trackingMode
        )
        
        modelContext.insert(rule)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Edit Time Block View
struct TimeBlockEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var sets: [ActivitySet]
    
    @Bindable var rule: TimeBlockRule
    
    @State private var selectedDays: Set<Int> = []
    
    let daysOfWeek = [
        (1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"),
        (5, "Thu"), (6, "Fri"), (7, "Sat")
    ]
    
    var body: some View {
        Form {
            TextField("Name", text: $rule.name)
            
            Section("Time Range") {
                DatePicker("Start Time", selection: $rule.startTime, displayedComponents: .hourAndMinute)
                DatePicker("End Time", selection: $rule.endTime, displayedComponents: .hourAndMinute)
            }
            
            // Tracking Mode
            Section {
                Picker("Tracking Mode", selection: Binding(
                    get: { rule.trackingMode },
                    set: { rule.trackingMode = $0 }
                )) {
                    ForEach(TrackingMode.allCases, id: \.self) { mode in
                        Label(mode.displayName, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.menu)
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
                    Text("When this time block starts, automatically switch to the selected activity set")
                }
            }
            
            Section {
                if selectedDays.isEmpty {
                    Text("Every day")
                        .foregroundStyle(.secondary)
                }
                
                ForEach(daysOfWeek, id: \.0) { day in
                    Toggle(day.1, isOn: Binding(
                        get: { selectedDays.contains(day.0) },
                        set: { newValue in
                            if newValue {
                                selectedDays.insert(day.0)
                            } else {
                                selectedDays.remove(day.0)
                            }
                            // Update rule
                            rule.daysOfWeek = Array(selectedDays)
                        }
                    ))
                }
            } header: {
                Text("Days of Week")
            } footer: {
                Text("Leave all unchecked for every day, or select specific days")
            }
            
            Section {
                Toggle("Enabled", isOn: $rule.isEnabled)
            } footer: {
                Text("Disable to temporarily stop this time block from activating")
            }
            
            Section {
                Button("Delete Time Block", role: .destructive) {
                    modelContext.delete(rule)
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .navigationTitle("Edit Time Block")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .onAppear {
            selectedDays = Set(rule.daysOfWeek)
        }
    }
    
    private var trackingModeFooter: String {
        switch rule.trackingMode {
        case .strict:
            return "Track activities and gaps. Best for work hours."
        case .relaxed:
            return "Track activities but no gaps. Best for personal time."
        case .off:
            return "Manual tracking only. Best for sleep or downtime."
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Activity.self, ActivitySet.self, TimeBlock.self, TimeBlockRule.self, configurations: config)
    let context = container.mainContext
    
    let workSet = ActivitySet(name: "Work", isActive: true)
    context.insert(workSet)
    
    return AddTimeBlockView(sets: [workSet])
        .modelContainer(container)
}
