import SwiftUI
import SwiftData
import UserNotifications

// MARK: - App Theme Enum
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Main Settings View
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - General
                Section {
                    // Appearance Picker
                    Picker("Appearance", selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    
                    // Interface (Haptics)
                    NavigationLink {
                        InterfaceSettingsView()
                    } label: {
                        Label("Interface & Haptics", systemImage: "hand.tap.fill")
                    }
                } header: {
                    Text("General")
                }
                
                // MARK: - Tracking Logic
                Section {
                    NavigationLink {
                        DefaultTrackingModeView()
                    } label: {
                        Label("Default Tracking Mode", systemImage: "clock.badge.questionmark")
                    }
                    
                    NavigationLink {
                        BackgroundTrackingView()
                    } label: {
                        Label("Background Tracking", systemImage: "moon.fill")
                    }
                    
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.fill")
                    }
                } header: {
                    Text("Tracking Behavior")
                } footer: {
                    Text("Configure how Cadence records time when you switch contexts or leave the app.")
                }
                
                // MARK: - Data Management
                Section {
                    NavigationLink {
                        DataManagementView()
                    } label: {
                        Label("Data Management", systemImage: "externaldrive.fill")
                    }
                } header: {
                    Text("Data & Storage")
                } footer: {
                    Text("Export CSVs, create backups, or archive old records.")
                }
                
                // MARK: - About & Help
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Phase 1)")
                            .foregroundStyle(.secondary)
                    }
                    
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Time Blocks control how gaps are tracked. Set up 'Work Hours' to be Strict (track gaps) and 'Evenings' to be Relaxed.")
                            Text("The 'Default Mode' applies whenever you are outside of these specific Time Blocks.")
                        }
                        .font(.caption)
                        .padding(.vertical, 4)
                    } label: {
                        Label("Quick Tips", systemImage: "lightbulb.fill")
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - SUBVIEWS

// MARK: - Default Tracking Mode View
struct DefaultTrackingModeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var timeTrackingManager: TimeTrackingManager?
    @State private var selectedMode: TrackingMode = .relaxed
    
    var body: some View {
        Form {
            Section {
                Text("This mode applies when you're not within any defined time block.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                ForEach(TrackingMode.allCases, id: \.self) { mode in
                    Button {
                        selectedMode = mode
                        timeTrackingManager?.saveDefaultTrackingMode(mode)
                    } label: {
                        HStack {
                            Image(systemName: mode.icon)
                                .font(.title3)
                                .foregroundStyle(colorForMode(mode))
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Default Mode")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("How Tracking Modes Work", systemImage: "info.circle")
                        .font(.headline)
                    
                    TrackingModeExplanation(mode: .strict)
                    TrackingModeExplanation(mode: .relaxed)
                    TrackingModeExplanation(mode: .off)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("About Tracking Modes")
            }
        }
        .navigationTitle("Default Tracking Mode")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            timeTrackingManager = TimeTrackingManager(modelContext: modelContext)
            selectedMode = timeTrackingManager?.defaultTrackingMode ?? .relaxed
        }
    }
    
    private func colorForMode(_ mode: TrackingMode) -> Color {
        switch mode {
        case .strict: return .red
        case .relaxed: return .blue
        case .off: return .gray
        }
    }
}

// MARK: - Tracking Mode Explanation
struct TrackingModeExplanation: View {
    let mode: TrackingMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: mode.icon)
                Text(mode.displayName)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.primary)
            
            switch mode {
            case .strict:
                Text("• Tracks activities and creates gaps when stopped")
                Text("• Auto-switches activity sets based on time blocks")
                Text("• Best for work hours when accountability matters")
            case .relaxed:
                Text("• Tracks activities but no gaps when stopped")
                Text("• Auto-switches activity sets based on time blocks")
                Text("• Best for personal time without pressure")
            case .off:
                Text("• Only tracks what you manually start")
                Text("• No gaps, no auto-switching")
                Text("• Best for sleep or complete downtime")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Background Tracking View
struct BackgroundTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var timeTrackingManager: TimeTrackingManager?
    @State private var selectedDuration: TimeInterval = 900
    
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
        }
    }
}

