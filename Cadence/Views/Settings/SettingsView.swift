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

    /// Retrospective spans at or above this length open the confirm sheet.
    @AppStorage("retroConfirmThreshold") private var retroConfirmThreshold: Double = 4 * 3600
    @AppStorage(Accountability.key) private var accountable = false

    private let thresholdOptions: [(label: String, value: Double)] = [
        ("2 hours",   2 * 3600),
        ("4 hours",   4 * 3600),
        ("8 hours",   8 * 3600),
        ("12 hours", 12 * 3600),
    ]

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

                // MARK: - Accountability
                Section {
                    Toggle(isOn: $accountable) {
                        Label("Call Out Unlogged Time", systemImage: "exclamationmark.circle")
                    }

                    NavigationLink {
                        TrackingWindowSettingsView()
                    } label: {
                        Label("Accountable Hours", systemImage: "clock.badge.checkmark")
                    }
                } header: {
                    Text("Accountability")
                } footer: {
                    if accountable {
                        Text("Unlogged time within your accountable hours (\(TrackingWindow.current.displayString)) is marked on Today and in the Journal and counted in each day's header. Insights adds unaccounted time, a focus score and good/bad colours for your goals.")
                    } else {
                        Text("Blank time stays quiet: no counts, no unaccounted totals, no red or green. The Journal's Ledger view always shows blank time so you can fill it in. Turn this on for work-style accountability.")
                    }
                }

                // MARK: - Logging
                Section {
                    Picker("Confirm long spans over", selection: $retroConfirmThreshold) {
                        ForEach(thresholdOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                } header: {
                    Text("Logging")
                } footer: {
                    Text("Logging a stretch longer than this asks you to check where it starts first, so a forgotten morning doesn't become one huge entry.")
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
                    Text("Set morning intention and evening reflection reminders. Intentions and reflections open and close each day on Today and in the Journal.")
                }

                // MARK: - Tracking Behavior
                Section {
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
                    Text("Timer alerts and notification preferences, including inactivity reminders. Timers keep running while the app is in the background or closed — nothing is auto-stopped.")
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
                    Text("Export your entries and notes as CSV, create backups, or archive old records. Timesheet PDFs are exported from Insights.")
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
                                icon: "hand.tap",
                                tint: .blue,
                                title: "Tap to Log, Hold to Time",
                                body: "Tap an activity to label the time since your last entry — nothing to arm, nothing to forget. Hold an activity to start a live timer instead; while it runs, tapping another activity switches it, and Stop goes back to logging."
                            )

                            tipRow(
                                icon: "tag.fill",
                                tint: .green,
                                title: "Labeling Long Spans",
                                body: "Stretches longer than your confirm threshold open a sheet where you can adjust the start time. Anything before the start stays blank in your journal, and you can fill it in later."
                            )

                            tipRow(
                                icon: "timer",
                                tint: .orange,
                                title: "Session Timer",
                                body: "Hold an activity and choose Start with goal, or tap the bell on a running timer. You'll get an alert (with sound and haptics) when time's up, even if the app is backgrounded."
                            )

                            tipRow(
                                icon: "note.text",
                                tint: .blue,
                                title: "Notes & Tags",
                                body: "Every note belongs to an entry. Write one from the card that appears after each tap, from a running timer, or by tapping an entry. Use #hashtags to group notes, then filter or search them in the Journal."
                            )

                            tipRow(
                                icon: "sun.horizon.fill",
                                tint: .orange,
                                title: "Intentions & Reflections",
                                body: "Set a daily intention each morning and write a reflection each evening. The intention opens the day and the reflection closes it, on Today and in the Journal. The reflection editor shows a one-line summary of your day."
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
                                title: "Fixing Your Record",
                                body: "Tap any entry for its page: notes, times, split or delete. In the Journal, switch to Ledger to fill blank time, swipe to edit or delete, or tap Select to merge entries that follow each other."
                            )

                            tipRow(
                                icon: "clock.badge.checkmark",
                                tint: .indigo,
                                title: "Accountable Hours",
                                body: "With Call Out Unlogged Time on, only the hours you set here (say, 09:00–18:00 on weekdays) are checked for blank time. Anything you log outside them is still kept and shown."
                            )

                            tipRow(
                                icon: "doc.text.fill",
                                tint: .gray,
                                title: "Timesheet Export",
                                body: "Generate a supervisor-ready PDF for any period from Insights (the share button): chronological rows, day subtotals, breaks, notes, and unaccounted time as its own labeled line."
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
                Text("Cadence can notify you about timer completions, scheduled set changes, and inactivity.")
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
                        text: "Session timer completion — plays an alert sound and vibrates when your target duration is reached, including when it completes while the app is closed."
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
                        .onChange(of: inactivityEnabled) { _, isOn in
                            guard isOn else { return }
                            NotificationPermission.requestIfNeeded { granted in
                                if !granted {
                                    inactivityEnabled = false
                                    showingPermissionAlert = true
                                }
                            }
                        }

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
    SettingsView().modelContainer(try! CadenceSchema.makeContainer(inMemory: true))
}
