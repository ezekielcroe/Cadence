//
//  SetsView.swift
//  Cadence
//

import SwiftUI
import SwiftData

struct SetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var activitySets: [ActivitySet]
    @Query private var activities: [Activity]
    @Query(sort: \TimeBlockRule.startTime) private var timeBlockRules: [TimeBlockRule]
    
    @State private var showingAddSet = false
    @State private var showingAddActivity = false
    @State private var showingAddTimeBlock = false
    @State private var selectedSetID: UUID?
    
    var activeSet: ActivitySet? {
        activitySets.first(where: { $0.isActive })
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Time Block Rules Section
                Section {
                    if timeBlockRules.isEmpty {
                        Text("No time blocks yet")
                            .foregroundStyle(.secondary)
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
                    
                    Button(action: { showingAddTimeBlock = true }) {
                        Label("Add Time Block", systemImage: "clock.badge.plus")
                    }
                } header: {
                    Text("Time Blocks")
                } footer: {
                    Text("Control when gaps are tracked and auto-switch activity sets")
                }
                
                // Activity Sets Section
                Section {
                    ForEach(activitySets) { set in
                        NavigationLink {
                            ActivitySetDetailView(set: set, activities: activities.filter { $0.setID == set.id })
                        } label: {
                            HStack {
                                Text(set.name)
                                
                                Spacer()
                                
                                if set.isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                                
                                Text("\(activitiesCount(for: set.id))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteSet)
                    
                    Button(action: { showingAddSet = true }) {
                        Label("Add Activity Set", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Activity Sets")
                } footer: {
                    Text("Create different sets of activities for different contexts")
                }
            }
            .navigationTitle("Sets")
            .toolbar {
                EditButton()
            }
            .sheet(isPresented: $showingAddSet) {
                AddActivitySetView()
            }
            .sheet(isPresented: $showingAddTimeBlock) {
                AddTimeBlockView(sets: activitySets)
            }
        }
    }
    
    private func activitiesCount(for setID: UUID) -> Int {
        activities.filter { $0.setID == setID }.count
    }
    
    private func deleteSet(at offsets: IndexSet) {
        for index in offsets {
            let set = activitySets[index]
            
            // Don't allow deleting the only set
            if activitySets.count == 1 {
                continue
            }
            
            // Delete associated activities
            let associatedActivities = activities.filter { $0.setID == set.id }
            for activity in associatedActivities {
                modelContext.delete(activity)
            }
            
            // If deleting active set, activate another one
            if set.isActive, let newActiveSet = activitySets.first(where: { $0.id != set.id }) {
                newActiveSet.isActive = true
            }
            
            modelContext.delete(set)
        }
        
        try? modelContext.save()
    }
    
    private func deleteTimeBlock(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(timeBlockRules[index])
        }
        try? modelContext.save()
    }
}

// MARK: - Time Block Rule Row
struct TimeBlockRuleRow: View {
    let rule: TimeBlockRule
    let sets: [ActivitySet]
    @Environment(\.modelContext) private var modelContext
    
    var linkedSetName: String {
        guard let setID = rule.linkedSetID,
              let set = sets.first(where: { $0.id == setID }) else {
            return "No set"
        }
        return set.name
    }
    
    var trackingModeColor: Color {
        switch rule.trackingMode {
        case .strict: return .red
        case .relaxed: return .blue
        case .off: return .gray
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(rule.name)
                        .font(.headline)
                    
                    // Tracking mode badge
                    HStack(spacing: 2) {
                        Image(systemName: rule.trackingMode.icon)
                            .font(.caption2)
                        Text(rule.trackingMode.displayName)
                            .font(.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(trackingModeColor.opacity(0.15))
                    .foregroundStyle(trackingModeColor)
                    .cornerRadius(4)
                }
                
                Text(rule.timeRangeDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Text(rule.daysOfWeekDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if rule.linkedSetID != nil && rule.trackingMode != .off {
                        Text("→ \(linkedSetName)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    rule.isEnabled = newValue
                    try? modelContext.save()
                }
            ))
            .labelsHidden()
        }
    }
}

// MARK: - Activity Set Detail View
struct ActivitySetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var set: ActivitySet
    let activities: [Activity]
    
    @State private var showingAddActivity = false
    
    var sortedActivities: [Activity] {
        activities.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    var body: some View {
        List {
            Section {
                TextField("Set Name", text: $set.name)
                
                Toggle("Active", isOn: Binding(
                    get: { set.isActive },
                    set: { newValue in
                        if newValue {
                            // Deactivate all other sets
                            let descriptor = FetchDescriptor<ActivitySet>()
                            if let allSets = try? modelContext.fetch(descriptor) {
                                allSets.forEach { $0.isActive = false }
                            }
                            set.isActive = true
                            try? modelContext.save()
                        }
                    }
                ))
            }
            
            Section {
                ForEach(sortedActivities) { activity in
                    NavigationLink {
                        ActivityEditView(activity: activity)
                    } label: {
                        HStack {
                            if let emoji = activity.emoji {
                                Text(emoji)
                                    .font(.title3)
                            }
                            
                            Circle()
                                .fill(Color(hex: activity.color))
                                .frame(width: 24, height: 24)
                            
                            Text(activity.name)
                        }
                    }
                }
                .onMove(perform: moveActivity)
                .onDelete(perform: deleteActivity)
                
                Button(action: { showingAddActivity = true }) {
                    Label("Add Activity", systemImage: "plus.circle")
                }
            } header: {
                Text("Activities")
            } footer: {
                Text("Drag to reorder, swipe to delete")
            }
        }
        .navigationTitle("Edit Set")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .sheet(isPresented: $showingAddActivity) {
            AddActivityView(setID: set.id)
        }
    }
    
    private func moveActivity(from source: IndexSet, to destination: Int) {
        var sorted = sortedActivities
        sorted.move(fromOffsets: source, toOffset: destination)
        
        for (index, activity) in sorted.enumerated() {
            activity.sortOrder = index
        }
        
        try? modelContext.save()
    }
    
    private func deleteActivity(_ indexSet: IndexSet) {
        for index in indexSet {
            modelContext.delete(sortedActivities[index])
        }
        try? modelContext.save()
    }
}

// MARK: - Add Activity Set View
struct AddActivitySetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Set Name", text: $name)
            }
            .navigationTitle("New Activity Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addSet()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func addSet() {
        let newSet = ActivitySet(name: name)
        modelContext.insert(newSet)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Add Activity View
struct AddActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let setID: UUID
    
    @State private var name = ""
    @State private var emoji = ""
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
                Section(header: Text("Details"), footer: Text("Tap 🌐 on keyboard to add emoji for easier identification")) {
                    TextField("Emoji (optional)", text: $emoji)
                        .onChange(of: emoji) { _, newValue in
                            if newValue.count > 2 {
                                emoji = String(newValue.prefix(2))
                            }
                        }
                        .font(.system(size: 40))
                        .multilineTextAlignment(.center)
                    
                    TextField("Activity Name", text: $name)
                }
                
                // FIXED: Use explicit header/footer to fix compilation error
                Section(header: Text("Productivity Goal"), footer: Text("Helps reports determine if an increase in duration is good or bad.")) {
                    Picker("Goal", selection: $selectedGoal) {
                        ForEach(ActivityGoal.allCases, id: \.self) { goal in
                            HStack {
                                Image(systemName: goal.icon)
                                Text(goal.displayName)
                            }
                            .tag(goal)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // FIXED: Explicit header for Color section
                Section(header: Text("Color")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(availableColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                    .padding(.vertical, 8)
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
        let descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate<Activity> { $0.setID == setID }
        )
        let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        
        let newActivity = Activity(
            name: name,
            color: selectedColor,
            setID: setID,
            sortOrder: existingCount,
            emoji: emoji.isEmpty ? nil : emoji,
            goal: selectedGoal
        )
        
        modelContext.insert(newActivity)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Activity Edit View
struct ActivityEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
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
            Section(header: Text("Details"), footer: Text("Tap 🌐 on keyboard to add emoji for easier identification")) {
                TextField("Emoji (optional)", text: Binding(
                    get: { activity.emoji ?? "" },
                    set: { newValue in
                        let trimmed = newValue.isEmpty ? nil : String(newValue.prefix(2))
                        activity.emoji = trimmed
                    }
                ))
                .font(.system(size: 40))
                .multilineTextAlignment(.center)
                
                TextField("Activity Name", text: $activity.name)
            }
            
            // FIXED: Explicit header/footer
            Section(header: Text("Productivity Goal"), footer: Text("Helps reports determine if an increase in duration is good or bad.")) {
                Picker("Goal", selection: $activity.goal) {
                    ForEach(ActivityGoal.allCases, id: \.self) { goal in
                        HStack {
                            Image(systemName: goal.icon)
                            Text(goal.displayName)
                        }
                        .tag(goal)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // FIXED: Explicit header
            Section(header: Text("Color")) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(availableColors, id: \.self) { color in
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: activity.color == color ? 3 : 0)
                            )
                            .onTapGesture {
                                activity.color = color
                            }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Edit Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Activity.self, ActivitySet.self, TimeBlock.self, TimeBlockRule.self, configurations: config)
    
    return SetsView()
        .modelContainer(container)
}
