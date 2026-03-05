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
                    Text("Create activity sets (e.g. Work, Personal) and assign activities to each. Activities can belong to multiple sets and carry a goal direction (Keep High, Keep Low, Neutral).")
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
                    Text("Set morning intention and evening reflection reminders. Intentions and reflections appear in your daily timeline alongside activity records.")
                }

                // MARK: - Tracking Behavior
                Section {

                    NavigationLink {
                        BackgroundTrackingView()
                    } label: {
                        Label("Background Tracking", systemImage: "moon.fill")
                    }

                    NavigationLink {
                        TimerDisplaySettingsView()
                    } label: {
                        Label("Timer & Display", systemImage: "timer")
                    }

                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.fill")
                    }
                } header: {
                    Text("Tracking Behavior")
                } footer: {
                    Text("Controls how Cadence tracks time in the background, when to auto-stop, timer alerts, and notification preferences including inactivity reminders.")
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
                    Text("Export your activity history and remarks as CSV, create backups, or archive old records.")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.5.0")
                            .foregroundStyle(.secondary)
                    }

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 16) {
                            
                            tipRow(
                                icon: "switch.2",
                                tint: .blue,
                                title: "Start & Log Modes",
                                body: "Choose your tracking style from the Tracking tab. 'Start' mode begins a timer for what you are doing right now. 'Log' mode lets you catch up by retrospectively labeling the time since your last entry."
                            )
                            
                            tipRow(
                                icon: "play.circle.fill",
                                tint: .green,
                                title: "Quick Switching",
                                body: "Tap any activity to start the clock or log a duration. Tap a different activity to switch seamlessly — the previous one is capped and saved automatically."
                            )

                            tipRow(
                                icon: "timer",
                                tint: .orange,
                                title: "Session Timer",
                                body: "Set a target duration for any session using the bell icon. You'll get an alert (with sound and haptics) when time's up, even if the app is backgrounded."
                            )

                            tipRow(
                                icon: "note.text",
                                tint: .blue,
                                title: "Remarks & Tags",
                                body: "Add timestamped notes to your running activities, or attach them to previous ones in Log mode. Use #hashtags to categorize, then filter across all remarks in the Records tab."
                            )

                            tipRow(
                                icon: "sun.horizon.fill",
                                tint: .orange,
                                title: "Intentions & Reflections",
                                body: "Set a daily intention each morning and write a reflection each evening. These bookend your day in the Records timeline and help you stay mindful."
                            )

                            tipRow(
                                icon: "square.grid.2x2.fill",
                                tint: .purple,
                                title: "Activity Sets & Schedules",
                                body: "Organize activities into palettes (Work, Personal, etc.). Create schedules to auto-switch the active set on a timetable so Cadence shows you the right activities at the right time."
                            )

                            tipRow(
                                icon: "hand.tap.fill",
                                tint: .teal,
                                title: "Manage Records",
                                body: "In the Records timeline, long-press any block to edit its time, change the activity, or split it in two. Double-tap a block to quickly add an inline note."
                            )

                            tipRow(
                                icon: "moon.fill",
                                tint: .indigo,
                                title: "Background Tracking",
                                body: "When you leave the app, your current activity keeps tracking. If you're away too long, Cadence auto-stops at your configured limit. State is saved so nothing is lost, even if iOS terminates the app."
                            )

                            tipRow(
                                icon: "bell.badge.fill",
                                tint: .red,
                                title: "Inactivity Reminder",
                                body: "Enable a nudge if you forget to log. Cadence will notify you after a configurable period of no activity, so you can pick up where you left off."
                            )
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Label("Feature Guide", systemImage: "lightbulb.fill")
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Tip Row Helper

    private func tipRow(icon: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.body)
                .frame(width: 24, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
                Text("When you leave the app, your current activity keeps running. If you don't return within the limit below, Cadence will auto-stop the activity at that point.")
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
                Text("Auto-Stop After")
            } footer: {
                if maxBackgroundDuration == .infinity {
                    Text("Activity will track indefinitely — it won't auto-stop no matter how long you're away.")
                } else {
                    Text("If you're away longer than \(maxBackgroundDuration.formattedDuration), the activity stops at that mark and the remaining time appears as a gap.")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("How It Works", systemImage: "info.circle")
                        .font(.headline)

                    Text("Cadence records a timestamp when you leave and calculates elapsed time when you return. No background processing runs — this uses zero battery.")
                    Text("If iOS terminates the app while it's in the background (which is normal), Cadence recovers the session on next launch using the saved timestamp.")
                    Text("A reminder notification is sent 5 minutes before the auto-stop limit to give you a chance to return.")

                    if maxBackgroundDuration != .infinity {
                        Text("Activity auto-stops after \(maxBackgroundDuration.formattedDuration) if you don't come back.")
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

// MARK: - Timer & Display Settings View

struct TimerDisplaySettingsView: View {
    @AppStorage("keepScreenOnWhileTracking") private var keepScreenOn = false

    var body: some View {
        Form {
            Section {
                Toggle("Keep Screen On While Tracking", isOn: $keepScreenOn)
            } header: {
                Text("Display")
            } footer: {
                Text("Prevents auto-lock while an activity is being tracked. Automatically re-enables when you stop tracking.")
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
                            Text("Keeping the screen on uses more battery. Consider plugging in during long sessions.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("When To Use This", systemImage: "info.circle")
                        .font(.headline)

                    Text("Enable this when you want to glance at the countdown without unlocking your phone, or to ensure the timer-completion sound plays reliably (it fires through the speaker when the app is in the foreground).")
                    Text("If you're using a session timer (set via the bell icon on the tracking screen), keeping the screen on guarantees you'll hear the completion alert even with the phone sitting nearby.")
                    Text("The screen turns off automatically when you stop tracking or when no activity is active.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Timer & Display")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notification Settings View

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
                Text("Cadence can notify you about timer completions, background activity changes, and more.")
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
                    notificationRow(
                        icon: "timer",
                        tint: .red,
                        text: "Session timer completion — plays an alert sound and vibrates when your target duration is reached."
                    )
                    notificationRow(
                        icon: "bell.badge",
                        tint: .orange,
                        text: "Background warning — notifies you 5 minutes before Cadence auto-stops your activity."
                    )
                    notificationRow(
                        icon: "stop.circle",
                        tint: .secondary,
                        text: "Activity stopped — confirms when an activity is auto-stopped due to background timeout or pause timeout."
                    )
                    notificationRow(
                        icon: "arrow.triangle.swap",
                        tint: .blue,
                        text: "Set auto-switch — tells you when a scheduled rule changes your active activity set."
                    )
                } header: {
                    Text("What You'll Receive")
                }

                // MARK: Inactivity Reminder
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
                        Text("If you stop tracking and don't start a new activity within \(inactivityInterval.formattedDuration), you'll get a nudge to log what you're doing.")
                    } else {
                        Text("Get a reminder when you haven't logged any activity for a while. Helpful if you tend to forget to track.")
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
            Text("Please enable notifications in Settings to receive activity reminders and timer alerts.")
        }
    }

    // MARK: - Notification Row Helper

    private func notificationRow(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.caption)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)
            Text(text)
                .font(.caption)
        }
    }

    // MARK: - Permission Handling

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
                Text("Customize how the app feels when you interact with it.")
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
                Text("Haptics fire when you tap activity buttons, start/stop tracking, and when a timer completes.")
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
