import SwiftUI
import SwiftData
import UserNotifications

// MARK: - App Theme Enum

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
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

                // MARK: - Activities
                Section {
                    NavigationLink {
                        SetsView()
                    } label: {
                        Label("Activity Sets", systemImage: "square.grid.2x2")
                    }
                } header: {
                    Text("Activities")
                } footer: {
                    Text("Manage your activity sets and the activities within each set.")
                }

                // MARK: - General
                Section {
                    Picker("Appearance", selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }

                    NavigationLink {
                        InterfaceSettingsView()
                    } label: {
                        Label("Interface & Haptics", systemImage: "hand.tap.fill")
                    }
                } header: {
                    Text("General")
                }
                
                // MARK: - Journal
                Section {
                    NavigationLink {
                        JournalSettingsView()
                    } label: {
                        Label("Journal & Reflection", systemImage: "sun.horizon")
                    }
                } header: {
                    Text("Journal")
                } footer: {
                    Text("Configure daily intention and reflection reminders.")
                }

                // MARK: - Tracking Behavior
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
                        TimerDisplaySettingsView()
                    } label: {
                        Label("Timer Display", systemImage: "timer")
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

                // MARK: - Data & Storage
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

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Phase 1)")
                            .foregroundStyle(.secondary)
                    }

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Time Blocks can automatically switch your Activity Set (e.g., to 'Work') and control tracking behavior.")
                            Text("Use 'Tracking On' to enforce accountability (gaps are tracked). Use 'Paused' for sleep to ignore gaps.")
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

// MARK: - Default Tracking Mode View

struct DefaultTrackingModeView: View {
    @AppStorage("defaultTrackingMode") private var defaultTrackingModeRaw: String = TrackingMode.on.rawValue

