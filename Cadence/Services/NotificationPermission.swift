//
//  NotificationPermission.swift
//  Cadence
//
//  Asks for notification permission at the moment it's needed (turning
//  on a reminder, starting a timer with a goal) instead of at launch.
//

import Foundation
import UserNotifications

enum NotificationPermission {

    /// Asks the system only if it has never been asked. `completion` runs
    /// on the main queue with whether notifications are allowed.
    static func requestIfNeeded(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async { completion?(granted) }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { completion?(true) }
            default:
                DispatchQueue.main.async { completion?(false) }
            }
        }
    }
}
