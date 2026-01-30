// MARK: - Enhanced RecordsView with Collapsible Sections and Detail View

import SwiftUI
import SwiftData

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeBlock.startTime, order: .reverse) private var allTimeBlocks: [TimeBlock]
    
    @State private var searchText = ""
    @State private var selectedActivity: String? = nil
    @State private var showingFilters = false
    @State private var hidePauses = false
    @State private var showingTimeline = false
    @State private var selectedBlock: TimeBlock?
    @State private var showArchived = false  // NEW: Show/hide archived records
    
    // Collapsed sections state
    @State private var collapsedSections: Set<String> = []
    
    var filteredBlocks: [TimeBlock] {
        var blocks = allTimeBlocks
        
        // Archive filter - hide blocks older than 1 month unless showArchived is true
        if !showArchived {
            let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
            blocks = blocks.filter { $0.startTime >= oneMonthAgo }
        }
        
        // Filter pauses
        if hidePauses {
            blocks = blocks.filter { !$0.isPauseBlock }
        }
        
        // Filter by activity
        if let activity = selectedActivity {
            blocks = blocks.filter { $0.activityName == activity }
        }
        
        // Search in remarks
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
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredBlocks.isEmpty && !showArchived && archivedCount > 0 {
                    // Show archived records available message
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
                            withAnimation {
                                showArchived = true
                            }
                        } label: {
                            Label("View Archived Records", systemImage: "archivebox.fill")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                } else if filteredBlocks.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Records" : "No Results",
                        systemImage: searchText.isEmpty ? "tray" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Start tracking activities to see your records" : "Try adjusting your filters")
                    )
                } else {
                    List {
                        // Timeline button for recent records
                        if groupedBlocks.contains(where: { $0.section == .today }) {
                            Section {
                                Button {
                                    showingTimeline = true
                                } label: {
                                    HStack {
                                        Image(systemName: "chart.bar.xaxis")
                                            .foregroundColor(.blue)
                                            .font(.title3)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("View Day Timeline")
                                                .font(.headline)
                                            Text("Visual timeline of today's activities")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Collapsible date sections
                        ForEach(groupedBlocks, id: \.section) { group in
                            CollapsibleSection(
                                section: group.section,
                                blocks: group.blocks,
                                isCollapsed: collapsedSections.contains(group.section.id),
                                onToggle: {
                                    withAnimation {
                                        if collapsedSections.contains(group.section.id) {
                                            collapsedSections.remove(group.section.id)
                                        } else {
                                            collapsedSections.insert(group.section.id)
                                        }
                                    }
                                },
                                onSelectBlock: { block in
                                    selectedBlock = block
                                }
                            )
                        }
                        
                        // Archive toggle at bottom
                        if archivedCount > 0 {
                            Section {
                                Button {
                                    withAnimation {
                                        showArchived.toggle()
                                    }
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
                }
            }
            .navigationTitle("Records")
            .searchable(text: $searchText, prompt: "Search remarks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
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
            .sheet(isPresented: $showingFilters) {
                FiltersView(
                    selectedActivity: $selectedActivity,
                    activities: uniqueActivities
                )
            }
            .sheet(isPresented: $showingTimeline) {
                NavigationStack {
                    DayTimelineView(date: Date())
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingTimeline = false
                                }
                            }
                        }
                }
            }
            .sheet(item: $selectedBlock) { block in
                RecordDetailView(block: block)
            }
        }
    }
}

// MARK: - Date Section Enum

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
        
        if calendar.isDateInToday(date) {
            return .today
        } else if calendar.isDateInYesterday(date) {
            return .yesterday
        }
        
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
        case .twoDaysAgo, .threeDaysAgo, .fourDaysAgo, .fiveDaysAgo, .sixDaysAgo, .lastWeek:
            return "calendar"
        case .lastMonth: return "calendar.badge.clock"
        case .lastThreeMonths, .lastSixMonths: return "calendar.circle"
        case .lastYear, .older: return "archivebox"
        }
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection: View {
    let section: DateSection
    let blocks: [TimeBlock]
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onSelectBlock: (TimeBlock) -> Void
    
    var sectionStats: String {
        let totalDuration = blocks.reduce(0.0) { $0 + $1.duration }
        return "\(totalDuration.formattedDuration) • \(blocks.count) records"
    }
    
    var body: some View {
        Section {
            if !isCollapsed {
                ForEach(blocks) { block in
                    Button {
                        onSelectBlock(block)
                    } label: {
                        RecordRowCompact(block: block)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            // Edit action - show edit sheet
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            // Merge/Split action
                        } label: {
                            Label("Merge/Split", systemImage: "arrow.left.arrow.right")
                        }
                        .tint(.orange)
                    }
                }
            }
        } header: {
            Button {
                onToggle()
            } label: {
                HStack {
                    Image(systemName: section.icon)
                        .font(.subheadline)
                    
                    Text(section.rawValue)
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(sectionStats)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Compact Record Row

struct RecordRowCompact: View {
    let block: TimeBlock
    
    var body: some View {
        HStack(spacing: 12) {
            // Color indicator
            Circle()
                .fill(Color(hex: block.activityColor))
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 4) {
                // Activity name with badges
                HStack {
                    Text(block.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if block.isGap {
                        Text("Gap")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(3)
                    } else if block.isPauseBlock {
                        Text("Pause")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
                
                // Time and duration
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text(block.startTime, style: .time)
                        Text("→")
                        if let endTime = block.endTime {
                            Text(endTime, style: .time)
                        } else {
                            Text("now")
                        }
                    }
                    .font(.caption)
                    
                    Text("•")
                        .font(.caption2)
                    
                    Text(block.duration.formattedDuration)
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                
                // Remarks preview (if exists)
                if !block.remarks.isEmpty {
                    Text(block.remarks)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Chevron to indicate tappable
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Record Detail View

struct RecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let block: TimeBlock
    
    @State private var showingEditSheet = false
    @State private var showingMergeSplitSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header card
                    VStack(spacing: 16) {
                        // Activity name with color
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
                        
                        // Duration - large and prominent
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
                        .background(Color(hex: block.activityColor).opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Time details
                    VStack(spacing: 12) {
                        DetailRow(
                            label: "Started",
                            value: block.startTime.formatted(date: .abbreviated, time: .shortened),
                            icon: "clock"
                        )
                        
                        if let endTime = block.endTime {
                            DetailRow(
                                label: "Ended",
                                value: endTime.formatted(date: .abbreviated, time: .shortened),
                                icon: "clock.fill"
                            )
                        } else {
                            DetailRow(
                                label: "Status",
                                value: "Ongoing",
                                icon: "clock.fill",
                                valueColor: .green
                            )
                        }
                        
                        DetailRow(
                            label: "Stop State",
                            value: block.stopState.capitalized,
                            icon: "stop.circle"
                        )
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Activity details (if any)
                    if block.switchCount > 0 || block.totalPauseDuration > 0 {
                        VStack(spacing: 12) {
                            if block.switchCount > 0 {
                                DetailRow(
                                    label: "Switches/Resumes",
                                    value: "\(block.switchCount)",
                                    icon: "arrow.triangle.2.circlepath"
                                )
                            }
                            
                            if block.totalPauseDuration > 0 {
                                DetailRow(
                                    label: "Total Paused",
                                    value: block.totalPauseDuration.formattedDuration,
                                    icon: "pause.circle"
                                )
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    }
                    
                    // Remarks
                    if !block.remarks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Remarks", systemImage: "note.text")
                                .font(.headline)
                            
                            Text(block.remarks)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                    }
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            showingEditSheet = true
                        } label: {
                            Label("Edit Record", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        
                        Button {
                            showingMergeSplitSheet = true
                        } label: {
                            Label("Merge / Split", systemImage: "arrow.left.arrow.right")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Record Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                RecordEditSheet(timeBlock: block)
            }
            .sheet(isPresented: $showingMergeSplitSheet) {
                MergeSplitSheet(timeBlock: block)
            }
        }
    }
}

// MARK: - Detail Row Helper

struct DetailRow: View {
    let label: String
    let value: String
    let icon: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Updated Filters View (removed date range)

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
