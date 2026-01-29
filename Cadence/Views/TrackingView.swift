import SwiftUI
import SwiftData

struct TrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var activitySets: [ActivitySet]
    @Query private var activities: [Activity]
    
    @Bindable var manager: TimeTrackingManager
    
    @State private var currentTime = Date()
    @State private var timer: Timer?
    
    var activeSet: ActivitySet? {
        activitySets.first(where: { $0.isActive })
    }
    
    var filteredActivities: [Activity] {
        guard let setID = activeSet?.id else { return [] }
        return activities.filter { $0.setID == setID }.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Current Activity Display
                CurrentActivityCard(manager: manager, currentTime: currentTime)
                    .padding()
                
                // Time Block Indicator
                if let rule = manager.currentTimeBlockRule {
                    HStack {
                        Image(systemName: "clock.badge.checkmark")
                            .foregroundStyle(.blue)
                        Text(rule.name)
                            .font(.subheadline)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(rule.timeRangeDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                }
                
                Divider()
                
                // Activity Set Switcher
                if activitySets.count > 1 {
                    ActivitySetPicker(sets: activitySets)
                        .padding(.horizontal)
                        .padding(.top)
                }
                
                // Activity Grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(filteredActivities) { activity in
                            ActivityButton(
                                activity: activity,
                                isActive: manager.currentTimeBlock?.activityID == activity.id,
                                action: {
                                    manager.startActivity(activity)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Cadence")
            .onAppear {
                startTimer()
            }
            .onDisappear {
                stopTimer()
            }
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            currentTime = Date()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

struct CurrentActivityCard: View {
    let manager: TimeTrackingManager
    let currentTime: Date
    
    var currentDuration: TimeInterval {
        guard let block = manager.currentTimeBlock else { return 0 }
        return block.duration
    }
    
    var isInBackground: Bool {
        manager.backgroundEnteredTime != nil
    }
    
    var backgroundDuration: TimeInterval {
        guard let backgroundTime = manager.backgroundEnteredTime else { return 0 }
        return currentTime.timeIntervalSince(backgroundTime)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            if let block = manager.currentTimeBlock {
                // Active activity
                HStack {
                    Circle()
                        .fill(Color(hex: block.activityColor))
                        .frame(width: 12, height: 12)
                    
                    Text(block.activityName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                
                // Duration display
                Text(currentDuration.detailedFormattedDuration)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                
                // Background indicator
                if isInBackground {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(.purple)
                        Text("Tracking in background for \(backgroundDuration.formattedDuration)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Control buttons
                HStack(spacing: 20) {
                    if block.isPaused {
                        Button(action: {
                            manager.resumeCurrentActivity()
                        }) {
                            Label("Resume", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else {
                        Button(action: {
                            manager.pauseCurrentActivity()
                        }) {
                            Label("Pause", systemImage: "pause.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button(action: {
                        manager.stopCurrentActivity()
                    }) {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                
                if block.isPaused {
                    HStack {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Paused")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
    }
}

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
