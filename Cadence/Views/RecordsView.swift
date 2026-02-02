import SwiftUI
import SwiftData

// MARK: - Helper Wrapper for Timeline Sheet
struct TimelineSession: Identifiable {
    let id = UUID()
    let date: Date
}

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
    @State private var timelineSession: TimelineSession?
    
    // Collapsed sections state
    @State private var collapsedSections: Set<String> = []
    
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
                    List {
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
                                },
                                onOpenTimeline: { date in
                                    timelineSession = TimelineSession(date: date)
                                }
                            )
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
            .sheet(item: $timelineSession) { session in
                NavigationStack {
                    TimelineEditorView(date: session.date, modelContext: modelContext)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { timelineSession = nil }
                            }
                        }
                }
            }
            .sheet(item: $selectedBlock) { block in
                RecordDetailView(block: block)
            }
        }
    }
    
    var archivePromptView: some View {
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

// MARK: - Helper Types (Must be outside RecordsView)

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

struct CollapsibleSection: View {
    let section: DateSection
    let blocks: [TimeBlock]
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onSelectBlock: (TimeBlock) -> Void
    let onOpenTimeline: (Date) -> Void
    
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                           onOpenTimeline(block.startTime)
                        } label: {
                            Label("Timeline", systemImage: "chart.bar.xaxis")
                        }
                        .tint(.purple)
                    }
                }
            }
        } header: {
            HStack {
                Button {
                    onToggle()
                } label: {
                    HStack {
                        Image(systemName: section.icon)
                            .font(.subheadline)
                        Text(section.rawValue)
                            .font(.headline)
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button {
                    onOpenTimeline(blocks.first?.startTime ?? Date())
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(.blue)
                        .padding(6)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RecordRowCompact: View {
    let block: TimeBlock
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: block.activityColor))
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
