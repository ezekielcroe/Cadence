import SwiftUI
import SwiftData

struct RecordsView: View {
    @Environment(\.modelContext) private var modelContext

    // MARK: - Navigation State
    @State private var currentMonth: Date = Date()
    @State private var showArchived = false
    @State private var showingFilters = false
    @State private var showingAddBlock = false
    
    // MARK: - Filter State
    @State private var searchText = ""
    @State private var selectedActivity: String? = nil
    @State private var selectedTag: String? = nil
    
    // MARK: - Selection & Edit State
    @State private var isSelectionMode = false
    @State private var selectedBlockIDs: Set<UUID> = []
    @State private var selectedBlock: TimeBlock?
    @State private var conflictDetector: ConflictDetector?

    // Filter Helpers
    @Query private var allActivities: [Activity]
    @Query private var allRemarks: [Remark]

    private var allTags: [String] {
        Array(Set(allRemarks.flatMap { $0.tags })).sorted()
    }
    
    private var allActivityNames: [String] {
        allActivities.map { $0.name }.sorted()
    }

    // MARK: - Date Range Calculation
    private var monthRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth))!
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        return (start, end)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    
                    // 1. Month Navigator (Hide when searching)
                    if searchText.isEmpty {
                        HStack {
                            Button(action: { changeMonth(by: -1) }) {
                                Image(systemName: "chevron.left")
                                    .padding(8)
                            }
                            
                            Spacer()
                            
                            Text(currentMonth.formatted(.dateTime.month(.wide).year()))
                                .font(.headline)
                                .monospacedDigit()
                                .id(currentMonth)
                                .transition(.push(from: .top))
                            
                            Spacer()
                            
                            Button(action: { changeMonth(by: 1) }) {
                                Image(systemName: "chevron.right")
                                    .padding(8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Material.regular)
                        
                        // 2. Filter Banner
                        if selectedTag != nil || selectedActivity != nil {
                            HStack {
                                if let act = selectedActivity {
                                    Text("Activity: \(act)").font(.caption).bold()
                                }
                                if let tag = selectedTag {
                                    Text("Tag: #\(tag)").font(.caption).bold().foregroundStyle(.blue)
                                }
                                Spacer()
                                Button("Clear") {
                                    selectedActivity = nil
                                    selectedTag = nil
                                }
                                .font(.caption)
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                        }
                    }

                    // 3. Main Content Area (Conditional)
                    if !searchText.isEmpty {
                        // PHASE 3: Dedicated Search View
                        SearchListView(searchText: searchText)
                    } else {
                        // PHASE 1: Paged Timeline View
                        // Note: 'searchText' is removed from arguments here
                        TimelineListView(
                            startDate: monthRange.start,
                            endDate: monthRange.end,
                            selectedBlock: $selectedBlock,
                            isSelectionMode: $isSelectionMode,
                            selectedBlockIDs: $selectedBlockIDs,
                            selectedActivity: selectedActivity,
                            selectedTag: selectedTag,
                            showArchived: showArchived
                        )
                        .id(currentMonth)
                    }
                }

                // 4. Bulk Action Toolbar
                if isSelectionMode && searchText.isEmpty {
                    BulkActionToolbar(
                        count: selectedBlockIDs.count,
                        onMerge: mergeSelected,
                        onDelete: deleteSelected,
                        onCancel: {
                            isSelectionMode = false
                            selectedBlockIDs.removeAll()
                        }
                    )
                }
            }
            .navigationTitle("Records")
            .navigationBarTitleDisplayMode(.inline)
            // Searchable is bound to local state, triggering the view swap
            .searchable(text: $searchText, prompt: "Search remarks history")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if searchText.isEmpty {
                        Button(isSelectionMode ? "Done" : "Select") {
                            isSelectionMode.toggle()
                            selectedBlockIDs.removeAll()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddBlock = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Filter…") { showingFilters = true }
                        Divider()
                        Button("Today") { currentMonth = Date() }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .symbolVariant(selectedActivity != nil || selectedTag != nil ? .fill : .none)
                    }
                }
            }
            .sheet(item: $selectedBlock) { block in
                BlockEditSheet(
                    block: block,
                    conflictDetector: conflictDetector ?? ConflictDetector(modelContext: modelContext),
                    onSave: { try? modelContext.save() }
                )
            }
            .sheet(isPresented: $showingFilters) {
                FiltersView(
                    selectedActivity: $selectedActivity,
                    selectedTag: $selectedTag,
                    activities: allActivityNames,
                    allTags: allTags
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingAddBlock) {
                AddBlockSheet(
                    date: currentMonth,
                    conflictDetector: conflictDetector ?? ConflictDetector(modelContext: modelContext),
                    onSave: { try? modelContext.save() }
                )
            }
        }
        .onAppear {
            conflictDetector = ConflictDetector(modelContext: modelContext)
        }
    }

    // MARK: - Navigation Actions
    private func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: currentMonth) {
            withAnimation {
                currentMonth = newDate
            }
        }
    }
    
    // MARK: - Bulk Actions
    private func deleteSelected() {
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { selectedBlockIDs.contains($0.id) }
        )
        if let toDelete = try? modelContext.fetch(descriptor) {
             let ids = Set(toDelete.map { $0.id })
             // Note: In a production app, use Cascade delete rules in Model definition
             let remarkDesc = FetchDescriptor<Remark>(predicate: #Predicate { ids.contains($0.timeBlockID) })
             if let remarks = try? modelContext.fetch(remarkDesc) {
                 for r in remarks { modelContext.delete(r) }
             }
             
             for block in toDelete { modelContext.delete(block) }
             try? modelContext.save()
        }
        isSelectionMode = false
        selectedBlockIDs.removeAll()
    }
    
    private func mergeSelected() {
        let editor = TimeBlockEditor(modelContext: modelContext)
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { selectedBlockIDs.contains($0.id) },
            sortBy: [SortDescriptor(\.startTime)]
        )
        
        guard let blocksToMerge = try? modelContext.fetch(descriptor),
              let firstBlock = blocksToMerge.first,
              let activityID = firstBlock.activityID else { return }

        let actDesc = FetchDescriptor<Activity>(predicate: #Predicate { $0.id == activityID })
        guard let targetActivity = try? modelContext.fetch(actDesc).first else { return }

        try? editor.mergeBlocks(blocksToMerge, intoActivity: targetActivity)
        isSelectionMode = false
        selectedBlockIDs.removeAll()
    }
}
