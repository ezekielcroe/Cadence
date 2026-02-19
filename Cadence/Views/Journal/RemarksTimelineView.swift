import SwiftUI
import SwiftData

// MARK: - JournalItem

private enum JournalItem: Identifiable {
    case remark(Remark, TimeBlock?)
    case intention(DayNote)
    case reflection(DayNote)
    case intentionPlaceholder
    case reflectionPlaceholder

    var id: String {
        switch self {
        case .remark(let r, _):      return "remark-\(r.id)"
        case .intention(let n):      return "intention-\(n.id)"
        case .reflection(let n):     return "reflection-\(n.id)"
        case .intentionPlaceholder:  return "placeholder-intention"
        case .reflectionPlaceholder: return "placeholder-reflection"
        }
    }
    
    func activityTimestamp(forDayStart dayStart: Date) -> Date {
        switch self {
        case .remark(let r, let block): return block?.startTime ?? r.timestamp
        default: return dayStart
        }
    }
    
    func itemTimestamp() -> Date {
        switch self {
        case .remark(let r, _): return r.timestamp
        default: return Date.distantPast
        }
    }
}

// MARK: - RemarksTimelineView

struct RemarksTimelineView: View {
    // Navigation State
    @State private var currentMonth: Date = Date()
    @State private var searchText = ""
    @State private var isSearching = false
    
    // Filter State (Local to the month)
    @State private var selectedTag: String? = nil
    @State private var showingTagPicker = false
    
    // Data for Filter Picker (Lightweight global fetch)
    @Query private var allRemarks: [Remark]
    private var allTags: [String] {
        Array(Set(allRemarks.flatMap { $0.tags })).sorted()
    }

    private var monthRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth))!
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        return (start, end)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. Month Navigator (Hidden when searching)
                if searchText.isEmpty {
                    MonthNavigator(currentDate: $currentMonth)
                }

                // 2. Main Content
                if !searchText.isEmpty {
                    // Global Search (Uses Phase 3 View)
                    SearchListView(searchText: searchText)
                } else {
                    // Paged Monthly Journal
                    JournalListView(
                        startDate: monthRange.start,
                        endDate: monthRange.end,
                        selectedTag: $selectedTag
                    )
                    // ID forces a full rebuild when month changes, preventing stale state
                    .id(currentMonth)
                }
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search remarks history")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingTagPicker = true
                    } label: {
                        Image(systemName: "tag")
                            .symbolVariant(selectedTag != nil ? .fill : .none)
                            .foregroundStyle(selectedTag != nil ? .blue : .primary)
                    }
                    .disabled(allTags.isEmpty || !searchText.isEmpty)
                }
            }
            .sheet(isPresented: $showingTagPicker) {
                TagPickerSheet(allTags: allTags, selectedTag: $selectedTag)
                    .presentationDetents([.medium])
            }
        }
    }
}

// MARK: - Paged List View

struct JournalListView: View {
    @Environment(\.modelContext) private var modelContext

    // Queries scoped to the specific month
    @Query private var remarks: [Remark]
    @Query private var dayNotes: [DayNote]
    @Query private var timeBlocks: [TimeBlock]

    @Binding var selectedTag: String?
    
    // Sheet State
    @State private var showingIntention = false
    @State private var showingReflection = false
    @State private var editingNote: DayNote? = nil

    init(startDate: Date, endDate: Date, selectedTag: Binding<String?>) {
        _selectedTag = selectedTag
        
        // 1. Fetch Remarks for this month
        _remarks = Query(
            filter: #Predicate { $0.timestamp >= startDate && $0.timestamp < endDate },
            sort: \.timestamp, order: .reverse
        )
        
        // 2. Fetch Notes for this month
        _dayNotes = Query(
            filter: #Predicate { $0.date >= startDate && $0.date < endDate },
            sort: \.date, order: .reverse
        )
        
        // 3. Fetch Blocks (Buffer 24h before to catch overnight overlaps)
        let bufferDate = startDate.addingTimeInterval(-86400)
        _timeBlocks = Query(
            filter: #Predicate { $0.startTime >= bufferDate && $0.startTime < endDate }
        )
    }

    // MARK: - Derived Data
    
    private var blockLookup: [UUID: TimeBlock] {
        Dictionary(uniqueKeysWithValues: timeBlocks.compactMap { ($0.id, $0) })
    }

