import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    let manager: TimeTrackingManager
    
    @State private var stats: DayStats?
    @State private var timeBlocks: [TimeBlock] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let stats = stats {
                        // Summary Cards
                        HStack(spacing: 12) {
                            StatCard(
                                title: "Total Time",
                                value: stats.totalDuration.formattedDuration,
                                icon: "clock.fill",
                                color: .blue
                            )
                            
                            StatCard(
                                title: "Activities",
                                value: "\(stats.blockCount)",
                                icon: "list.bullet",
                                color: .green
                            )
                        }
                        .padding(.horizontal)
                        
                        HStack(spacing: 12) {
                            StatCard(
                                title: "Switches",
                                value: "\(stats.totalSwitches)",
                                icon: "arrow.triangle.2.circlepath",
                                color: .orange
                            )
                            
                            StatCard(
                                title: "Avg Duration",
                                value: stats.blockCount > 0 ? (stats.totalDuration / Double(stats.blockCount)).formattedDuration : "0m",
                                icon: "timer",
                                color: .purple
                            )
                        }
                        .padding(.horizontal)
                        
                        // Activity Breakdown Chart
                        if !stats.sortedActivities.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Activity Breakdown")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                Chart {
                                    ForEach(stats.sortedActivities, id: \.name) { activity in
                                        BarMark(
                                            x: .value("Duration", activity.duration),
                                            y: .value("Activity", activity.name)
                                        )
                                        .foregroundStyle(getActivityColor(activity.name))
                                        .annotation(position: .trailing) {
                                            Text(activity.duration.formattedDuration)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .frame(height: CGFloat(stats.sortedActivities.count) * 50)
                                .chartXAxis {
                                    AxisMarks(position: .bottom)
                                }
                                .padding(.horizontal)
                            }
                            .padding(.vertical)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                        // Timeline Chart
                        if !timeBlocks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Timeline")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                TimelineChart(blocks: timeBlocks)
                                    .frame(height: 60)
                                    .padding(.horizontal)
                            }
                            .padding(.vertical)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                        // Activity List
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Activity Details")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(stats.sortedActivities, id: \.name) { activity in
                                ActivityDetailRow(
                                    name: activity.name,
                                    duration: activity.duration,
                                    percentage: stats.totalDuration > 0 ? (activity.duration / stats.totalDuration) * 100 : 0,
                                    color: getActivityColor(activity.name)
                                )
                            }
                        }
                        .padding(.vertical)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                    } else {
                        ContentUnavailableView(
                            "No Data Yet",
                            systemImage: "chart.bar",
                            description: Text("Start tracking activities to see your stats")
                        )
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Today's Stats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: loadStats) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                loadStats()
                startAutoRefresh()
            }
        }
    }
    
    private func loadStats() {
        stats = manager.getTodaysStats()
        timeBlocks = manager.getTodaysTimeBlocks()
    }
    
    private func startAutoRefresh() {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            loadStats()
        }
    }
    
    private func getActivityColor(_ name: String) -> Color {
        // Find the color from time blocks
        if let block = timeBlocks.first(where: { $0.activityName == name }) {
            return Color(hex: block.activityColor)
        }
        return .gray
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ActivityDetailRow: View {
    let name: String
    let duration: TimeInterval
    let percentage: Double
    let color: Color
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            
            Text(name)
                .font(.subheadline)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(duration.formattedDuration)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                
                Text("\(Int(percentage))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct TimelineChart: View {
    let blocks: [TimeBlock]
    
    private var startOfDay: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    private var endOfDay: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color(.systemGray5))
                
                // Time blocks
                ForEach(blocks.filter { $0.endTime != nil }) { block in
                    let start = block.startTime
                    let end = block.endTime ?? Date()
                    
                    let startOffset = start.timeIntervalSince(startOfDay) / 86400
                    let duration = end.timeIntervalSince(start) / 86400
                    
                    Rectangle()
                        .fill(Color(hex: block.activityColor))
                        .frame(width: geometry.size.width * duration)
                        .offset(x: geometry.size.width * startOffset)
                }
            }
        }
        .cornerRadius(8)
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
        startTime: Date().addingTimeInterval(-7200)
    )
    block1.endTime = Date().addingTimeInterval(-3600)
    
    let block2 = TimeBlock(
        activityID: UUID(),
        activityName: "Email",
        activityColor: "#FF9800",
        startTime: Date().addingTimeInterval(-3600)
    )
    block2.endTime = Date().addingTimeInterval(-1800)
    
    context.insert(block1)
    context.insert(block2)
    
    let manager = TimeTrackingManager(modelContext: context)
    
    return StatsView(manager: manager)
        .modelContainer(container)
}
