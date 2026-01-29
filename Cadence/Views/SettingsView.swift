import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingBackgroundSettings = false
    
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
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.2.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("Phase 1")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
                
                // Info Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Activity Sets & Time Blocks")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Go to the Sets tab to manage your activity sets and time block rules")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Quick Tip")
                }
            }
            .navigationTitle("Settings")
        }
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
        ("10 minutes", 600),
        ("15 minutes", 900),
        ("30 minutes", 1800),
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
                Picker("Duration", selection: $selectedDuration) {
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

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Activity.self, ActivitySet.self, TimeBlock.self, TimeBlockRule.self, configurations: config)
    
    return SettingsView()
        .modelContainer(container)
}
