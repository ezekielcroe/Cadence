import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    
    // State variables for day boundaries
    @State private var startHour: Int = 6
    @State private var endHour: Int = 23
    @State private var manager: TimeTrackingManager?
    
    var body: some View {
        NavigationStack {
            Form {
                // Version Info
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
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
                
                // Day Boundaries Section
                Section {
                    Picker("Start of Day", selection: $startHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour)).tag(hour)
                        }
                    }
                    
                    Picker("End of Day", selection: $endHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour)).tag(hour)
                        }
                    }
                } header: {
                    Text("Day Boundaries")
                } footer: {
                    Text("These times define your tracking day for reports. Activities outside these hours are tracked but grouped separately.")
                }
                .onChange(of: startHour) { _, newValue in
                    manager?.saveDayBoundaries(start: newValue, end: endHour)
                }
                .onChange(of: endHour) { _, newValue in
                    manager?.saveDayBoundaries(start: startHour, end: newValue)
                }
                
                // Background Tracking
                Section {
                    NavigationLink {
                        BackgroundSettingsView()
                    } label: {
                        Label("Background Tracking", systemImage: "moon.fill")
                    }
                } header: {
                    Text("Tracking")
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
            .onAppear {
                manager = TimeTrackingManager(modelContext: modelContext)
                startHour = manager?.startOfDayHour ?? 6
                endHour = manager?.endOfDayHour ?? 23
            }
        }
    }
    
    // Helper function to format hour
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let calendar = Calendar.current
        guard let date = calendar.date(from: DateComponents(hour: hour)) else {
            return "\(hour):00"
        }
        return formatter.string(from: date)
    }
}

// MARK: - Background Settings View
struct BackgroundSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var timeTrackingManager: TimeTrackingManager?
    @State private var selectedDuration: TimeInterval = 900
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
                            // User wants to enable - check system permission first
                            checkAndRequestNotificationPermission()
                        } else {
                            // User wants to disable - just save preference
                            timeTrackingManager?.notificationsEnabled = false
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
                Text("Get notified before your activity stops in background and when activity sets change")
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
            selectedDuration = timeTrackingManager?.maxBackgroundDuration ?? 900
            
            // Load saved notification preference
            notificationsEnabled = timeTrackingManager?.notificationsEnabled ?? true
            
            // Also check system permission status
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
                timeTrackingManager?.notificationsEnabled = false
            }
        } message: {
            Text("Please enable notifications in Settings to receive activity reminders")
        }
    }
    
    private func checkAndRequestNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized:
                    // Already authorized - just save preference
                    notificationsEnabled = true
                    timeTrackingManager?.notificationsEnabled = true
                    
                case .notDetermined:
                    // Request permission
                    requestNotificationPermission()
                    
                case .denied:
                    // Show alert to open Settings
                    notificationsEnabled = false
                    timeTrackingManager?.notificationsEnabled = false
                    showingPermissionAlert = true
                    
                case .provisional, .ephemeral:
                    // Treat as authorized
                    notificationsEnabled = true
                    timeTrackingManager?.notificationsEnabled = true
                    
                @unknown default:
                    notificationsEnabled = false
                    timeTrackingManager?.notificationsEnabled = false
                }
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    notificationsEnabled = true
                    timeTrackingManager?.notificationsEnabled = true
                } else {
                    notificationsEnabled = false
                    timeTrackingManager?.notificationsEnabled = false
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                // If system permission is denied, override user preference
                if settings.authorizationStatus == .denied {
                    notificationsEnabled = false
                    timeTrackingManager?.notificationsEnabled = false
                }
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
