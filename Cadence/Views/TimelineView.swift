import SwiftUI
import SwiftData

struct TimelineView: View {
    let manager: TimeTrackingManager
    
    @State private var timeBlocks: [TimeBlock] = []
    @State private var refreshTrigger = false
    
    var body: some View {
        NavigationStack {
            Group {
                if timeBlocks.isEmpty {
                    ContentUnavailableView(
                        "No Activities Yet",
                        systemImage: "clock",
                        description: Text("Start tracking activities to see your timeline")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(timeBlocks) { block in
                                TimeBlockRow(block: block)
                                
                                if block.id != timeBlocks.last?.id {
                                    Divider()
                                        .padding(.leading, 70)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Today's Timeline")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: loadTimeBlocks) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                loadTimeBlocks()
                startAutoRefresh()
            }
        }
    }
    
    private func loadTimeBlocks() {
        timeBlocks = manager.getTodaysTimeBlocks()
    }
    
    private func startAutoRefresh() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            loadTimeBlocks()
        }
    }
}

struct TimeBlockRow: View {
    let block: TimeBlock
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Time indicator
            VStack(alignment: .trailing, spacing: 2) {
                Text(block.startTime, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let endTime = block.endTime {
                    Text("↓")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    Text(endTime, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("now")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 50)
            
            // Activity indicator
            VStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: block.activityColor))
                    .frame(width: 12, height: 12)
                
                if block.endTime != nil {
                    Rectangle()
                        .fill(Color(hex: block.activityColor).opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            
            // Activity details
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(block.activityName)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(block.duration.formattedDuration)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                
                if block.switchCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                        Text("\(block.switchCount) resume\(block.switchCount == 1 ? "" : "s")")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                
                if block.totalPauseDuration > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.circle")
                            .font(.caption2)
                        Text("\(block.totalPauseDuration.formattedDuration) paused")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }
                
                if block.endTime == nil {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                        Text(block.isPaused ? "Paused" : "Active")
                            .font(.caption)
                    }
                    .foregroundStyle(block.isPaused ? .orange : .green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .padding(.horizontal)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Activity.self, ActivitySet.self, TimeBlock.self, configurations: config)
    let context = container.mainContext
    
    // Create preview data
    let block1 = TimeBlock(
        activityID: UUID(),
        activityName: "Deep Work",
        activityColor: "#4CAF50",
        startTime: Date().addingTimeInterval(-3600)
    )
    block1.endTime = Date().addingTimeInterval(-1800)
    block1.switchCount = 2
    
    let block2 = TimeBlock(
        activityID: UUID(),
        activityName: "Email",
        activityColor: "#FF9800",
        startTime: Date().addingTimeInterval(-1800)
    )
    block2.endTime = Date().addingTimeInterval(-900)
    
    let block3 = TimeBlock(
        activityID: UUID(),
        activityName: "Meetings",
        activityColor: "#2196F3",
        startTime: Date().addingTimeInterval(-900)
    )
    
    context.insert(block1)
    context.insert(block2)
    context.insert(block3)
    
    let manager = TimeTrackingManager(modelContext: context)
    
    return TimelineView(manager: manager)
        .modelContainer(container)
}
