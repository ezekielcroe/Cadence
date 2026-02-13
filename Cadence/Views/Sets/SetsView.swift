import SwiftUI
import SwiftData

// MARK: - SetsView

struct SetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var activitySets:   [ActivitySet]
    @Query(sort: \Activity.sortOrder)  private var allActivities: [Activity]
    @Query(sort: \TimeBlockRule.startTime) private var timeBlockRules: [TimeBlockRule]

    @State private var showingAddSet       = false
    @State private var showingAddActivity  = false
    @State private var showingAddTimeBlock = false

    var body: some View {
        NavigationStack {
            List {

                // MARK: Time Blocks
                Section {
                    if timeBlockRules.isEmpty {
                        Text("No time blocks yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(timeBlockRules) { rule in
                            NavigationLink {
                                TimeBlockEditView(rule: rule)
                            } label: {
                                TimeBlockRuleRow(rule: rule, sets: activitySets)
                            }
                        }
                        .onDelete(perform: deleteTimeBlock)
                    }
                    Button { showingAddTimeBlock = true } label: {
                        Label("Add Time Block", systemImage: "clock.badge.plus")
                    }
                } header: {
                    Text("Time Blocks")
                } footer: {
                    Text("Control when gaps are tracked and auto-switch activity sets.")
                }

                // MARK: Activity Sets
                Section {
                    ForEach(activitySets) { set in
                        NavigationLink {
                            ActivitySetDetailView(activitySet: set, allActivities: allActivities)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(set.name).font(.body)
                                    Text("\(set.activities.count) activities")
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
                } header: {
                    Text("Activity Sets")
                } footer: {
                    Text("Each set is a palette of activities for a specific context. The same activity can appear in multiple sets.")
                }

                // MARK: Activity Library
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
                } header: {
                    Text("Activity Library")
                } footer: {
                    Text("All your activities live here. Add them to sets to build palettes for different contexts.")
                }
            }
            .navigationTitle("Sets")
            .toolbar { EditButton() }
            .sheet(isPresented: $showingAddSet)       { AddActivitySetView() }
            .sheet(isPresented: $showingAddTimeBlock) { AddTimeBlockView(sets: activitySets) }
            .sheet(isPresented: $showingAddActivity)  { AddActivityView() }
        }
    }

    // MARK: - Deletions

    private func deleteSet(at offsets: IndexSet) {
        for index in offsets {
            let set = activitySets[index]
            guard activitySets.count > 1 else { continue }
            if set.isActive, let next = activitySets.first(where: { $0.id != set.id }) {
                next.isActive = true
            }
            // Activities stay in the library — only the set is removed
            modelContext.delete(set)
        }
        try? modelContext.save()
    }

    private func deleteActivity(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(allActivities[index]) }
        try? modelContext.save()
    }

    private func deleteTimeBlock(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(timeBlockRules[index]) }
        try? modelContext.save()
    }
}

// MARK: - Activity Library Row

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

// MARK: - Activity Set Detail View

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
            // MARK: Set Config
            Section {
                TextField("Set Name", text: $activitySet.name)

                Toggle("Active", isOn: Binding(
                    get: { activitySet.isActive },
                    set: { newValue in
                        if newValue {
                            // Deactivate all other sets
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

            // MARK: Activities in this Set
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

            // MARK: Add Activities
            Section {
                Button {
                    showingAddToSet = true
                } label: {
                    Label("Add from Library", systemImage: "text.badge.plus")
                }

                Button {
                    showingNewActivity = true
                } label: {
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

// MARK: - Add to Set Sheet
//
// Shows all library activities NOT already in this set. Tap to toggle membership.

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
                            if selectedIDs.contains(activity.id) {
                                selectedIDs.remove(activity.id)
                            } else {
                                selectedIDs.insert(activity.id)
                            }
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

// MARK: - Add Activity Set View

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
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { addSet() }.disabled(name.isEmpty)
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

// MARK: - Add Activity View
//
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
                Section(header: Text("Details"), footer: Text("Add an emoji for easier identification")) {
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
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(availableColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 44, height: 44)
                                .overlay(Circle().stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0))
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addActivity() }.disabled(name.isEmpty)
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

// MARK: - Activity Edit View (unchanged logic, no setID)

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
            Section(header: Text("Details"), footer: Text("Add an emoji for easier identification")) {
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
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(availableColors, id: \.self) { color in
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color.primary, lineWidth: activity.color == color ? 3 : 0))
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

// MARK: - Time Block Rule Row (unchanged)

struct TimeBlockRuleRow: View {
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
                Text(rule.timeRangeDisplay).font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Text(rule.daysOfWeekDisplay).font(.caption).foregroundStyle(.secondary)
                    if rule.linkedSetID != nil && rule.trackingMode != .off {
                        Text("→ \(linkedSetName)").font(.caption).foregroundStyle(.blue)
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

// MARK: - Preview

#Preview {
    let config    = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Activity.self, ActivitySet.self, TimeBlock.self, TimeBlockRule.self,
             Remark.self, DayNote.self,
        configurations: config
    )
    let ctx = container.mainContext

    let work    = ActivitySet(name: "Work",    isActive: true)
    let leisure = ActivitySet(name: "Leisure", isActive: false)
    ctx.insert(work); ctx.insert(leisure)

    let deepWork = Activity(name: "Deep Work", color: "#4CAF50")
    let email    = Activity(name: "Email",     color: "#FF9800")
    let reading  = Activity(name: "Reading",   color: "#2196F3")
    ctx.insert(deepWork); ctx.insert(email); ctx.insert(reading)

    work.activities    = [deepWork, email]
    leisure.activities = [reading, deepWork]   // Deep Work in both sets

    return SetsView().modelContainer(container)
}
