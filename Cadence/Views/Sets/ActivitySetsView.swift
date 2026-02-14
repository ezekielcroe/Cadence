// ============================================================
// FILE: Cadence/Views/Sets/ActivitySetsView.swift
// ============================================================

import SwiftUI
import SwiftData

// MARK: - ActivitySetsView

struct ActivitySetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var activitySets: [ActivitySet]
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]

    @State private var showingAddSet = false

    var body: some View {
        List {
            Section {
                ForEach(activitySets) { set in
                    NavigationLink {
                        ActivitySetDetailView(activitySet: set, allActivities: allActivities)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(set.name).font(.body)
                                Text("\(set.activities.count) activit\(set.activities.count == 1 ? "y" : "ies")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if set.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteSet)

                Button { showingAddSet = true } label: {
                    Label("Add Set", systemImage: "plus.circle")
                }
            } footer: {
                Text("Each set is a palette of activities for a specific context. The same activity can appear in multiple sets.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Activity Sets")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { EditButton() }
        .sheet(isPresented: $showingAddSet) { AddActivitySetView() }
    }

    private func deleteSet(at offsets: IndexSet) {
        for index in offsets {
            let set = activitySets[index]
            guard activitySets.count > 1 else { continue }
            if set.isActive, let next = activitySets.first(where: { $0.id != set.id }) {
                next.isActive = true
            }
            modelContext.delete(set)
        }
        try? modelContext.save()
    }
}

// MARK: - ActivitySetDetailView
// Moved here from SetsView.swift.

struct ActivitySetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var activitySet: ActivitySet
    let allActivities: [Activity]

    @State private var showingAddToSet    = false
    @State private var showingNewActivity = false

    private var sortedActivities: [Activity] {
        activitySet.activities.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section {
                TextField("Set Name", text: $activitySet.name)

                Toggle("Active", isOn: Binding(
                    get: { activitySet.isActive },
                    set: { newValue in
                        if newValue {
                            let descriptor = FetchDescriptor<ActivitySet>()
                            if let allSets = try? modelContext.fetch(descriptor) {
                                for s in allSets where s.id != activitySet.id { s.isActive = false }
                            }
                        }
                        activitySet.isActive = newValue
                        try? modelContext.save()
                    }
                ))
            } header: {
                Text("Set Info")
            }

            Section {
                if sortedActivities.isEmpty {
                    Text("No activities yet — add some below.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(sortedActivities) { activity in
                        NavigationLink {
                            ActivityEditView(activity: activity)
                        } label: {
                            ActivityLibraryRow(activity: activity)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                removeFromSet(activity)
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            .tint(.orange)
                        }
                    }
                }
            } header: {
                Text("Activities")
            } footer: {
                Text("Swipe left to remove an activity from this set. The activity stays in the library.")
            }

            Section {
                Button { showingAddToSet    = true } label: {
                    Label("Add from Library",    systemImage: "text.badge.plus")
                }
                Button { showingNewActivity = true } label: {
                    Label("Create New Activity", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle(activitySet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { try? modelContext.save() } label: {
                    Text("Done").fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showingAddToSet) {
            AddToSetSheet(set: activitySet, allActivities: allActivities)
        }
        .sheet(isPresented: $showingNewActivity) {
            AddActivityView(targetSet: activitySet)
        }
    }

    private func removeFromSet(_ activity: Activity) {
        activitySet.activities.removeAll { $0.id == activity.id }
        try? modelContext.save()
    }
}

// MARK: - AddToSetSheet
// Moved here from SetsView.swift.
// Shows all library activities NOT already in this set.

struct AddToSetSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @Bindable var set: ActivitySet
    let allActivities: [Activity]

    @State private var selectedIDs: Set<UUID> = []

    private var availableActivities: [Activity] {
        let existingIDs = Set(set.activities.map { $0.id })
        return allActivities.filter { !existingIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableActivities.isEmpty {
                    ContentUnavailableView(
                        "All activities added",
                        systemImage: "checkmark.circle",
                        description: Text("Every activity in your library is already in this set.")
                    )
                } else {
                    List(availableActivities) { activity in
                        Button {
                            if selectedIDs.contains(activity.id) { selectedIDs.remove(activity.id) }
                            else { selectedIDs.insert(activity.id) }
                        } label: {
                            HStack {
                                ActivityLibraryRow(activity: activity)
                                Spacer()
                                if selectedIDs.contains(activity.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Add to \(set.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedIDs.count))") { addSelected() }
                        .fontWeight(.semibold)
                        .disabled(selectedIDs.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addSelected() {
        let toAdd = allActivities.filter { selectedIDs.contains($0.id) }
        for activity in toAdd {
            if !set.activities.contains(where: { $0.id == activity.id }) {
                set.activities.append(activity)
            }
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - AddActivitySetView
// Moved here from SetsView.swift.

struct AddActivitySetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form { TextField("Set Name", text: $name) }
                .navigationTitle("New Activity Set")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { addSet() }
                            .disabled(name.isEmpty)
                    }
                }
        }
    }

    private func addSet() {
        modelContext.insert(ActivitySet(name: name))
        try? modelContext.save()
        dismiss()
    }
}