// MARK: - Notification Settings View
struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var timeTrackingManager: TimeTrackingManager?
    @State private var notificationsEnabled = false
    @State private var showingPermissionAlert = false
    
    var body: some View {
        Form {
            Section {
                Text("Get notified when activities stop in background and when activity sets change automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                Toggle("Enable Notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        if newValue {
                            checkAndRequestNotificationPermission()
                        } else {
                            timeTrackingManager?.notificationsEnabled = false
                        }
                    }
            } header: {
                Text("Notifications")
            }
            
            if notificationsEnabled {
                Section {
                    HStack {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.orange)
                        Text("You'll receive reminders before activities stop in background")
                            .font(.caption)
                    }
                    
                    HStack {
                        Image(systemName: "arrow.triangle.swap")
                            .foregroundStyle(.blue)
                        Text("You'll be notified when activity sets change automatically")
                            .font(.caption)
                    }
                } header: {
                    Text("Active Notifications")
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            timeTrackingManager = TimeTrackingManager(modelContext: modelContext)
            notificationsEnabled = timeTrackingManager?.notificationsEnabled ?? true
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
                    notificationsEnabled = true
                    timeTrackingManager?.notificationsEnabled = true
                case .notDetermined:
                    requestNotificationPermission()
                case .denied:
                    notificationsEnabled = false
                    timeTrackingManager?.notificationsEnabled = false
                    showingPermissionAlert = true
                case .provisional, .ephemeral:
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
                if settings.authorizationStatus == .denied {
                    notificationsEnabled = false
                    timeTrackingManager?.notificationsEnabled = false
                }
            }
        }
    }
}

// MARK: - Interface Settings View
struct InterfaceSettingsView: View {
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("hapticIntensity") private var hapticIntensity = 1.0
    
    var body: some View {
        Form {
            Section {
                Text("Customize how the app responds to your interactions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                
                if hapticsEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Intensity")
                            .font(.subheadline)
                        
                        Slider(value: $hapticIntensity, in: 0.5...1.5, step: 0.25) {
                            Text("Intensity")
                        } minimumValueLabel: {
                            Text("Soft")
                                .font(.caption)
                        } maximumValueLabel: {
                            Text("Strong")
                                .font(.caption)
                        }
                        .onChange(of: hapticIntensity) { _, _ in
                            // Test haptic when slider changes
                            HapticManager.shared.impact(style: .medium, intensity: hapticIntensity)
                        }
                    }
                }
            } header: {
                Text("Haptic Feedback")
            } footer: {
                Text("Feel physical feedback when tapping activity buttons and control buttons")
            }
        }
        .navigationTitle("Interface")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Haptic Manager
class HapticManager {
    static let shared = HapticManager()
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()
    
    private init() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }
    
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium, intensity: CGFloat = 1.0) {
        guard UserDefaults.standard.bool(forKey: "hapticsEnabled") else { return }
        
        switch style {
        case .light:
            impactLight.impactOccurred(intensity: intensity)
        case .medium:
            impactMedium.impactOccurred(intensity: intensity)
        case .heavy:
            impactHeavy.impactOccurred(intensity: intensity)
        case .soft:
            impactLight.impactOccurred(intensity: intensity * 0.7)
        case .rigid:
            impactHeavy.impactOccurred(intensity: intensity * 1.2)
        @unknown default:
            impactMedium.impactOccurred(intensity: intensity)
        }
    }
    
    func selection() {
        guard UserDefaults.standard.bool(forKey: "hapticsEnabled") else { return }
        selectionGenerator.selectionChanged()
    }
    
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        guard UserDefaults.standard.bool(forKey: "hapticsEnabled") else { return }
        notificationGenerator.notificationOccurred(type)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Activity.self, ActivitySet.self, TimeBlock.self, TimeBlockRule.self, configurations: config)
    
    return SettingsView()
        .modelContainer(container)
}
