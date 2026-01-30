import SwiftUI
import SwiftData
import Combine

struct TrackingView: View {
    @ObservedObject var manager: TimeTrackingManager
    @Environment(\.modelContext) private var modelContext
    
    @Query private var activitySets: [ActivitySet]
    @Query private var activities: [Activity]
    
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var activeSet: ActivitySet? {
        activitySets.first { $0.isActive }
    }
    
    var activeSetActivities: [Activity] {
        guard let setID = activeSet?.id else { return [] }
        return activities.filter { $0.setID == setID }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    // Check if current block is a Pause
    var isCurrentlyPaused: Bool {
        manager.currentTimeBlock?.isPauseBlock ?? false
    }
    
    // Get the last activity before pause (for Resume button)
    var lastActivityBeforePause: Activity? {
        guard isCurrentlyPaused else { return nil }
        
        // Find the most recent non-pause/non-gap activity
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.blockType == "activity" && block.endTime != nil
            },
            sortBy: [SortDescriptor(\.endTime, order: .reverse)]
        )
        
        guard let lastActivityBlock = try? modelContext.fetch(descriptor).first,
              let activityID = lastActivityBlock.activityID,
              let activity = activities.first(where: { $0.id == activityID }) else {
            return nil
        }
        
        return activity
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Activity Set Picker
                    if activitySets.count > 1 {
                        ActivitySetPicker(sets: activitySets)
                    }
                    
                    // Current Activity Display
                    CurrentActivityCard(
                        block: manager.currentTimeBlock,
                        isPaused: isCurrentlyPaused,
                        onPause: {
                            manager.pauseCurrentActivity()
                        },
                        onStop: {
                            manager.stopCurrentActivity()
                        },
                        onResume: {
                            if let activity = lastActivityBeforePause {
                                manager.resumeFromPause(activity)
                            }
                        }
                    )
                    
                    // Activity Buttons Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(activeSetActivities) { activity in
                            ActivityButton(
                                activity: activity,
                                isActive: manager.currentTimeBlock?.activityID == activity.id && !isCurrentlyPaused
                            ) {
                                if isCurrentlyPaused {
                                    // If currently paused, resume with this activity
                                    manager.resumeFromPause(activity)
                                } else {
                                    // Normal activity start
                                    manager.startActivity(activity)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top)
            }
            .navigationTitle("Track")
            .onReceive(timer) { _ in
                if manager.currentTimeBlock != nil {
                    manager.objectWillChange.send()
                }
            }
        }
    }
}

// MARK: - Current Activity Card
struct CurrentActivityCard: View {
    let block: TimeBlock?
    let isPaused: Bool
    let onPause: () -> Void
    let onStop: () -> Void
    let onResume: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            if let block = block {
                VStack(spacing: 12) {
                    // Activity name and duration
                    HStack {
                        Circle()
                            .fill(Color(hex: block.activityColor))
                            .frame(width: 16, height: 16)
                        
                        Text(block.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    Text(block.duration.detailedFormattedDuration)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    
                    // Show pause/gap indicator
                    if isPaused {
                        HStack {
                            Image(systemName: "pause.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Paused")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    } else if block.isGap {
                        HStack {
                            Image(systemName: "timer")
                                .foregroundStyle(.gray)
                            Text("Not tracking")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Elapsed time since start
                    Text("Since \(block.startTime, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Control buttons
                HStack(spacing: 20) {
                    if isPaused {
                        // Resume button
                        Button(action: onResume) {
                            Label("Resume", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else if !block.isGap {
                        // Regular activity controls
                        Button(action: onPause) {
                            Label("Pause", systemImage: "pause.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: onStop) {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                
            } else {
                // No active activity
                VStack(spacing: 12) {
                    Image(systemName: "timer")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("No Active Activity")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("Tap an activity below to start tracking")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

// MARK: - Activity Button
struct ActivityButton: View {
    let activity: Activity
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: activity.color))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: isActive ? 3 : 0)
                    )
                
                Text(activity.name)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isActive ? Color(hex: activity.color).opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color(hex: activity.color) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity Set Picker
struct ActivitySetPicker: View {
    let sets: [ActivitySet]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        HStack {
            Text("Activity Set:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Picker("Set", selection: binding) {
                ForEach(sets) { set in
                    Text(set.name).tag(set.id)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var binding: Binding<UUID> {
        Binding(
            get: { sets.first(where: { $0.isActive })?.id ?? sets.first?.id ?? UUID() },
            set: { newID in
                for set in sets {
                    set.isActive = (set.id == newID)
                }
                try? modelContext.save()
            }
        )
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Activity.self, ActivitySet.self, TimeBlock.self, configurations: config)
    let context = container.mainContext
    
    // Create preview data
    let workSet = ActivitySet(name: "Work", isActive: true)
    context.insert(workSet)
    
    let activity1 = Activity(name: "Deep Work", color: "#4CAF50", setID: workSet.id)
    let activity2 = Activity(name: "Meetings", color: "#2196F3", setID: workSet.id, sortOrder: 1)
    context.insert(activity1)
    context.insert(activity2)
    
    let manager = TimeTrackingManager(modelContext: context)
    
    return TrackingView(manager: manager)
        .modelContainer(container)
}
