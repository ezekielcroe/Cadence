//
//  NotificationDelegate.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 1/3/26.
//


import Foundation
import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// Called when a notification arrives while the app is in the foreground.
    /// We allow banner + sound so the timer alarm is audible/visible even
    /// when the user is looking at the app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner + play sound for all notifications while foregrounded
        completionHandler([.banner, .sound])
    }

    /// Called when the user taps a notification. Default handling — brings app to foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
