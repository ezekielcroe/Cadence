//
//  TrackingWindow.swift
//  Cadence
//
//  Created by Yeo Zhi Zheng on 7/7/26.
//


//
//  TrackingWindow.swift
//  Cadence
//
//  Defines the hours of the day the user wants to be accountable for.
//  Gaps are only computed inside the window. Blocks outside the window
//  still exist and still render — they are never clipped or hidden —
//  but time outside the window is never flagged as unaccounted.
//
//  Disabled window = full-day auditing (24h accountability).
//  Enabled window  = e.g. 09:00–18:00 Mon–Fri for work-hours tracking.
//
//  Stored in UserDefaults: a single global setting, no SwiftData migration.
//

import Foundation

struct TrackingWindow: Equatable {

    var isEnabled: Bool
    /// Minutes from midnight, 0..<1440.
    var startMinutes: Int
    var endMinutes: Int
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday). Empty = every day.
    var weekdays: Set<Int>

    /// True when the window wraps past midnight (e.g. 22:00 → 06:00).
    var isOvernight: Bool { endMinutes < startMinutes }

    // MARK: - Persistence

    private enum Keys {
        static let enabled  = "trackingWindow.enabled"
        static let start    = "trackingWindow.startMinutes"
        static let end      = "trackingWindow.endMinutes"
        static let weekdays = "trackingWindow.weekdays"
    }

    static var current: TrackingWindow { load(from: .standard) }

    static func load(from d: UserDefaults) -> TrackingWindow {
        TrackingWindow(
            isEnabled:    d.bool(forKey: Keys.enabled),
            startMinutes: d.object(forKey: Keys.start) as? Int ?? 9 * 60,
            endMinutes:   d.object(forKey: Keys.end)   as? Int ?? 18 * 60,
            weekdays:     Set((d.array(forKey: Keys.weekdays) as? [Int]) ?? [])
        )
    }

    func save(to d: UserDefaults = .standard) {
        d.set(isEnabled,          forKey: Keys.enabled)
        d.set(startMinutes,       forKey: Keys.start)
        d.set(endMinutes,         forKey: Keys.end)
        d.set(Array(weekdays),    forKey: Keys.weekdays)
    }

    // MARK: - Weekday applicability

    private func applies(toWeekday weekday: Int) -> Bool {
        weekdays.isEmpty || weekdays.contains(weekday)
    }

    // MARK: - Segments

    /// The accountable intervals that fall on the given calendar day.
    ///
    /// Non-overnight window: one segment [start, end] if the day's weekday
    /// applies, else none.
    ///
    /// Overnight window (end < start): up to two segments —
    ///   [00:00, end]   if the *previous* day's weekday applies
    ///                  (that segment belongs to a window that started yesterday),
    ///   [start, 24:00] if *this* day's weekday applies.
    ///
    /// Disabled window: the whole day.
    func segments(on day: Date, calendar: Calendar = .current) -> [DateInterval] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        guard isEnabled else { return [DateInterval(start: dayStart, end: dayEnd)] }

        let weekday = calendar.component(.weekday, from: dayStart)

        func time(_ minutes: Int, of base: Date) -> Date {
            calendar.date(byAdding: .minute, value: minutes, to: base)!
        }

        if !isOvernight {
            guard applies(toWeekday: weekday) else { return [] }
            let s = time(startMinutes, of: dayStart)
            let e = time(endMinutes,   of: dayStart)
            return s < e ? [DateInterval(start: s, end: e)] : []
        }

        var result: [DateInterval] = []

        // Tail of a window that started the previous day.
        let prevDayStart = calendar.date(byAdding: .day, value: -1, to: dayStart)!
        let prevWeekday  = calendar.component(.weekday, from: prevDayStart)
        if applies(toWeekday: prevWeekday) {
            let e = time(endMinutes, of: dayStart)
            if dayStart < e { result.append(DateInterval(start: dayStart, end: e)) }
        }

        // Head of the window that starts today.
        if applies(toWeekday: weekday) {
            let s = time(startMinutes, of: dayStart)
            if s < dayEnd { result.append(DateInterval(start: s, end: dayEnd)) }
        }

        return result
    }

    /// The earliest accountable moment on the given day, or nil when the
    /// window is disabled (full-day mode has no floor — retrospective
    /// labeling may reach into the previous day, e.g. overnight sleep).
    /// Used to clamp the retrospective anchor for work-hours users.
    func anchorFloor(on day: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        return segments(on: day, calendar: calendar).map(\.start).min()
    }

    // MARK: - Display

    var displayString: String {
        guard isEnabled else { return "All day" }
        func fmt(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
        let days: String
        if weekdays.isEmpty {
            days = "every day"
        } else {
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            days = weekdays.sorted().map { names[$0 - 1] }.joined(separator: ", ")
        }
        return "\(fmt(startMinutes))–\(fmt(endMinutes)), \(days)"
    }
}
