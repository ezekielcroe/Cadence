//
//  AccountabilityTests.swift
//  CadenceTests
//
//  Step 7: who starts with accountability on.
//

import Testing
import Foundation
@testable import Cadence

struct AccountabilityTests {

    let defaults = UserDefaults(suiteName: "CadenceTests.\(UUID().uuidString)")!

    @Test func newInstallsStartInDiaryMode() {
        Accountability.migrateDefaultIfNeeded(in: defaults)
        #expect(!Accountability.isEnabled(in: defaults))
    }

    @Test func installsWithAccountableHoursKeepAccountability() {
        TrackingWindow(isEnabled: true, startMinutes: 9 * 60, endMinutes: 18 * 60, weekdays: [])
            .save(to: defaults)
        Accountability.migrateDefaultIfNeeded(in: defaults)
        #expect(Accountability.isEnabled(in: defaults))
    }

    @Test func aChoiceAlreadyMadeIsNeverChanged() {
        defaults.set(false, forKey: Accountability.key)
        TrackingWindow(isEnabled: true, startMinutes: 9 * 60, endMinutes: 18 * 60, weekdays: [])
            .save(to: defaults)
        Accountability.migrateDefaultIfNeeded(in: defaults)
        #expect(!Accountability.isEnabled(in: defaults))
    }
}