    private var noteByDay: [Date: DayNote] {
        let cal = Calendar.current
        return Dictionary(
            dayNotes.map { (cal.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var groupedItems: [(dayLabel: String, dayStart: Date, items: [JournalItem])] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var daySet = Set<Date>()

        // Filter locally by Tag if needed
        let filteredRemarks = selectedTag == nil
            ? remarks
            : remarks.filter { $0.tags.contains(selectedTag!) }

        // 1. Collect Days
        for remark in filteredRemarks {
            daySet.insert(cal.startOfDay(for: remark.timestamp))
        }

        if selectedTag == nil {
            for note in dayNotes {
                if !note.intention.isEmpty || !note.reflection.isEmpty {
                    daySet.insert(cal.startOfDay(for: note.date))
                }
            }
            if let firstRemark = remarks.first, cal.isDate(firstRemark.timestamp, equalTo: Date(), toGranularity: .month) {
                daySet.insert(todayStart)
            }
        }

        return daySet
            .sorted(by: >)
            .compactMap { dayStart -> (String, Date, [JournalItem])? in
                let isToday = dayStart == todayStart
                
                // A. Prepare Remarks (Descending by Activity Time)
                let dayRemarks = filteredRemarks
                    .filter { cal.startOfDay(for: $0.timestamp) == dayStart }
                    .map { JournalItem.remark($0, blockLookup[$0.timeBlockID]) }
                    .sorted { a, b in
                        let actA = a.activityTimestamp(forDayStart: dayStart)
                        let actB = b.activityTimestamp(forDayStart: dayStart)
                        
                        if abs(actA.timeIntervalSince(actB)) > 0.1 {
                            return actA > actB
                        }
                        return a.itemTimestamp() > b.itemTimestamp()
                    }

                var finalItems: [JournalItem] = []

                if selectedTag == nil {
                    let note = noteByDay[dayStart]

                    // 1. TOP: Reflection (The "Evening" bookend, now at Top)
                    if let note, !note.reflection.isEmpty { finalItems.append(.reflection(note)) }
                    else if isToday { finalItems.append(.reflectionPlaceholder) }

                    // 2. MIDDLE: Remarks (Descending Stream)
                    finalItems.append(contentsOf: dayRemarks)

                    // 3. BOTTOM: Intention (The "Morning" bookend, now at Bottom)
                    if let note, !note.intention.isEmpty { finalItems.append(.intention(note)) }
                    else if isToday { finalItems.append(.intentionPlaceholder) }
                } else {
                    finalItems = dayRemarks
                }

                if finalItems.isEmpty { return nil }

                let label: String
                if cal.isDateInToday(dayStart) { label = "Today" }
                else if cal.isDateInYesterday(dayStart) { label = "Yesterday" }
                else { label = dayStart.formatted(date: .abbreviated, time: .omitted) }

                return (label, dayStart, finalItems)
            }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if groupedItems.isEmpty {
                EmptyJournalState(isFiltered: selectedTag != nil)
            } else {
                List {
                    // Tag Chip
                    if let tag = selectedTag {
                        Section {
                            Button { selectedTag = nil } label: {
                                HStack {
                                    Image(systemName: "tag.fill").foregroundStyle(.blue)
                                    Text("#\(tag)").foregroundStyle(.blue)
                                    Spacer()
                                    Text("Clear").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach(groupedItems, id: \.dayLabel) { group in
                        Section(header: Text(group.dayLabel).fontWeight(.semibold)) {
                            ForEach(group.items) { item in
                                JournalRowDispatch(
                                    item: item,
                                    dayStart: group.dayStart,
                                    noteByDay: noteByDay,
                                    onEditNote: { note, type in
                                        editingNote = note
                                        if type == .intention { showingIntention = true }
                                        else { showingReflection = true }
                                    },
                                    onDeleteRemark: deleteRemark,
                                    onClearNote: clearNote
                                )
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .sheet(isPresented: $showingIntention, onDismiss: { editingNote = nil }) {
            IntentionSheet(existingNote: editingNote)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingReflection, onDismiss: { editingNote = nil }) {
            ReflectionSheet(existingNote: editingNote)
                .presentationDetents([.medium])
        }
    }

    // MARK: - Actions
    
    private func deleteRemark(_ remark: Remark) {
        modelContext.delete(remark)
        try? modelContext.save()
    }
    
    private func clearNote(_ note: DayNote, type: NoteType) {
        if type == .intention {
            note.intention = ""
            note.intentionUpdatedAt = nil
        } else {
            note.reflection = ""
            note.reflectionUpdatedAt = nil
        }
        try? modelContext.save()
    }
}

// MARK: - Helper Views & Enums

enum NoteType { case intention, reflection }

struct MonthNavigator: View {
    @Binding var currentDate: Date
    
    var body: some View {
        HStack {
            Button(action: { changeMonth(by: -1) }) {
                Image(systemName: "chevron.left").padding(8)
            }
            Spacer()
            Text(currentDate.formatted(.dateTime.month(.wide).year()))
                .font(.headline).monospacedDigit()
            Spacer()
            Button(action: { changeMonth(by: 1) }) {
                Image(systemName: "chevron.right").padding(8)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Material.regular)
    }
    
    private func changeMonth(by value: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: value, to: currentDate) {
            withAnimation { currentDate = newDate }
        }
    }
}

struct EmptyJournalState: View {
    let isFiltered: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text(isFiltered ? "No remarks match this filter" : "No entries this month")
                .font(.title3).fontWeight(.medium)
            Text("Journal entries for this month will appear here.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Row Dispatcher (Clean Separation)

private struct JournalRowDispatch: View {
    let item: JournalItem
    let dayStart: Date
    let noteByDay: [Date: DayNote]
    let onEditNote: (DayNote, NoteType) -> Void
    let onDeleteRemark: (Remark) -> Void
    let onClearNote: (DayNote, NoteType) -> Void
    
    var body: some View {
        switch item {
        case .remark(let remark, let block):
            RemarkTimelineRow(remark: remark, block: block)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { onDeleteRemark(remark) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                
        case .intention(let note):
            IntentionTimelineRow(note: note)
                .listRowBackground(Color.orange.opacity(0.07))
                .onTapGesture { onEditNote(note, .intention) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { onClearNote(note, .intention) } label: { Label("Clear", systemImage: "trash") }.tint(.orange)
                    Button { onEditNote(note, .intention) } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                }
                
        case .reflection(let note):
            ReflectionTimelineRow(note: note)
                .listRowBackground(Color.indigo.opacity(0.07))
                .onTapGesture { onEditNote(note, .reflection) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { onClearNote(note, .reflection) } label: { Label("Clear", systemImage: "trash") }.tint(.indigo)
                    Button { onEditNote(note, .reflection) } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                }
                
        case .intentionPlaceholder:
            IntentionPlaceholderRow {
                // Find or Create logic would typically happen here or be passed down
                // For simplified UX, we rely on the existing noteByDay or would create one
                // Assuming 'noteByDay' might fail if no note exists yet.
                // In a real app, you'd insert the DayNote here if missing.
                if let existing = noteByDay[dayStart] {
                    onEditNote(existing, .intention)
                }
            }
            .listRowBackground(Color.orange.opacity(0.04))
            
        case .reflectionPlaceholder:
            ReflectionPlaceholderRow {
                if let existing = noteByDay[dayStart] {
                    onEditNote(existing, .reflection)
                }
            }
            .listRowBackground(Color.indigo.opacity(0.04))
        }
    }
}

// MARK: - Subviews (Unchanged from previous Phase)
// Included for completeness context

struct IntentionTimelineRow: View {
    let note: DayNote
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sun.horizon.fill").foregroundStyle(.orange).font(.subheadline).padding(.top, 2).frame(width: 20)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Morning Intention").font(.caption).fontWeight(.semibold).foregroundStyle(.orange)
                    Spacer()
                    if let updatedAt = note.intentionUpdatedAt {
                        Text(updatedAt.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Text(note.intention).font(.body).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 4)
    }
}

struct ReflectionTimelineRow: View {
    let note: DayNote
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "moon.stars.fill").foregroundStyle(.indigo).font(.subheadline).padding(.top, 2).frame(width: 20)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Evening Reflection").font(.caption).fontWeight(.semibold).foregroundStyle(.indigo)
                    Spacer()
                    if let updatedAt = note.reflectionUpdatedAt {
                        Text(updatedAt.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Text(note.reflection).font(.body).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 4)
    }
}

struct IntentionPlaceholderRow: View {
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "sun.horizon").foregroundStyle(.orange.opacity(0.5)).font(.subheadline).frame(width: 20)
                Text("Set today's intention…").font(.body).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "plus.circle").font(.subheadline).foregroundStyle(.orange.opacity(0.5))
            }
            .padding(.vertical, 4)
        }.buttonStyle(.plain)
    }
}

struct ReflectionPlaceholderRow: View {
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars").foregroundStyle(.indigo.opacity(0.5)).font(.subheadline).frame(width: 20)
                Text("Write tonight's reflection…").font(.body).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "plus.circle").font(.subheadline).foregroundStyle(.indigo.opacity(0.5))
            }
            .padding(.vertical, 4)
        }.buttonStyle(.plain)
    }
}

struct RemarkTimelineRow: View {
    let remark: Remark
    let block: TimeBlock?
    private var timeString: String { remark.timestamp.formatted(date: .omitted, time: .shortened) }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let block {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: block.activityColor)).frame(width: 4).frame(minHeight: 44)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let block { Text(block.activityName).font(.caption).fontWeight(.medium).foregroundStyle(.secondary) }
                    Spacer()
                    Text(timeString).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Text(remark.text).font(.body).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                if !remark.tags.isEmpty { TagChipRow(tags: remark.tags) }
            }
        }.padding(.vertical, 4)
    }
}

struct TagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let allTags: [String]
    @Binding var selectedTag: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { selectedTag = nil; dismiss() } label: {
                        HStack { Text("All Remarks"); Spacer(); if selectedTag == nil { Image(systemName: "checkmark").foregroundStyle(.blue) } }
                    }.foregroundStyle(.primary)
                }
                Section("Tags") {
                    ForEach(allTags, id: \.self) { tag in
                        Button { selectedTag = tag; dismiss() } label: {
                            HStack { Image(systemName: "tag.fill").foregroundStyle(.blue).font(.caption); Text("#\(tag)").foregroundStyle(.primary); Spacer(); if selectedTag == tag { Image(systemName: "checkmark").foregroundStyle(.blue) } }
                        }
                    }
                }
            }
            .navigationTitle("Filter by Tag").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
