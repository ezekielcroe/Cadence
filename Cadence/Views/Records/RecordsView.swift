//
//  RecordsView.swift
//  Cadence
//

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
    
    // Navigation / Sheets
    @State private var selectedBlock: TimeBlock?
    
    // Audit navigation
    @State private var timelineDate: Date?
    @State private var showingTimeline = false
    
    // Collapsed sections state
    @State private var collapsedSections: Set<String> = []
    
    // MARK: - Computed Properties
    
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
                FiltersView(selectedActivity: $selectedActivity, activities: uniqueActivities)
            }
            .sheet(isPresented: $showingTimeline) {
                TimelineSheetView(date: timelineDate ?? Date())
                    .onDisappear {
                        timelineDate = nil  // Clean up
                    }
            }

            .sheet(item: $selectedBlock) { block in
                RecordDetailView(block: block)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var recordsList: some View {
        List {
            // Collapsible date sections
            ForEach(groupedBlocks, id: \.section) { group in
                Section {
                    if !collapsedSections.contains(group.section.id) {
                        ForEach(group.blocks) { block in
                            Button {
                                selectedBlock = block
                            } label: {
                                RecordRowCompact(block: block)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    timelineDate = block.startTime
                                    showingTimeline = true
                                } label: {
                                    Label("Timeline", systemImage: "chart.bar.xaxis")
                                }
                                .tint(.purple)
                            }
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
    }
    
    private func sectionHeader(for section: DateSection, blocks: [TimeBlock]) -> some View {
        HStack {
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
                    Text(section.rawValue)
                        .font(.headline)
                    Image(systemName: collapsedSections.contains(section.id) ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Button {
                timelineDate = blocks.first?.startTime ?? Date()
                showingTimeline = true
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(.purple)
                    .padding(6)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
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
}

// MARK: - Record Row

struct RecordRowCompact: View {
    let block: TimeBlock
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(block.activityColor))
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 4) {
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
                    
                    Text("•").font(.caption2)
                    
                    Text(block.duration.formattedDuration)
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                
                if !block.remarks.isEmpty {
                    Text(block.remarks)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
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

// Helper view for TimelineSheet

struct TimelineSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let date: Date
    
    private var isEditable: Bool {
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        return date >= threeDaysAgo
    }
    
    var body: some View {
        NavigationStack {
            if isEditable {
                AuditListView(date: date)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
            } else {
                ReadOnlyTimelineView(date: date)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
            }
        }
    }
}

// MARK: - Read-Only Timeline View

struct ReadOnlyTimelineView: View {
    @Environment(\.modelContext) private var modelContext
    let date: Date
    
    @State private var blocks: [TimeBlock] = []
    
    private var sortedBlocks: [TimeBlock] {
        blocks.sorted { $0.startTime < $1.startTime }
    }
    
    private var totalTracked: TimeInterval {
        blocks.filter { !$0.isGap && !$0.isPauseBlock }
            .reduce(0) { $0 + $1.duration }
    }
    
    private var gaps: [TimeBlock] {
        blocks.filter { $0.isGap }
    }
    
    private var totalGapTime: TimeInterval {
        gaps.reduce(0) { $0 + $1.duration }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Info banner
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Read-Only Mode")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Timeline cannot be edited after 3 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            
            // Summary (same as AuditListView)
            DaySummaryBar(
                date: date,
                totalTracked: totalTracked,
                gapCount: gaps.count,
                totalGapTime: totalGapTime,
                onResolveAllGaps: { } // No-op in read-only mode
            )
            
            if blocks.isEmpty {
                ContentUnavailableView(
                    "No Activities",
                    systemImage: "clock",
                    description: Text("No time blocks recorded for this day")
                )
            } else {
                List {
                    ForEach(sortedBlocks) { block in
                        ReadOnlyBlockRow(block: block)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(date.formatted(date: .abbreviated, time: .omitted))
        .onAppear {
            loadBlocks()
        }
    }
    
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
}

// MARK: - Read-Only Block Row

struct ReadOnlyBlockRow: View {
    let block: TimeBlock
    
    private var timeRange: String {
        let start = block.startTime.formatted(date: .omitted, time: .shortened)
        if let end = block.endTime {
            let endStr = end.formatted(date: .omitted, time: .shortened)
            return "\(start) → \(endStr)"
        }
        return "\(start) → now"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Color indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(block.activityColor))
                .frame(width: 4, height: 44)
            
            // Main content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(block.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    if block.isGap {
                        GapBadge()
                    } else if block.isPauseBlock {
                        PauseBadge()
                    }
                    
                    Spacer()
                    
                    Text(block.duration.formattedDuration)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                
                HStack {
                    Text(timeRange)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    
                    if !block.remarks.isEmpty {
                        Text("•").font(.caption2)
                        Text(block.remarks.split(separator: "\n").first ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            // Lock icon (read-only)
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color.clear)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Activity.self, ActivitySet.self, TimeBlock.self, TimeBlockRule.self, configurations: config)
    
    return RecordsView()
        .modelContainer(container)
}
