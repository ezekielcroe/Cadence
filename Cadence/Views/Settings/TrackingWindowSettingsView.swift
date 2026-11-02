//
//  TrackingWindowSettingsView.swift
//  Cadence
//
//  Created by Yeo Zhi Zheng on 7/7/26.
//


//
//  TrackingWindowSettingsView.swift
//  Cadence
//
//  Configures the accountable-hours window. Add a NavigationLink to this
//  from SettingsView (see INTEGRATION.md).
//

import SwiftUI

struct TrackingWindowSettingsView: View {
    @State private var window = TrackingWindow.current

    private static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var startDate: Binding<Date> {
        minutesBinding(\.startMinutes)
    }
    private var endDate: Binding<Date> {
        minutesBinding(\.endMinutes)
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<TrackingWindow, Int>) -> Binding<Date> {
        Binding(
            get: {
                let base = Calendar.current.startOfDay(for: Date())
                return Calendar.current.date(byAdding: .minute,
                                             value: window[keyPath: keyPath],
                                             to: base)!
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                window[keyPath: keyPath] = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Limit accountable hours", isOn: $window.isEnabled)
            } footer: {
                Text("Off: every hour of the day counts, so blank time anywhere can be marked as unlogged. On: only the hours below are checked, and the counter on Today never starts before them. Anything you log outside these hours is kept and shown; it is just never asked for. Unlogged time is only marked when Call Out Unlogged Time is on in Settings.")
            }

            if window.isEnabled {
                Section("Hours") {
                    DatePicker("From", selection: startDate, displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: endDate, displayedComponents: .hourAndMinute)
                    if window.isOvernight {
                        Label("Window crosses midnight", systemImage: "moon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { day in
                            let selected = window.weekdays.contains(day)
                            Button {
                                if selected { window.weekdays.remove(day) }
                                else        { window.weekdays.insert(day) }
                            } label: {
                                Text(Self.dayNames[day - 1])
                                    .font(.caption).fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(selected ? Color.accentColor : Color(.systemGray5))
                                    .foregroundStyle(selected ? .white : .primary)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Days")
                } footer: {
                    Text("No days selected means every day.")
                }
            }
        }
        .navigationTitle("Accountable Hours")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: window) { _, newValue in newValue.save() }
    }
}
