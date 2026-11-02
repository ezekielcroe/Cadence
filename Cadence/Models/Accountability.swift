//
//  Accountability.swift
//  Cadence
//
//  One switch between two ways of looking at your time:
//
//    Off (diary, the default for new installs): blank time is quiet blank
//    space. No gap counts, no "unaccounted" totals, no red/green
//    judgement of activities.
//
//    On (accountability): blank time inside your Accountable Hours is
//    called out as unlogged, headers count it, and Insights shows
//    unaccounted time, fragmentation and goal colours.
//
//  The Ledger view always shows blank time with Fill, whichever is set,
//  because that's where you go to fix it.
//

import Foundation

enum Accountability {

    static let key = "accountability.enabled"

    /// Run once at launch. Installs that had already set up Accountable
    /// Hours keep accountability on; everyone else starts in diary mode.
    static func migrateDefaultIfNeeded(in defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: key) == nil else { return }
        defaults.set(TrackingWindow.load(from: defaults).isEnabled, forKey: key)
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }
}
