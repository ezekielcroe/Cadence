//
//  DayTimelineView.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 30/1/26.
//


// MARK: - Vertical Timeline View for Single Day

import SwiftUI
import SwiftData

struct DayTimelineView: View {
    let date: Date
    @Environment(\.modelContext) private var modelContext
    
    @State private var blocks: [TimeBlock] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header with date
                HStack {
                    VStack(alignment: .leading) {
                        Text(date, style: .date)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(dayStats)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                
                if blocks.isEmpty {
                    ContentUnavailableView(
                        "No Activities",
                        systemImage: "calendar.badge.clock",
                        description: Text("No activities tracked for this day")
                    )
                    .frame(height: 300)
                } else {
                    // Timeline
                    TimelineContent(blocks: blocks)
                        .padding(.horizontal)
                }
            }
        }
        .onAppear {
            loadBlocks()
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var dayStats: String {
        let totalDuration = blocks.reduce(0.0) { $0 + $1.duration }
        let activityCount = blocks.filter { $0.isRegularActivity }.count
        return "\(totalDuration.formattedDuration) • \(activityCount) activities"
    }
    
    private func loadBlocks() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime >= startOfDay && block.startTime < endOfDay
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        
        blocks = (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - Timeline Content

struct TimelineContent: View {
    let blocks: [TimeBlock]
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                TimelineBlockRow(
                    block: block,
                    isFirst: index == 0,
                    isLast: index == blocks.count - 1
                )
            }
        }
    }
}

// MARK: - Timeline Block Row

struct TimelineBlockRow: View {
    let block: TimeBlock
    let isFirst: Bool
    let isLast: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: Time column
            VStack(alignment: .trailing, spacing: 4) {
                Text(block.startTime, style: .time)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .frame(width: 60, alignment: .trailing)
                
                if let endTime = block.endTime {
                    Text(endTime, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
                
                Spacer()
            }
            
            // Center: Timeline line with dot
            VStack(spacing: 0) {
                // Top line
                if !isFirst {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 2)
                        .frame(height: 8)
                }
                
                // Dot
                Circle()
                    .fill(Color(hex: block.activityColor))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(radius: 2)
                
                // Connecting line to bottom
                if !isLast {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            
            // Right: Content card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(block.displayName)
                        .font(.headline)
                    
                    Spacer()
                    
                    // Block type badge
                    if block.isGap {
                        Text("Gap")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    } else if block.isPauseBlock {
                        Text("Pause")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                // Duration
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(block.duration.formattedDuration)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    // Stop state
                    if block.stopState != "ongoing" {
                        Text(block.stopState.capitalized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.secondary)
                
                // Additional info
                if block.switchCount > 0 {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                        Text("\(block.switchCount) switches")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                }
                
                // Remarks preview
                if !block.remarks.isEmpty {
                    Text(block.remarks)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .padding(.top, 4)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: block.activityColor).opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(hex: block.activityColor).opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Integration: Add Timeline Button to RecordsView

// Add this to your existing RecordsView toolbar:
/*
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Menu {
            Button(action: { 
                showingTimeline = true 
            }) {
                Label("Day Timeline", systemImage: "chart.bar.xaxis")
            }
            
            Toggle("Hide Pauses", isOn: $hidePauses)
            
            Divider()
            
            Button(action: { showingFilters.toggle() }) {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}
.sheet(isPresented: $showingTimeline) {
    NavigationStack {
        DayTimelineView(date: selectedDate)
    }
}
*/

// Or add Timeline as a section in RecordsView for Today:
/*
if selectedDateRange == .today && !filteredBlocks.isEmpty {
    Section {
        NavigationLink {
            DayTimelineView(date: Date())
        } label: {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundColor(.blue)
                Text("View Timeline")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
*/