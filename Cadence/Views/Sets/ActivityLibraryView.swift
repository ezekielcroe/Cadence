// ============================================================
// FILE: Cadence/Views/Sets/ActivityLibraryView.swift
// ============================================================

import SwiftUI
import SwiftData

// MARK: - ActivityLibraryView

struct ActivityLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]

    @State private var showingAddActivity = false

    var body: some View {
        List {
            Section {
                ForEach(allActivities) { activity in
                    NavigationLink {
                        ActivityEditView(activity: activity)
                    } label: {
                        ActivityLibraryRow(activity: activity)
                    }
                }
                .onDelete(perform: deleteActivity)

                Button { showingAddActivity = true } label: {
                    Label("New Activity", systemImage: "plus.circle")
                }
            } footer: {
                Text("Activities live here independent of any set. Add them to one or more sets to make them available while tracking.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Activity Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { EditButton() }
        .sheet(isPresented: $showingAddActivity) { AddActivityView() }
    }

    private func deleteActivity(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(allActivities[index]) }
        try? modelContext.save()
    }
}

// MARK: - ActivityLibraryRow
// Moved here from SetsView.swift — still referenced by ActivitySetDetailView.

struct ActivityLibraryRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 12) {
            if let emoji = activity.emoji {
                Text(emoji).font(.title3).frame(width: 32)
            } else {
                Circle()
                    .fill(Color(hex: activity.color))
                    .frame(width: 20, height: 20)
                    .frame(width: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name)
                if !activity.sets.isEmpty {
                    Text(activity.sets.map { $0.name }.sorted().joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: activity.goal.icon)
                .font(.caption)
                .foregroundStyle(Color(hex: activity.goal.color))
        }
    }
}

// MARK: - AddActivityView
// Moved here from SetsView.swift.
// Creates a new Activity in the global library.
// If `targetSet` is provided, also adds it to that set on save.

struct AddActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    var targetSet: ActivitySet? = nil

    @State private var name          = ""
    @State private var emoji         = ""
    @State private var selectedColor = "#4CAF50"
    @State private var selectedGoal: ActivityGoal = .neutral

    let availableColors = [
        "#F44336", "#E91E63", "#9C27B0", "#673AB7",
        "#3F51B5", "#2196F3", "#03A9F4", "#00BCD4",
        "#009688", "#4CAF50", "#8BC34A", "#CDDC39",
        "#FFEB3B", "#FFC107", "#FF9800", "#FF5722",
        "#795548", "#607D8B", "#9E9E9E", "#000000"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Details"),
                        footer: Text("Add an emoji for easier identification")) {
                    TextField("Emoji (optional)", text: $emoji)
                        .onChange(of: emoji) { _, v in if v.count > 2 { emoji = String(v.prefix(2)) } }
                        .font(.system(size: 40))
                        .multilineTextAlignment(.center)
                    TextField("Activity Name", text: $name)
                }

                Section(header: Text("Productivity Goal"),
                        footer: Text("Helps reports determine if an increase in duration is good or bad.")) {
                    Picker("Goal", selection: $selectedGoal) {
                        ForEach(ActivityGoal.allCases, id: \.self) { goal in
                            HStack {
                                Image(systemName: goal.icon)
                                Text(goal.displayName)
                            }.tag(goal)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(header: Text("Color")) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 5),
                        spacing: 12
                    ) {
                        ForEach(availableColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle().stroke(
                                        Color.primary,
                                        lineWidth: selectedColor == color ? 3 : 0
                                    )
                                )
                                .onTapGesture { selectedColor = color }
                        }
                    }
                    .padding(.vertical, 8)
                }

                if let set = targetSet {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Will be added to \"\(set.name)\"")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addActivity() }
                        .disabled(name.isEmpty)
                }
            }
        }
    }

    private func addActivity() {
        let allDescriptor = FetchDescriptor<Activity>()
        let existingCount = (try? modelContext.fetchCount(allDescriptor)) ?? 0

        let activity = Activity(
            name:      name,
            color:     selectedColor,
            sortOrder: existingCount,
            emoji:     emoji.isEmpty ? nil : emoji,
            goal:      selectedGoal
        )
        modelContext.insert(activity)

        if let set = targetSet {
            set.activities.append(activity)
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - ActivityEditView
// Moved here from SetsView.swift.

struct ActivityEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Bindable var activity: Activity

    let availableColors = [
        "#F44336", "#E91E63", "#9C27B0", "#673AB7",
        "#3F51B5", "#2196F3", "#03A9F4", "#00BCD4",
        "#009688", "#4CAF50", "#8BC34A", "#CDDC39",
        "#FFEB3B", "#FFC107", "#FF9800", "#FF5722",
        "#795548", "#607D8B", "#9E9E9E", "#000000"
    ]

    var body: some View {
        Form {
            Section(header: Text("Details"),
                    footer: Text("Add an emoji for easier identification")) {
                TextField("Emoji (optional)", text: Binding(
                    get: { activity.emoji ?? "" },
                    set: { activity.emoji = $0.isEmpty ? nil : String($0.prefix(2)) }
                ))
                .font(.system(size: 40))
                .multilineTextAlignment(.center)
                TextField("Activity Name", text: $activity.name)
            }

            Section(header: Text("Productivity Goal"),
                    footer: Text("Helps reports determine if an increase in duration is good or bad.")) {
                Picker("Goal", selection: $activity.goal) {
                    ForEach(ActivityGoal.allCases, id: \.self) { goal in
                        HStack {
                            Image(systemName: goal.icon)
                            Text(goal.displayName)
                        }.tag(goal)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(header: Text("Color")) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 5),
                    spacing: 12
                ) {
                    ForEach(availableColors, id: \.self) { color in
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle().stroke(
                                    Color.primary,
                                    lineWidth: activity.color == color ? 3 : 0
                                )
                            )
                            .onTapGesture { activity.color = color }
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Sets") {
                if activity.sets.isEmpty {
                    Text("Not in any set").foregroundStyle(.secondary)
                } else {
                    ForEach(activity.sets.sorted { $0.name < $1.name }) { set in
                        HStack {
                            Text(set.name)
                            Spacer()
                            if set.isActive {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Edit Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { try? modelContext.save(); dismiss() }
            }
        }
    }
}