    var body: some View {
        Form {
            Section {
                Text("Controls whether the app tracks activities and creates gaps by default.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable Tracking by Default", isOn: Binding(
                    get: { defaultTrackingModeRaw == TrackingMode.on.rawValue },
                    set: { newValue in
                        defaultTrackingModeRaw = newValue ? TrackingMode.on.rawValue : TrackingMode.off.rawValue
                    }
                ))
            } header: {
                Text("Default Mode")
            } footer: {
                Text("When enabled, the app will track activities and create gaps for untracked time. When disabled, the tracker is paused.")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("How Tracking Works", systemImage: "info.circle")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Image(systemName: "clock.badge.checkmark")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tracking On").fontWeight(.medium)
                                Text("• Records all activities\n• Creates gaps when you stop\n• Auto-switches activity sets")
                                    .font(.caption)
                            }
                        }

                        HStack(alignment: .top) {
                            Image(systemName: "clock.badge.xmark")
                                .foregroundStyle(.gray)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tracking Off").fontWeight(.medium)
                                Text("• Tracker is paused\n• No activities recorded\n• Use for sleep or downtime")
                                    .font(.caption)
                            }
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("About Tracking Modes")
            }
        }
        .navigationTitle("Default Tracking Mode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Background Tracking View

struct BackgroundTrackingView: View {
    @AppStorage("maxBackgroundDuration") private var maxBackgroundDuration: Double = 900

    let durationOptions: [(label: String, value: TimeInterval)] = [
        ("10 minutes",  600),
        ("15 minutes",  900),
        ("30 minutes", 1800),
        ("45 minutes", 2700),
        ("1 hour",     3600),
        ("2 hours",    7200),
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
                Picker("Duration", selection: $maxBackgroundDuration) {
                    ForEach(durationOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Auto-Stop Duration")
            } footer: {
                if maxBackgroundDuration == .infinity {
                    Text("Activity will continue tracking indefinitely while in background")
                } else {
                    Text("Activity will stop after \(maxBackgroundDuration.formattedDuration) in background")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("How Background Tracking Works", systemImage: "info.circle")
                        .font(.headline)

                    Text("• When you background the app, we record the timestamp")
                    Text("• When you return, we calculate elapsed time and add it to your activity")
                    Text("• This doesn't drain battery — no actual background processing happens")
                    Text("• To switch activities, you must open the app")

                    if maxBackgroundDuration != .infinity {
                        Text("\n• If you're away longer than \(maxBackgroundDuration.formattedDuration), the activity stops at that time")
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
    }
}

// MARK: - Timer Display Settings View (NEW)

struct TimerDisplaySettingsView: View {
    @AppStorage("keepScreenOnWhileTracking") private var keepScreenOn = false

    var body: some View {
        Form {
            Section {
                Toggle("Keep Screen On While Tracking", isOn: $keepScreenOn)
            } header: {
                Text("Display")
            } footer: {
                Text("Prevents the screen from auto-locking while an activity is being tracked. The screen will dim normally but won't turn off. This ensures the timer stays visible and in-app sounds play reliably. Uses more battery.")
            }

            if keepScreenOn {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "battery.50")
                            .foregroundStyle(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Battery Impact")
                                .font(.subheadline).fontWeight(.medium)
                            Text("Keeping the screen on will use more battery. Consider plugging in during long sessions.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Why Keep Screen On?", systemImage: "info.circle")
                        .font(.headline)

                    Text("• Timer completion sounds play reliably")
                    Text("• Countdown stays visible at a glance")
                    Text("• No need to unlock to check progress")
                    Text("• Screen turns off automatically when you stop tracking")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Timer Display")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notification Settings View (UPDATED)

struct NotificationSettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("inactivityReminderEnabled") private var inactivityEnabled = false
    @AppStorage("inactivityReminderInterval") private var inactivityInterval: Double = 1800

    @State private var showingPermissionAlert = false

    let inactivityOptions: [(label: String, value: TimeInterval)] = [
        ("15 minutes",  900),
        ("30 minutes", 1800),
        ("1 hour",     3600),
        ("2 hours",    7200),
        ("4 hours",   14400),
    ]

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
                        if newValue { checkAndRequestNotificationPermission() }
                    }
            } header: {
                Text("Notifications")
            }

            if notificationsEnabled {
                Section {
                    HStack {
                        Image(systemName: "bell.badge").foregroundStyle(.orange)
                        Text("You'll receive reminders before activities stop in background")
                            .font(.caption)
                    }

                    HStack {
                        Image(systemName: "arrow.triangle.swap").foregroundStyle(.blue)
                        Text("You'll be notified when activity sets change automatically")
                            .font(.caption)
                    }

                    HStack {
                        Image(systemName: "timer").foregroundStyle(.red)
                        Text("Timer completion alerts play even when the app is backgrounded")
                            .font(.caption)
                    }
                } header: {
                    Text("Active Notifications")
                }

                // MARK: Inactivity Reminder (NEW)
                Section {
                    Toggle("Inactivity Reminder", isOn: $inactivityEnabled)

                    if inactivityEnabled {
                        Picker("Remind after", selection: $inactivityInterval) {
                            ForEach(inactivityOptions, id: \.value) { option in
                                Text(option.label).tag(option.value)
                            }
                        }
                    }
                } header: {
                    Text("Inactivity Reminder")
                } footer: {
                    if inactivityEnabled {
                        Text("You'll be reminded if you haven't started a new activity within \(inactivityInterval.formattedDuration) of stopping the last one.")
                    } else {
                        Text("Get a nudge when you forget to log activities for a while.")
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { checkNotificationPermission() }
        .alert("Notifications Disabled", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { notificationsEnabled = false }
        } message: {
            Text("Please enable notifications in Settings to receive activity reminders")
        }
    }

    private func checkAndRequestNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    notificationsEnabled = true
                case .notDetermined:
                    requestNotificationPermission()
                case .denied:
                    notificationsEnabled = false
                    showingPermissionAlert = true
                @unknown default:
                    notificationsEnabled = false
                }
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                notificationsEnabled = granted
                if !granted { showingPermissionAlert = true }
            }
        }
    }

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                if settings.authorizationStatus == .denied { notificationsEnabled = false }
            }
        }
    }
}

// MARK: - Interface Settings View

struct InterfaceSettingsView: View {
    @AppStorage("hapticsEnabled")  private var hapticsEnabled  = true
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
                        Text("Intensity").font(.subheadline)

                        Slider(value: $hapticIntensity, in: 0.5...1.5, step: 0.25) {
                            Text("Intensity")
                        } minimumValueLabel: {
                            Text("Soft").font(.caption)
                        } maximumValueLabel: {
                            Text("Strong").font(.caption)
                        }
                        .onChange(of: hapticIntensity) { _, _ in
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

    private let impactLight     = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium    = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy     = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionGen    = UISelectionFeedbackGenerator()
    private let notificationGen = UINotificationFeedbackGenerator()

    private init() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        selectionGen.prepare()
        notificationGen.prepare()
    }

    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium, intensity: CGFloat = 1.0) {
        guard UserDefaults.standard.bool(forKey: "hapticsEnabled") else { return }
        switch style {
        case .light:  impactLight.impactOccurred(intensity: intensity)
        case .medium: impactMedium.impactOccurred(intensity: intensity)
        case .heavy:  impactHeavy.impactOccurred(intensity: intensity)
        case .soft:   impactLight.impactOccurred(intensity: intensity * 0.7)
        case .rigid:  impactHeavy.impactOccurred(intensity: intensity * 1.2)
        @unknown default: impactMedium.impactOccurred(intensity: intensity)
        }
    }

    func selection() {
        guard UserDefaults.standard.bool(forKey: "hapticsEnabled") else { return }
        selectionGen.selectionChanged()
    }

    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        guard UserDefaults.standard.bool(forKey: "hapticsEnabled") else { return }
        notificationGen.notificationOccurred(type)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Activity.self, ActivitySet.self, TimeBlock.self, TimeBlockRule.self,
             Remark.self, DayNote.self,
        configurations: config
    )
    return SettingsView().modelContainer(container)
}
