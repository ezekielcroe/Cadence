import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var activitySets: [ActivitySet]
    @Query private var activities: [Activity]
    
    @State private var showingAddSet = false
    @State private var showingAddActivity = false
    @State private var selectedSetID: UUID?
    @State private var showingBackgroundSettings = false
    
    var activeSet: ActivitySet? {
        activitySets.first(where: { $0.isActive })
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Background Tracking Section
                Section {
                    NavigationLink {
                        BackgroundSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "clock.badge")
                                .foregroundStyle(.blue)
                            Text("Background Tracking")
                        }
                    }
                } header: {
                    Text("Tracking Settings")
                } footer: {
                    Text("Configure how long activities continue tracking when app is in background")
                }
                
                // Activity Sets Section
                Section {
                    ForEach(activitySets) { set in
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            setActiveSet(set)
                        }
                    }
                    .onDelete(perform: deleteSet)
                    
                    Button(action: { showingAddSet = true }) {
                        Label("Add Activity Set", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Activity Sets")
                } footer: {
                    Text("Switch between different sets of activities for work, personal time, etc.")
                }
                
                // Activities Section
                if let activeSet = activeSet {
                    Section {
                        ForEach(activitiesForSet(activeSet.id)) { activity in
                            NavigationLink {
                                ActivityEditView(activity: activity)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: activity.color))
                                        .frame(width: 24, height: 24)
                                    
                                    Text(activity.name)
                                }
                            }
                        }
                        .onMove(perform: moveActivity)
                        .onDelete { indexSet in
                            deleteActivity(indexSet, from: activeSet.id)
                        }
                        
                        Button(action: {
                            selectedSetID = activeSet.id
                            showingAddActivity = true
                        }) {
                            Label("Add Activity", systemImage: "plus.circle")
                        }
                    } header: {
                        Text("Activities in \(activeSet.name)")
                    } footer: {
                        Text("Tap to edit, swipe to delete, or drag to reorder")
                    }
                }
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.1.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                EditButton()
            }
            .sheet(isPresented: $showingAddSet) {
                AddActivitySetView()
            }
            .sheet(isPresented: $showingAddActivity) {
                if let setID = selectedSetID {
                    AddActivityView(setID: setID)
                }
            }
        }
    }
    
    private func activitiesCount(for setID: UUID) -> Int {
        activities.filter { $0.setID == setID }.count
    }
    
    private func activitiesForSet(_ setID: UUID) -> [Activity] {
        activities.filter { $0.setID == setID }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    private func setActiveSet(_ set: ActivitySet) {
        for s in activitySets {
            s.isActive = (s.id == set.id)
        }
        try? modelContext.save()
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
    
    private func deleteActivity(_ indexSet: IndexSet, from setID: UUID) {
        let setActivities = activitiesForSet(setID)
        for index in indexSet {
            modelContext.delete(setActivities[index])
        }
        try? modelContext.save()
    }
    
    private func moveActivity(from source: IndexSet, to destination: Int) {
        guard let activeSet = activeSet else { return }
        
        var setActivities = activitiesForSet(activeSet.id)
        setActivities.move(fromOffsets: source, toOffset: destination)
        
        for (index, activity) in setActivities.enumerated() {
            activity.sortOrder = index
        }
        
        try? modelContext.save()
    }
}

// MARK: - Background Settings View
struct BackgroundSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var timeTrackingManager: TimeTrackingManager?
    @State private var selectedDuration: TimeInterval = 3600
    @State private var notificationsEnabled = false
    @State private var showingPermissionAlert = false
    
    let durationOptions: [(label: String, value: TimeInterval)] = [
        ("5 minutes", 300),
        ("10 minutes", 600),
        ("30 minutes", 900),
        ("45 minutes", 2700),
        ("1 hour", 3600),
        ("2 hours", 7200),
        ("Never stop", .infinity)
    ]
    
    var body: some View {
        Form {
            Section {
                Text("When you background the app, the current activity continues tracking. Set a maximum duration after which the activity will automatically stop.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                Picker("Maximum Background Duration", selection: $selectedDuration) {
                    ForEach(durationOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: selectedDuration) { _, newValue in
                    timeTrackingManager?.saveMaxBackgroundDuration(newValue)
                }
            } header: {
                Text("Auto-Stop Duration")
            } footer: {
                if selectedDuration == .infinity {
                    Text("Activity will continue tracking indefinitely while in background")
                } else {
                    Text("Activity will stop after \(selectedDuration.formattedDuration) in background")
                }
            }
            
            Section {
                Toggle("Reminder Notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        if newValue {
                            requestNotificationPermission()
                        }
                    }
                
                if notificationsEnabled && selectedDuration != .infinity && selectedDuration > 300 {
                    HStack {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.orange)
                        Text("You'll receive a reminder 5 minutes before activity stops")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Get notified before your activity stops in background")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("How Background Tracking Works", systemImage: "info.circle")
                        .font(.headline)
                    
                    Text("• When you background the app, we record the timestamp")
                    Text("• When you return, we calculate elapsed time and add it to your activity")
                    Text("• This doesn't drain battery - no actual background processing happens")
                    Text("• To switch activities, you must open the app")
                    
                    if selectedDuration != .infinity {
                        Text("\n• If you're away longer than \(selectedDuration.formattedDuration), the activity stops at that time")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Background Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            timeTrackingManager = TimeTrackingManager(modelContext: modelContext)
            selectedDuration = timeTrackingManager?.maxBackgroundDuration ?? 3600
            checkNotificationPermission()
        }
        .alert("Notifications Disabled", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                notificationsEnabled = false
            }
        } message: {
            Text("Please enable notifications in Settings to receive activity reminders")
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    notificationsEnabled = true
                } else {
                    notificationsEnabled = false
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
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
    @State private var selectedColor = "#4CAF50"
    
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
                TextField("Activity Name", text: $name)
                
                Section("Color") {
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addActivity()
                    }
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
            sortOrder: existingCount
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
            TextField("Activity Name", text: $activity.name)
            
            Section("Color") {
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

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Activity.self, ActivitySet.self, TimeBlock.self, configurations: config)
    
    return SettingsView()
        .modelContainer(container)
}
