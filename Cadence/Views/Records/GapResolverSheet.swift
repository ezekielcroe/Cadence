// GapResolverSheet.swift
// Cadence

import SwiftUI
import SwiftData

// MARK: - GapResolverSheet

struct GapResolverSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Computed gaps are value types — no binding needed.
    let gap: ComputedGap
    let onResolved: () -> Void

    @Query private var activities: [Activity]
    @Query private var activitySets: [ActivitySet]

    @State private var adjustedStart: Date
    @State private var adjustedEnd: Date
    @State private var recentActivities: [Activity] = []

    init(gap: ComputedGap, onResolved: @escaping () -> Void) {
        self.gap = gap
        self.onResolved = onResolved
        _adjustedStart = State(initialValue: gap.start)
        _adjustedEnd   = State(initialValue: gap.end)
    }

    // MARK: - Helpers

    private var activeSet: ActivitySet? {
        activitySets.first { $0.isActive }
    }

    private var setActivities: [Activity] {
        guard let setID = activeSet?.id else { return activities }
        return activities
            .filter { activity in
                activity.sets.contains(where: { $0.id == setID })
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var adjustedDuration: TimeInterval {
        adjustedEnd.timeIntervalSince(adjustedStart)
    }

    private var originalDurationLabel: String {
        gap.duration.formattedDuration
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    gapInfoCard
                    quickAssignSection
                    timeAdjustmentSection
                    helpSection
                }
                .padding()
            }
            .navigationTitle("Resolve Gap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { loadRecentActivities() }
    }

    // MARK: - Subviews

    private var gapInfoCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading) {
                    Text("Untracked Time")
                        .font(.headline)
                    Text(
                        "\(gap.start.formatted(date: .omitted, time: .shortened)) → " +
                        "\(gap.end.formatted(date: .omitted, time: .shortened))"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(originalDurationLabel)
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }

            Text("What were you doing during this time?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private var quickAssignSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Assign")
                .font(.headline)

            if !recentActivities.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(recentActivities.prefix(4)) { activity in
                            ActivityQuickButton(activity: activity) {
                                resolveGap(with: activity)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(activeSet?.name ?? "Activities")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(setActivities.prefix(12)) { activity in
                        ActivityQuickButton(activity: activity) {
                            resolveGap(with: activity)
                        }
                    }
                }

                if setActivities.count > 12 {
                    Text("\(setActivities.count - 12) more activities available in full editor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var timeAdjustmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup {
                VStack(spacing: 12) {
                    HStack {
                        Text("Start")
                        Spacer()
                        DatePicker("", selection: $adjustedStart, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    HStack {
                        Text("End")
                        Spacer()
                        DatePicker("", selection: $adjustedEnd, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    if adjustedStart != gap.start || adjustedEnd != gap.end {
                        Text("Block will cover \(adjustedDuration.formattedDuration)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Adjust Time Range", systemImage: "clock")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How gaps work", systemImage: "questionmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Gaps are untracked time between two activity blocks. Assigning an activity creates a new block for that period. If the gap shouldn't exist, you can merge the surrounding blocks from the Records view.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Actions

    private func loadRecentActivities() {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime >= weekAgo && block.activityID != nil
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        guard let recentBlocks = try? modelContext.fetch(descriptor) else { return }

        var seen = Set<UUID>()
        var ids: [UUID] = []
        for block in recentBlocks {
            if let id = block.activityID, !seen.contains(id) {
                seen.insert(id)
                ids.append(id)
            }
        }

        recentActivities = ids.compactMap { id in
            activities.first { $0.id == id }
        }
    }

    /// Creates a new TimeBlock for the gap period and saves it.
    private func resolveGap(with activity: Activity) {
        let newBlock = TimeBlock(
            activityID: activity.id,
            activityName: activity.name,
            activityColor: activity.color,
            activitySetID: activeSet?.id,
            startTime: adjustedStart
        )
        newBlock.endTime    = adjustedEnd
        newBlock.stopState  = "stopped"

        modelContext.insert(newBlock)
        try? modelContext.save()
        onResolved()
        dismiss()
    }
}

// MARK: - Activity Quick Button

struct ActivityQuickButton: View {
    let activity: Activity
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let emoji = activity.emoji {
                    Text(emoji)
                        .font(.title3)
                } else {
                    Circle()
                        .fill(Color(hex: activity.color))
                        .frame(width: 16, height: 16)
                }

                Text(activity.name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Color(hex: activity.color).opacity(0.15))
            .foregroundStyle(.primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

