//
//  RecordsView.swift (Combined Timeline View)
//  Cadence
//
// View and edit records

import SwiftUI
import SwiftData

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeBlock.startTime, order: .reverse) private var allTimeBlocks: [TimeBlock]
    
    // Filters & Search
    @State private var searchText = ""
    @State private var selectedActivity: String? = nil
    @State private var showingFilters = false
    @State private var hidePauses = false
    @State private var showArchived = false
    
    // Edit state
    @State private var selectedBlock: TimeBlock?
    @State private var conflictDetector: ConflictDetector?
    @State private var gapToResolve: TimeBlock?
    
    // Multi-select for bulk operations
    @State private var isSelectionMode = false
    @State private var selectedBlockIDs: Set<UUID> = []
    
    // Error Handling state [NEW]
    @State private var showingMergeError = false
    @State private var mergeErrorMessage = ""
    
    // Collapsed sections state
    @State private var collapsedSections: Set<String> = []
    
    // MARK: - Computed Properties
    
    private let editCutoffDays = 3
    
    private var editCutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -editCutoffDays, to: Date())!
    }
    
    var filteredBlocks: [TimeBlock] {
        var blocks = allTimeBlocks
        
        if !showArchived {
            let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
            blocks = blocks.filter { $0.startTime >= oneMonthAgo }
        }
        
        if hidePauses {
            blocks = blocks.filter { !$0.isPauseBlock }
        }
        
        if let activity = selectedActivity {
            blocks = blocks.filter { $0.activityName == activity }
        }
        
        if !searchText.isEmpty {
            blocks = blocks.filter { $0.remarks.localizedCaseInsensitiveContains(searchText) }
        }
        
        return blocks
    }
    
    var groupedBlocks: [(section: DateSection, blocks: [TimeBlock])] {
        let grouped = Dictionary(grouping: filteredBlocks) { block in
            DateSection.from(date: block.startTime)
        }
        
        return DateSection.allCases
            .compactMap { section in
                guard let blocks = grouped[section], !blocks.isEmpty else { return nil }
                return (section: section, blocks: blocks.sorted { $0.startTime > $1.startTime })
            }
    }
    
    var uniqueActivities: [String] {
        Array(Set(allTimeBlocks.map { $0.activityName })).sorted()
    }
    
    var archivedCount: Int {
        let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        return allTimeBlocks.filter { $0.startTime < oneMonthAgo }.count
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredBlocks.isEmpty && !showArchived && archivedCount > 0 {
                    archivePromptView
                } else if filteredBlocks.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Records" : "No Results",
                        systemImage: searchText.isEmpty ? "tray" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Start tracking activities to see your records" : "Try adjusting your filters")
                    )
                } else {
                    recordsList
                }
            }
            .navigationTitle("Timeline")
            .searchable(text: $searchText, prompt: "Search remarks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Hide Pauses", isOn: $hidePauses)
                        
                        if isSelectionMode {
                            Divider()
                            Button("Cancel Selection") {
                                isSelectionMode = false
                                selectedBlockIDs.removeAll()
                            }
                        } else {
                            Button(action: { isSelectionMode = true }) {
                                Label("Select Blocks", systemImage: "checkmark.circle")
                            }
                        }
                        
                        Divider()
                        Button(action: { showingFilters.toggle() }) {
                            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FiltersView(selectedActivity: $selectedActivity, activities: uniqueActivities)
            }
            .sheet(item: $selectedBlock) { block in
                let isEditable = block.startTime >= editCutoffDate
                
                if isEditable {
                    // FIX: Safely unwrap or create new detector
                    let detector = conflictDetector ?? ConflictDetector(modelContext: modelContext)
                    BlockEditSheet(
                        block: block,
                        conflictDetector: detector,
                        onSave: { }
                    )
                } else {
                    ReadOnlyBlockDetail(block: block)
                }
            }
            .sheet(item: $gapToResolve) { gap in
                GapResolverSheet(
                    gap: gap,
                    onResolved: { }
                )
            }
            // [NEW] Alert for merge errors
            .alert("Cannot Merge", isPresented: $showingMergeError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(mergeErrorMessage)
            }
            .onAppear {
                conflictDetector = ConflictDetector(modelContext: modelContext)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var recordsList: some View {
        VStack(spacing: 0) {
            List {
                // Collapsible date sections
                ForEach(groupedBlocks, id: \.section) { group in
                    Section {
                        if !collapsedSections.contains(group.section.id) {
                            // Day Summary
                            DaySummaryBar(
                                date: group.blocks.first?.startTime ?? Date(),
                                totalTracked: totalTracked(for: group.blocks),
                                gapCount: gaps(in: group.blocks).count,
                                totalGapTime: totalGapTime(for: group.blocks),
                                onResolveAllGaps: { }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            
                            // Blocks
                            ForEach(group.blocks) { block in
                                let isEditable = block.startTime >= editCutoffDate
                                
                                AuditRow(
                                    block: block,
                                    isSelected: selectedBlockIDs.contains(block.id),
                                    isSelectionMode: isSelectionMode,
                                    isEditable: isEditable,
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
                    } header: {
                        sectionHeader(for: group.section, blocks: group.blocks)
                    }
                }
                
                // Archive toggle at bottom
                if archivedCount > 0 {
                    Section {
                        Button {
                            withAnimation { showArchived.toggle() }
                        } label: {
                            HStack {
                                Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                                    .foregroundColor(.orange)
                                Text(showArchived ? "Hide Archived Records" : "Show Archived Records (\(archivedCount))")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            
            // Bottom toolbar (only in selection mode)
            if isSelectionMode {
                bottomToolbar
            }
        }
    }
    
    private func sectionHeader(for section: DateSection, blocks: [TimeBlock]) -> some View {
        Button {
            withAnimation {
                if collapsedSections.contains(section.id) {
                    collapsedSections.remove(section.id)
                } else {
                    collapsedSections.insert(section.id)
                }
            }
        } label: {
            HStack {
                Image(systemName: section.icon)
                    .font(.subheadline)
                    .foregroundStyle(section.iconColor)
                
                Text(section.rawValue)
                    .font(.headline)
                
                Image(systemName: collapsedSections.contains(section.id) ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Quick stats badge
                Text("\(blocks.count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(section.iconColor)
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
    }
    
    private var archivePromptView: some View {
        VStack(spacing: 20) {
            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Recent Records")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("You have \(archivedCount) archived records")
                .foregroundStyle(.secondary)
            
            Button {
                withAnimation { showArchived = true }
            } label: {
                Label("View Archived Records", systemImage: "archivebox.fill")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
    }
    
    private var bottomToolbar: some View {
        HStack(spacing: 20) {
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
    
    // MARK: - Helper Methods
    
    private func totalTracked(for blocks: [TimeBlock]) -> TimeInterval {
        blocks.filter { !$0.isGap && !$0.isPauseBlock }
            .reduce(0) { $0 + $1.duration }
    }
    
    private func gaps(in blocks: [TimeBlock]) -> [TimeBlock] {
        blocks.filter { $0.isGap }
    }
    
    private func totalGapTime(for blocks: [TimeBlock]) -> TimeInterval {
        gaps(in: blocks).reduce(0) { $0 + $1.duration }
    }
    
    private func toggleSelection(_ block: TimeBlock) {
        if selectedBlockIDs.contains(block.id) {
            selectedBlockIDs.remove(block.id)
        } else {
            selectedBlockIDs.insert(block.id)
        }
    }
    
    private func mergeSelected() {
        let toMerge = filteredBlocks
            .filter { selectedBlockIDs.contains($0.id) }
            .sorted { $0.startTime < $1.startTime }
        
        guard toMerge.count >= 2 else { return }
        
        // [UPDATED] Check 1: Ensure no active blocks (block with nil endTime)
        if toMerge.contains(where: { $0.endTime == nil }) {
            mergeErrorMessage = "You cannot merge an active/ongoing activity. Please stop the activity first."
            showingMergeError = true
            return
        }
        
        let editor = TimeBlockEditor(modelContext: modelContext)
        
        // [UPDATED] Check 2: Check connectivity/adjacency with feedback
        guard editor.canMerge(toMerge) else {
            mergeErrorMessage = "Selected blocks must be adjacent to merge (no gaps between them)."
            showingMergeError = true
            return
        }
        
        let targetActivity = findActivity(for: toMerge.first!)
        
        do {
            try editor.mergeBlocks(toMerge, intoActivity: targetActivity)
            selectedBlockIDs.removeAll()
            isSelectionMode = false
        } catch {
            // [UPDATED] Catch internal editor errors and show them
            mergeErrorMessage = "Merge failed: \(error.localizedDescription)"
            showingMergeError = true
        }
    }
    
    private func findActivity(for block: TimeBlock) -> Activity? {
        guard let activityID = block.activityID else { return nil }
        let descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.id == activityID }
        )
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Date Section Enum (Enhanced)

enum DateSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case twoDaysAgo = "2 Days Ago"
    case threeDaysAgo = "3 Days Ago"
    case fourDaysAgo = "4 Days Ago"
    case fiveDaysAgo = "5 Days Ago"
    case sixDaysAgo = "6 Days Ago"
    case lastWeek = "Last Week"
    case lastMonth = "Last Month"
    case lastThreeMonths = "Last 3 Months"
    case lastSixMonths = "Last 6 Months"
    case lastYear = "Last Year"
    case older = "Older"
    
    var id: String { rawValue }
    
    static func from(date: Date) -> DateSection {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        
        let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        
        switch daysAgo {
        case 2: return .twoDaysAgo
        case 3: return .threeDaysAgo
        case 4: return .fourDaysAgo
        case 5: return .fiveDaysAgo
        case 6: return .sixDaysAgo
        case 7...30: return .lastWeek
        case 31...90: return .lastMonth
        case 91...180: return .lastThreeMonths
        case 181...365: return .lastSixMonths
        case 366...730: return .lastYear
        default: return .older
        }
    }
    
    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .yesterday: return "moon.fill"
        case .twoDaysAgo, .threeDaysAgo, .fourDaysAgo, .fiveDaysAgo, .sixDaysAgo, .lastWeek: return "calendar"
        case .lastMonth: return "calendar.badge.clock"
        case .lastThreeMonths, .lastSixMonths: return "calendar.circle"
        case .lastYear, .older: return "archivebox"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .today: return .orange
        case .yesterday: return .blue
        case .twoDaysAgo, .threeDaysAgo: return .purple
        case .fourDaysAgo, .fiveDaysAgo, .sixDaysAgo, .lastWeek: return .green
        case .lastMonth, .lastThreeMonths: return .cyan
        case .lastSixMonths, .lastYear, .older: return .gray
        }
    }
}

struct DaySummaryBar: View {
    let date: Date
    let totalTracked: TimeInterval
    let gapCount: Int
    let totalGapTime: TimeInterval
    let onResolveAllGaps: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                StatPill(
                    icon: "clock.fill",
                    label: "Tracked",
                    value: totalTracked.formattedDuration,
                    color: .blue
                )
                
                if gapCount > 0 {
                    StatPill(
                        icon: "exclamationmark.triangle.fill",
                        label: "\(gapCount) Gap\(gapCount == 1 ? "" : "s")",
                        value: totalGapTime.formattedDuration,
                        color: .orange
                    )
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

// MARK: - Read-Only Block Detail

struct ReadOnlyBlockDetail: View {
    @Environment(\.dismiss) private var dismiss
    let block: TimeBlock
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Lock notice
                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Read-Only")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Records older than 3 days cannot be edited")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Block details
                    VStack(spacing: 16) {
                        HStack {
                            Circle()
                                .fill(Color(hex: block.activityColor))
                                .frame(width: 40, height: 40)
                            
                            VStack(alignment: .leading) {
                                Text(block.displayName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Text(block.blockType.capitalized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        
                        VStack(spacing: 4) {
                            Text(block.duration.detailedFormattedDuration)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("Duration")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(block.activityColor).opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Time details
                    VStack(spacing: 12) {
                        DetailRow(label: "Started", value: block.startTime.formatted(date: .abbreviated, time: .shortened), icon: "clock")
                        
                        if let endTime = block.endTime {
                            DetailRow(label: "Ended", value: endTime.formatted(date: .abbreviated, time: .shortened), icon: "clock.fill")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Remarks
                    if !block.remarks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Remarks", systemImage: "note.text").font(.headline)
                            Text(block.remarks)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Record Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    let icon: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Label(label, systemImage: icon).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).foregroundColor(valueColor)
        }
    }
}

// MARK: - Filters View

struct FiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedActivity: String?
    let activities: [String]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    Picker("Filter by Activity", selection: $selectedActivity) {
                        Text("All Activities").tag(nil as String?)
                        ForEach(activities, id: \.self) { activity in
                            Text(activity).tag(activity as String?)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Activity.self, ActivitySet.self, TimeBlock.self, TimeBlockRule.self, configurations: config)
    
    return RecordsView()
        .modelContainer(container)
}
