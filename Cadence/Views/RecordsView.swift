//
//  RecordsView.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 29/1/26.
//


import SwiftUI
import SwiftData

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeBlock.startTime, order: .reverse) private var allTimeBlocks: [TimeBlock]
    
    @State private var searchText = ""
    @State private var selectedDateRange: DateRangeFilter = .all
    @State private var selectedActivity: String? = nil
    @State private var showingFilters = false
    
    enum DateRangeFilter: String, CaseIterable {
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "This Week"
        case lastWeek = "Last Week"
        case thisMonth = "This Month"
        case all = "All Time"
    }
    
    var filteredBlocks: [TimeBlock] {
        var blocks = allTimeBlocks
        
        // Filter by date range
        switch selectedDateRange {
        case .today:
            blocks = blocks.filter { Calendar.current.isDateInToday($0.startTime) }
        case .yesterday:
            blocks = blocks.filter { Calendar.current.isDateInYesterday($0.startTime) }
        case .thisWeek:
            blocks = blocks.filter { Calendar.current.isDate($0.startTime, equalTo: Date(), toGranularity: .weekOfYear) }
        case .lastWeek:
            let lastWeek = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date())!
            blocks = blocks.filter { Calendar.current.isDate($0.startTime, equalTo: lastWeek, toGranularity: .weekOfYear) }
        case .thisMonth:
            blocks = blocks.filter { Calendar.current.isDate($0.startTime, equalTo: Date(), toGranularity: .month) }
        case .all:
            break
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
    
    var groupedBlocks: [(date: Date, blocks: [TimeBlock])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredBlocks) { block in
            calendar.startOfDay(for: block.startTime)
        }
        return grouped.sorted { $0.key > $1.key }.map { (date: $0.key, blocks: $0.value.sorted { $0.startTime < $1.startTime }) }
    }
    
    var uniqueActivities: [String] {
        Array(Set(allTimeBlocks.map { $0.activityName })).sorted()
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredBlocks.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Records" : "No Results",
                        systemImage: searchText.isEmpty ? "tray" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Start tracking activities to see your records" : "Try adjusting your filters")
                    )
                } else {
                    List {
                        ForEach(groupedBlocks, id: \.date) { group in
                            Section {
                                ForEach(group.blocks) { block in
                                    NavigationLink {
                                        RecordEditView(timeBlock: block)
                                    } label: {
                                        RecordRow(block: block)
                                    }
                                }
                            } header: {
                                Text(formatSectionDate(group.date))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Records")
            .searchable(text: $searchText, prompt: "Search remarks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingFilters.toggle() }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FiltersView(
                    selectedDateRange: $selectedDateRange,
                    selectedActivity: $selectedActivity,
                    activities: uniqueActivities
                )
            }
        }
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Record Row
struct RecordRow: View {
    let block: TimeBlock
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color(hex: block.activityColor))
                    .frame(width: 10, height: 10)
                
                Text(block.activityName)
                    .font(.headline)
                
                Spacer()
                
                Text(block.duration.formattedDuration)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            
            HStack {
                Text(block.startTime, style: .time)
                Text("→")
                if let endTime = block.endTime {
                    Text(endTime, style: .time)
                } else {
                    Text("now")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            if !block.remarks.isEmpty {
                Text(block.remarks)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            if block.switchCount > 0 || block.totalPauseDuration > 0 {
                HStack(spacing: 12) {
                    if block.switchCount > 0 {
                        Label("\(block.switchCount)", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    
                    if block.totalPauseDuration > 0 {
                        Label(block.totalPauseDuration.formattedDuration, systemImage: "pause.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Record Edit View
struct RecordEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var timeBlock: TimeBlock
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        Form {
            Section("Activity") {
                HStack {
                    Circle()
                        .fill(Color(hex: timeBlock.activityColor))
                        .frame(width: 24, height: 24)
                    Text(timeBlock.activityName)
                        .font(.headline)
                }
            }
            
            Section("Time") {
                LabeledContent("Start") {
                    Text(timeBlock.startTime, format: .dateTime)
                        .foregroundStyle(.secondary)
                }
                
                if let endTime = timeBlock.endTime {
                    LabeledContent("End") {
                        Text(endTime, format: .dateTime)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("End") {
                        Text("Ongoing")
                            .foregroundStyle(.green)
                    }
                }
                
                LabeledContent("Duration") {
                    Text(timeBlock.duration.detailedFormattedDuration)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            
            if timeBlock.switchCount > 0 || timeBlock.totalPauseDuration > 0 {
                Section("Activity Details") {
                    if timeBlock.switchCount > 0 {
                        LabeledContent("Resumes") {
                            Text("\(timeBlock.switchCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if timeBlock.totalPauseDuration > 0 {
                        LabeledContent("Paused") {
                            Text(timeBlock.totalPauseDuration.formattedDuration)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Section {
                TextEditor(text: $timeBlock.remarks)
                    .frame(minHeight: 100)
            } header: {
                Text("Remarks")
            } footer: {
                Text("Add notes about this activity session")
            }
            
            Section {
                Button("Delete Record", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .navigationTitle("Edit Record")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    try? modelContext.save()
                    dismiss()
                }
            }
        }
        .alert("Delete Record?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelContext.delete(timeBlock)
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("This record will be permanently deleted.")
        }
    }
}

// MARK: - Filters View
struct FiltersView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedDateRange: RecordsView.DateRangeFilter
    @Binding var selectedActivity: String?
    let activities: [String]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    Picker("Range", selection: $selectedDateRange) {
                        ForEach(RecordsView.DateRangeFilter.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.inline)
                }
                
                Section("Activity") {
                    Picker("Filter by Activity", selection: $selectedActivity) {
                        Text("All Activities").tag(nil as String?)
                        ForEach(activities, id: \.self) { activity in
                            Text(activity).tag(activity as String?)
                        }
                    }
                    .pickerStyle(.inline)
                }
                
                Section {
                    Button("Reset Filters") {
                        selectedDateRange = .all
                        selectedActivity = nil
                    }
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
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Activity.self, ActivitySet.self, TimeBlock.self, TimeBlockRule.self, configurations: config)
    let context = container.mainContext
    
    // Create preview data
    let block1 = TimeBlock(
        activityID: UUID(),
        activityName: "Deep Work",
        activityColor: "#4CAF50",
        startTime: Date().addingTimeInterval(-3600)
    )
    block1.endTime = Date().addingTimeInterval(-1800)
    block1.remarks = "Worked on new feature"
    
    context.insert(block1)
    
    return RecordsView()
        .modelContainer(container)
}