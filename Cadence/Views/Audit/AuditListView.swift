//
//  AuditListView.swift
//  Cadence
//
//  Precision time block auditing interface
//

import SwiftUI
import SwiftData

struct AuditListView: View {
    @Environment(\.modelContext) private var modelContext
    
    let date: Date
    
    @State private var blocks: [TimeBlock] = []
    @State private var selectedBlock: TimeBlock?
    @State private var gapToResolve: TimeBlock?
    @State private var conflictDetector: ConflictDetector?
    
    // Multi-select for bulk operations
    @State private var isSelectionMode = false
    @State private var selectedBlockIDs: Set<UUID> = []
    
    private var sortedBlocks: [TimeBlock] {
        blocks.sorted { $0.startTime < $1.startTime }
    }
    
    private var gaps: [TimeBlock] {
        blocks.filter { $0.isGap }
    }
    
    private var totalTracked: TimeInterval {
        blocks.filter { !$0.isGap && !$0.isPauseBlock }
            .reduce(0) { $0 + $1.duration }
    }
    
    private var totalGapTime: TimeInterval {
        gaps.reduce(0) { $0 + $1.duration }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Summary Header
            DaySummaryBar(
                date: date,
                totalTracked: totalTracked,
                gapCount: gaps.count,
                totalGapTime: totalGapTime,
                onResolveAllGaps: { showBulkGapResolver() }
            )
            
            if blocks.isEmpty {
                emptyState
            } else {
                blockList
            }
            
            bottomToolbar
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            conflictDetector = ConflictDetector(modelContext: modelContext)
            loadBlocks()
        }
        .refreshable {
            loadBlocks()
        }
        .sheet(item: $selectedBlock) { block in
            BlockEditSheet(
                block: block,
                conflictDetector: conflictDetector!,
                onSave: { loadBlocks() }
            )
        }
        .sheet(item: $gapToResolve) { gap in
            GapResolverSheet(
                gap: gap,
                onResolved: { loadBlocks() }
            )
        }
    }
    
    // MARK: - Subviews
    
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Activities", systemImage: "clock")
        } description: {
            Text("No time blocks recorded for this day")
        }
    }
    
    private var blockList: some View {
        List {
            ForEach(sortedBlocks) { block in
                AuditRow(
                    block: block,
                    isSelected: selectedBlockIDs.contains(block.id),
                    isSelectionMode: isSelectionMode,
                    onTap: {
                        if isSelectionMode {
                            toggleSelection(block)
                        } else {
                            selectedBlock = block
                        }
                    },
                    onResolveGap: {
                        gapToResolve = block
                    }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Bottom Toolbar
    
    private var bottomToolbar: some View {
        HStack(spacing: 20) {
            if isSelectionMode {
                // Selection mode: Show merge and cancel
                Button("Cancel") {
                    isSelectionMode = false
                    selectedBlockIDs.removeAll()
                }
                
                Spacer()
                
                if !selectedBlockIDs.isEmpty {
                    Text("\(selectedBlockIDs.count) selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button("Merge") {
                        mergeSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedBlockIDs.count < 2)
                }
            } else {
                // Normal mode: Show select and resolve all gaps buttons
                if !gaps.isEmpty {
                    Button {
                        showBulkGapResolver()
                    } label: {
                        Label("Resolve All Gaps", systemImage: "exclamationmark.triangle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
                
                Spacer()
                
                Button {
                    isSelectionMode = true
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color(.separator)),
            alignment: .top
        )
    }
    
    // MARK: - Actions
    
    private func loadBlocks() {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime >= dayStart && block.startTime < dayEnd
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        
        blocks = (try? modelContext.fetch(descriptor)) ?? []
    }
    
    private func toggleSelection(_ block: TimeBlock) {
        if selectedBlockIDs.contains(block.id) {
            selectedBlockIDs.remove(block.id)
        } else {
            selectedBlockIDs.insert(block.id)
        }
    }
    
    private func mergeSelected() {
        // Get blocks in order
        let toMerge = sortedBlocks.filter { selectedBlockIDs.contains($0.id) }
        guard toMerge.count >= 2 else { return }
        
        // Check if they're adjacent
        let editor = TimeBlockEditor(modelContext: modelContext)
        guard editor.canMerge(toMerge) else {
            // Show error
            return
        }
        
        // Use the first block's activity for the merged result
        let targetActivity = findActivity(for: toMerge.first!)
        
        do {
            try editor.mergeBlocks(toMerge, intoActivity: targetActivity)
            selectedBlockIDs.removeAll()
            isSelectionMode = false
            loadBlocks()
        } catch {
            print("Merge failed: \(error)")
        }
    }
    
    private func showBulkGapResolver() {
        // TODO: Implement bulk gap resolution
    }
    
    private func findActivity(for block: TimeBlock) -> Activity? {
        guard let activityID = block.activityID else { return nil }
        let descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.id == activityID }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Day Summary Bar

struct DaySummaryBar: View {
    let date: Date
    let totalTracked: TimeInterval
    let gapCount: Int
    let totalGapTime: TimeInterval
    let onResolveAllGaps: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Stats row
            HStack(spacing: 20) {
                StatPill(
                    icon: "clock.fill",
                    label: "Tracked",
                    value: totalTracked.formattedDuration,
                    color: .blue
                )
                
                if gapCount > 0 {
                    Button(action: onResolveAllGaps) {
                        StatPill(
                            icon: "exclamationmark.triangle.fill",
                            label: "\(gapCount) Gap\(gapCount == 1 ? "" : "s")",
                            value: totalGapTime.formattedDuration,
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    StatPill(
                        icon: "checkmark.circle.fill",
                        label: "Gaps",
                        value: "None",
                        color: .green
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
}

struct StatPill: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}
