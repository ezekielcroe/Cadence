//
//  JournalSettingsView.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 14/2/26.
//


// ============================================================
// FILE: Cadence/Views/Settings/JournalSettingsView.swift  (NEW FILE)
// ============================================================

import SwiftUI
import UserNotifications

// MARK: - JournalSettingsView

struct JournalSettingsView: View {

    // Notification toggles
    @AppStorage("morningNotificationEnabled") private var morningEnabled  = false
    @AppStorage("eveningNotificationEnabled") private var eveningEnabled  = false

    // Times stored as hour/minute integers to survive @AppStorage serialisation
    @AppStorage("morningNotificationHour")    private var morningHour:   Int = 8
    @AppStorage("morningNotificationMinute")  private var morningMinute: Int = 0
    @AppStorage("eveningNotificationHour")    private var eveningHour:   Int = 21
    @AppStorage("eveningNotificationMinute")  private var eveningMinute: Int = 0

    // MARK: - Time bindings
    //
    // DatePicker needs a Date, but we persist hour/minute integers to avoid
    // the reference-day drift that comes with storing a full Date in AppStorage.

    private var morningTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    from: DateComponents(hour: morningHour, minute: morningMinute)
                ) ?? Date()
            },
            set: { newDate in
                let comps  = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                morningHour   = comps.hour   ?? 8
                morningMinute = comps.minute ?? 0
                JournalNotificationManager.shared.rescheduleMorning()
            }
        )
    }

    private var eveningTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    from: DateComponents(hour: eveningHour, minute: eveningMinute)
                ) ?? Date()
            },
            set: { newDate in
                let comps  = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                eveningHour   = comps.hour   ?? 21
                eveningMinute = comps.minute ?? 0
                JournalNotificationManager.shared.rescheduleEvening()
            }
        )
    }

    // MARK: - Body

    var body: some View {
        Form {

            // Description
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Intentions and reflections open and close each day on Today and in the Journal.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Enable notifications to get a gentle daily prompt for each.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            // MARK: Morning
            Section {
                Toggle("Morning Reminder", isOn: $morningEnabled)
                    .onChange(of: morningEnabled) { _, _ in
                        if morningEnabled { checkNotificationPermission { morningEnabled = $0 } }
                        JournalNotificationManager.shared.rescheduleMorning()
                    }

                if morningEnabled {
                    DatePicker(
                        "Reminder Time",
                        selection: morningTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Label("Morning Intention", systemImage: "sun.horizon.fill")
            } footer: {
                Text("A daily reminder to write what you want to accomplish today.")
            }

            // MARK: Evening
            Section {
                Toggle("Evening Reminder", isOn: $eveningEnabled)
                    .onChange(of: eveningEnabled) { _, _ in
                        if eveningEnabled { checkNotificationPermission { eveningEnabled = $0 } }
                        JournalNotificationManager.shared.rescheduleEvening()
                    }

                if eveningEnabled {
                    DatePicker(
                        "Reminder Time",
                        selection: eveningTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            } header: {
                Label("Evening Reflection", systemImage: "moon.stars.fill")
            } footer: {
                Text("A daily reminder to reflect on how the day went.")
            }
        }
        .navigationTitle("Journal & Reflection")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Permission helper
    //
    // Checks notification auth status before enabling; opens Settings if denied.

    @State private var showingPermissionAlert = false

    private func checkNotificationPermission(onDenied: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    break   // already granted, nothing to do
                case .notDetermined:
                    UNUserNotificationCenter.current().requestAuthorization(
                        options: [.alert, .sound]
                    ) { granted, _ in
                        DispatchQueue.main.async {
                            if !granted { onDenied(false) }
                        }
                    }
                case .denied:
                    onDenied(false)
                    // Ideally show an alert here; for simplicity the toggle reverts
                @unknown default:
                    onDenied(false)
                }
            }
        }
    }
}
