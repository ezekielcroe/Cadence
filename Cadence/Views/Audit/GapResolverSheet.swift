//
//  GapResolverSheet.swift
//  Cadence
//
//  Convert a gap into a tracked activity
//

import SwiftUI
import SwiftData

struct GapResolverSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let gap: TimeBlock
    let onResolved: () -> Void
    
    @Query private var activities: [Activity]
    @Query private var activitySets: [ActivitySet]
    
    @State private var selectedActivity: Activity?
    @State private var adjustedStartTime: Date
    @State private var adjustedEndTime: Date
    @State private var showingActivityPicker = false
    
    // Common quick actions
    @State private var recentActivities: [Activity] = []
    
    init(gap: TimeBlock, onResolved: @escaping () -> Void) {
        self.gap = gap
        self.onResolved = onResolved
        _adjustedStartTime = State(initialValue: gap.startTime)
        _adjustedEndTime = State(initialValue: gap.endTime ?? Date())
    }
    
    private var activeSet: ActivitySet? {
        activitySets.first { $0.isActive }
    }
    
    private var setActivities: [Activity] {
        guard let setID = activeSet?.id else { return activities }
        return activities.filter { $0.setID == setID }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Gap info header
                    gapInfoCard
                    
                    // Quick assign section
                    quickAssignSection
                    
                    // Time adjustment (optional)
                    timeAdjustmentSection
                
                    // Help section
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
        .onAppear {
            loadRecentActivities()
        }
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
                    
                    Text("\(gap.startTime.formatted(date: .omitted, time: .shortened)) → \(gap.endTime?.formatted(date: .omitted, time: .shortened) ?? "now")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(gap.duration.formattedDuration)
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
            
            // Recently used activities
            if !recentActivities.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(recentActivities.prefix(4)) { activity in
                            ActivityQuickButton(activity: activity) {
                                resolveGap(with: activity)
                            }
                        }
                    }
                }
            }
            
            // Current set activities
            VStack(alignment: .leading, spacing: 8) {
                Text(activeSet?.name ?? "Activities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(setActivities.prefix(6)) { activity in
                        ActivityQuickButton(activity: activity) {
                            resolveGap(with: activity)
                        }
                    }
                }
                
                Button {
                    showingActivityPicker = true
                } label: {
                    Label("More Activities...", systemImage: "ellipsis.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
            }
        }
        .sheet(isPresented: $showingActivityPicker) {
            ActivityPickerSheet(activities: activities) { activity in
                resolveGap(with: activity)
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
                        DatePicker("", selection: $adjustedStartTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    
                    HStack {
                        Text("End")
                        Spacer()
                        DatePicker("", selection: $adjustedEndTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    
                    if adjustedStartTime != gap.startTime || adjustedEndTime != (gap.endTime ?? Date()) {
                        Text("Gap will be adjusted to \(adjustedDuration.formattedDuration)")
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
            Label("Need Help?", systemImage: "questionmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Gaps represent untracked time and must be assigned to an activity. If this gap shouldn't exist, you can merge surrounding blocks in the Timeline view.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Computed
    
    private var adjustedDuration: TimeInterval {
        adjustedEndTime.timeIntervalSince(adjustedStartTime)
    }
    
    // MARK: - Actions
    
    private func loadRecentActivities() {
        // Find activities used in the last 7 days
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime >= weekAgo && block.blockType == "activity"
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        
        guard let recentBlocks = try? modelContext.fetch(descriptor) else { return }
        
        // Get unique activity IDs in order of recency
        var seen = Set<UUID>()
        var recentIDs: [UUID] = []
        
        for block in recentBlocks {
            if let id = block.activityID, !seen.contains(id) {
                seen.insert(id)
                recentIDs.append(id)
            }
        }
        
        // Map to activities
        recentActivities = recentIDs.compactMap { id in
            activities.first { $0.id == id }
        }
    }
    
    private func resolveGap(with activity: Activity) {
        // Convert the gap to an activity
        gap.activityID = activity.id
        gap.activityName = activity.name
        gap.activityColor = activity.color
        gap.activitySetID = activity.setID
        gap.blockType = "activity"
        
        // Apply time adjustments if changed
        if adjustedStartTime != gap.startTime {
            gap.startTime = adjustedStartTime
        }
        if adjustedEndTime != (gap.endTime ?? Date()) {
            gap.endTime = adjustedEndTime
        }
        
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
                } else {
                    Circle()
                        .fill(Color(activity.color))
                        .frame(width: 16, height: 16)
                }
                
                Text(activity.name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Color(activity.color).opacity(0.15))
            .foregroundStyle(.primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity Picker Sheet

struct ActivityPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let activities: [Activity]
    let onSelect: (Activity) -> Void
    
    @State private var searchText = ""
    
    private var filteredActivities: [Activity] {
        if searchText.isEmpty {
            return activities
        }
        return activities.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredActivities) { activity in
                Button {
                    onSelect(activity)
                    dismiss()
                } label: {
                    HStack {
                        if let emoji = activity.emoji {
                            Text(emoji)
                                .font(.title3)
                        }
                        
                        Circle()
                            .fill(Color(activity.color))
                            .frame(width: 20, height: 20)
                        
                        Text(activity.name)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search activities")
            .navigationTitle("Choose Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
