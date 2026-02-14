//
//  JournalNotificationManager.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 14/2/26.
//


// ============================================================
// FILE: Cadence/Managers/JournalNotifications.swift  (NEW FILE)
// ============================================================

import Foundation
import UserNotifications

// MARK: - JournalNotificationManager
//
// Manages two repeating daily notifications:
//   • Morning — prompt to write today's intention
//   • Evening — prompt to write tonight's reflection
//
// All settings are read directly from UserDefaults / @AppStorage,
// so this can be called from anywhere without needing to pass values in.
// Call rescheduleAll() on app launch and whenever a setting changes.

class JournalNotificationManager {

    static let shared = JournalNotificationManager()
    private init() {}

    // Stable identifiers so cancellation is precise
    private let morningID = "journal.morning.intention"
    private let eveningID = "journal.evening.reflection"

    // MARK: - Public API

    /// Re-schedules both notifications. Safe to call on every app launch.
    func rescheduleAll() {
        rescheduleMorning()
        rescheduleEvening()
    }

    func rescheduleMorning() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningID])

        guard UserDefaults.standard.bool(forKey: "morningNotificationEnabled") else { return }

        let hour   = validHour(UserDefaults.standard.integer(forKey: "morningNotificationHour"),   fallback: 8)
        let minute = validMinute(UserDefaults.standard.integer(forKey: "morningNotificationMinute"))

        let content       = UNMutableNotificationContent()
        content.title     = "Set Today's Intention"
        content.body      = "What do you want to accomplish today?"
        content.sound     = .default

        var components    = DateComponents()
        components.hour   = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: morningID, content: content, trigger: trigger)
        center.add(request)
    }

    func rescheduleEvening() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [eveningID])

        guard UserDefaults.standard.bool(forKey: "eveningNotificationEnabled") else { return }

        let hour   = validHour(UserDefaults.standard.integer(forKey: "eveningNotificationHour"),   fallback: 21)
        let minute = validMinute(UserDefaults.standard.integer(forKey: "eveningNotificationMinute"))

        let content       = UNMutableNotificationContent()
        content.title     = "Evening Reflection"
        content.body      = "How did today go? Take a moment to reflect."
        content.sound     = .default

        var components    = DateComponents()
        components.hour   = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: eveningID, content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Helpers

    private func validHour(_ value: Int, fallback: Int) -> Int {
        // @AppStorage(Int) returns 0 when unset — treat 0 as "use fallback"
        (value > 0 && value < 24) ? value : fallback
    }

    private func validMinute(_ value: Int) -> Int {
        (value >= 0 && value < 60) ? value : 0
    }
}