// ============================================================
// FILE: Cadence/Views/Sets/SetsView.swift
// FULL REPLACEMENT — now a simple hub with three destinations.
// ============================================================

import SwiftUI
import SwiftData

struct SetsView: View {
    @Query private var activitySets:      [ActivitySet]
    @Query(sort: \Activity.sortOrder) private var allActivities: [Activity]
    @Query private var schedules:         [TimeBlockRule]

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Activity Sets
                NavigationLink {
                    ActivitySetsView()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Activity Sets")
                                .font(.body)
                            Text("\(activitySets.count) set\(activitySets.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: - Schedules
                NavigationLink {
                    SchedulesView()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Schedules")
                                .font(.body)
                            Text(schedules.isEmpty
                                 ? "No schedules"
                                 : "\(schedules.count) schedule\(schedules.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: - Activity Library
                NavigationLink {
                    ActivityLibraryView()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "list.bullet.rectangle.portrait.fill")
                            .font(.title3)
                            .foregroundStyle(.purple)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Activity Library")
                                .font(.body)
                            Text("\(allActivities.count) activit\(allActivities.count == 1 ? "y" : "ies")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sets & Schedules")
        }
    }
}

#Preview {
    let config    = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Activity.self, ActivitySet.self, TimeBlock.self,
             TimeBlockRule.self, Remark.self, DayNote.self,
        configurations: config
    )
    return SetsView().modelContainer(container)
}
