// TimelineListView.swift
// Cadence
//
// REDESIGN v2: Bullet journal day pages.
//
// Each day reads top-to-bottom as a single continuous page:
//   ☀️ Intention
//   8:30  ■ Activity          45m
//         › remark text       #tag
//   9:15  ┊ 15m untracked    [fill]
//   9:30  ■ Activity        2h 15m
//         › remark            #tag
//   → now
//   🌙 Reflection
//
// Key changes from original:
// - Reverse Chronological order (Latest first)
// - Remarks are ALWAYS visible inline, not hidden behind badges
// - Gaps are quiet dashed spacers, not angry orange alerts
// - Intention/reflection bookends are integrated, not on a separate tab
// - One-tap gap fill with recent activity chips (no GapResolverSheet)
// - Minimal state: no gap overview mode, no visual timeline toggle
// - List separators removed for continuous flow

import SwiftUI
import SwiftData

struct TimelineListView: View {
    @Environment(\.modelContext) private var modelContext

    // Queries
    @Query private var blocks: [TimeBlock]
    @Query private var remarks: [Remark]
    @Query private var schedules: [TimeBlockRule]
    @Query private var dayNotes: [DayNote]
    @Query private var allActivities: [Activity]

    // Parent bindings
    @Binding var selectedBlock: TimeBlock?
    @Binding var isSelectionMode: Bool
    @Binding var selectedBlockIDs: Set<UUID>

    let selectedActivity: String?
    let selectedTag: String?
    let showArchived: Bool
    let gapOverviewMode: Bool // FIX: Now captured locally

    // Undo support & Gap routing
    var onDeleteBlock: ((TimeBlock) -> Void)?
    var onFillGap: ((ComputedGap) -> Void)?

    // Local state
    @State private var inlineRemarkBlockID: UUID?
    @State private var inlineRemarkText = ""
    @State private var editingNoteType: NoteEditType?
    @FocusState private var remarkFieldFocused: Bool
    
    // Interaction state
    @State private var expandedActivityIDs: Set<UUID> = []
    @State private var collapsedDayDates: Set<Date> = []

    enum NoteEditType: Identifiable {
        case intention(Date), reflection(Date)
        var id: String {
            switch self {
            case .intention(let d): return "i-\(d.timeIntervalSince1970)"
            case .reflection(let d): return "r-\(d.timeIntervalSince1970)"
            }
        }
    }

    init(
        startDate: Date,
        endDate: Date,
        selectedBlock: Binding<TimeBlock?>,
        isSelectionMode: Binding<Bool>,
        selectedBlockIDs: Binding<Set<UUID>>,
        selectedActivity: String?,
        selectedTag: String?,
        showArchived: Bool,
        gapOverviewMode: Bool = false,
        onDeleteBlock: ((TimeBlock) -> Void)? = nil,
        onFillGap: ((ComputedGap) -> Void)? = nil
    ) {
        _selectedBlock = selectedBlock
        _isSelectionMode = isSelectionMode
        _selectedBlockIDs = selectedBlockIDs
        self.selectedActivity = selectedActivity
        self.selectedTag = selectedTag
        self.showArchived = showArchived
        self.gapOverviewMode = gapOverviewMode
        self.onDeleteBlock = onDeleteBlock
        self.onFillGap = onFillGap

        _blocks = Query(
            filter: #Predicate { block in
                block.startTime >= startDate && block.startTime < endDate && block.activityID != nil
            },
            sort: \.startTime,
            order: .reverse
        )

        _dayNotes = Query(
            filter: #Predicate { $0.date >= startDate && $0.date < endDate },
            sort: \.date, order: .reverse
        )
    }

    private var remarksByBlock: [UUID: [Remark]] {
        let ids = Set(blocks.map { $0.id })
        return Dictionary(grouping: remarks.filter { ids.contains($0.timeBlockID) }) { $0.timeBlockID }
    }

    private var filteredBlocks: [TimeBlock] {
        var result = blocks
        if let act = selectedActivity { result = result.filter { $0.activityName == act } }
        if let tag = selectedTag {
            let ids = Set(remarks.filter { $0.tags.contains(tag) }.map { $0.timeBlockID })
            result = result.filter { ids.contains($0.id) }
        }
        return result
    }

    private var noteByDay: [Date: DayNote] {
        Dictionary(dayNotes.map { (Calendar.current.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var dayPages: [(label: String, date: Date, items: [TimelineItem])] {
        let cal = Calendar.current
        let noFilters = selectedActivity == nil && selectedTag == nil
        let todayStart = cal.startOfDay(for: Date())

        let grouped = Dictionary(grouping: filteredBlocks) { cal.startOfDay(for: $0.startTime) }

        var allDays = Set(grouped.keys)
        if let first = blocks.first, cal.isDate(todayStart, equalTo: first.startTime, toGranularity: .month) {
            allDays.insert(todayStart)
        }

        return allDays.sorted(by: >).compactMap { dayStart -> (String, Date, [TimelineItem])? in
            let dayBlocks = (grouped[dayStart] ?? []).sorted { $0.startTime < $1.startTime }
            let isToday = cal.isDateInToday(dayStart)

            var gaps: [ComputedGap] = []
            if noFilters && !dayBlocks.isEmpty {
                let dayEnd: Date = {
                    let calEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
                    let latestEnd = dayBlocks.compactMap { $0.endTime }.max() ?? calEnd
                    return isToday ? min(Date(), max(calEnd, latestEnd)) : max(calEnd, latestEnd)
                }()
                let effStart = overnightCoverageEnd(before: dayStart) ?? dayStart
                gaps = GapCalculator.computeGaps(in: dayBlocks, rules: schedules, from: effStart, to: dayEnd)
            }

            var items: [TimelineItem] = dayBlocks.map { .activity($0) }
            gaps.forEach { items.append(.gap($0)) }
            items.sort { $0.startTime > $1.startTime }

            // FIX: Enforce gap overview filter
            if gapOverviewMode {
                items = items.filter { if case .gap = $0 { return true } else { return false } }
            }

            if items.isEmpty && noteByDay[dayStart] == nil { return nil }

            let label: String = {
                if cal.isDateInToday(dayStart) { return "Today" }
                if cal.isDateInYesterday(dayStart) { return "Yesterday" }
                return dayStart.formatted(date: .abbreviated, time: .omitted)
            }()

            return (label, dayStart, items)
        }
    }

    var body: some View {
        List {
            if isSelectionMode {
                selectionBar
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }

            ForEach(dayPages, id: \.date) { page in
                Section {
                    if !collapsedDayDates.contains(page.date) {
                        dayPage(page.label, date: page.date, items: page.items)
                    }
                } header: {
                    dayHeader(page.label, date: page.date, items: page.items, isCollapsed: collapsedDayDates.contains(page.date))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // FIX: Added explicit smoothing animation for collapse
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if collapsedDayDates.contains(page.date) {
                                    collapsedDayDates.remove(page.date)
                                } else {
                                    collapsedDayDates.insert(page.date)
                                }
                            }
                        }
                }
            }

            if dayPages.isEmpty { emptyState }
        }
        .listStyle(.plain)
        .sheet(item: $editingNoteType) { type in
            switch type {
            case .intention(let d):
                IntentionSheet(existingNote: noteByDay[Calendar.current.startOfDay(for: d)])
                    .presentationDetents([.medium])
            case .reflection(let d):
                ReflectionSheet(existingNote: noteByDay[Calendar.current.startOfDay(for: d)])
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Day Header
    private func dayHeader(_ label: String, date: Date, items: [TimelineItem], isCollapsed: Bool) -> some View {
        let tracked = items.compactMap { if case .activity(let b) = $0 { return b.duration } else { return nil } }
            .reduce(0.0, +)
        let gapCount = items.filter { if case .gap = $0 { return true }; return false }.count

        return HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.title3).fontWeight(.bold).foregroundStyle(.primary)
            
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.caption).foregroundStyle(.tertiary)
            
            Spacer()
            if tracked > 0 {
                Text(tracked.formattedDuration)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if gapCount > 0 {
                Text("· \(gapCount) gap\(gapCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.orange.opacity(0.7))
            }
        }
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 4, trailing: 16))
    }

    // MARK: - Day Page
    @ViewBuilder
    private func dayPage(_ label: String, date: Date, items: [TimelineItem]) -> some View {
        let dayStart = Calendar.current.startOfDay(for: date)
        let isToday = Calendar.current.isDateInToday(date)
        let note = noteByDay[dayStart]

        if let note, !note.reflection.isEmpty {
            bookendRow(
                icon: "moon.stars.fill", tint: .indigo, label: "Reflection",
                text: note.reflection, time: note.reflectionUpdatedAt
            )
            .onTapGesture { editingNoteType = .reflection(dayStart) }
            .listRowBackground(Color.indigo.opacity(0.03))
        } else if isToday {
            bookendPlaceholder(icon: "moon.stars", tint: .indigo, text: "Write tonight's reflection…")
                .onTapGesture { editingNoteType = .reflection(dayStart) }
        }

        ForEach(items) { item in
            switch item {
            case .activity(let block): activityEntry(block)
            case .gap(let gap): gapSpacer(gap)
            }
        }

        if items.isEmpty {
            HStack {
                Spacer()
                Text("No entries").font(.caption).foregroundStyle(.quaternary)
                Spacer()
            }
            .padding(.vertical, 16).listRowSeparator(.hidden)
        }
        
        if let note, !note.intention.isEmpty {
            bookendRow(
                icon: "sun.horizon.fill", tint: .orange, label: "Intention",
                text: note.intention, time: note.intentionUpdatedAt
            )
            .onTapGesture { editingNoteType = .intention(dayStart) }
            .listRowBackground(Color.orange.opacity(0.03))
        } else if isToday {
            bookendPlaceholder(icon: "sun.horizon", tint: .orange, text: "Set today's intention…")
                .onTapGesture { editingNoteType = .intention(dayStart) }
        }
    }

    // MARK: - Activity Entry
    private func activityEntry(_ block: TimeBlock) -> some View {
        let blockRemarks = (remarksByBlock[block.id] ?? []).sorted { $0.timestamp < $1.timestamp }
        let showingRemarkField = inlineRemarkBlockID == block.id
        let isExpanded = expandedActivityIDs.contains(block.id)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                timeGutter(block.startTime)

                colorBar(hex: block.activityColor)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        if isSelectionMode {
                            Image(systemName: selectedBlockIDs.contains(block.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedBlockIDs.contains(block.id) ? AnyShapeStyle(.blue) : AnyShapeStyle(.tertiary))
                                .font(.caption)
                        }

                        Text(block.activityName)
                            .font(.subheadline).fontWeight(.medium)
                        
                        if !blockRemarks.isEmpty {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2).foregroundStyle(.tertiary)
                                .padding(.leading, 2)
                        }
                        
                        Spacer()
                        Text(block.duration.formattedDuration)
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }

                    if isExpanded {
                        ForEach(blockRemarks) { remark in
                            remarkBullet(remark)
                        }
                    }
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            // FIX: Double-tap support to trigger inline remark field
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.15)) {
                    inlineRemarkBlockID = block.id; inlineRemarkText = ""
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { remarkFieldFocused = true }
            }
            // Standard single tap
            .onTapGesture(count: 1) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedActivityIDs.contains(block.id) {
                        expandedActivityIDs.remove(block.id)
                    } else {
                        expandedActivityIDs.insert(block.id)
                    }
                }
            }
            .onLongPressGesture {
                if !isSelectionMode { isSelectionMode = true; selectedBlockIDs.removeAll() }
                selectedBlockIDs.insert(block.id)
            }

            if showingRemarkField {
                quickRemarkField(for: block)
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
        .swipeActions(edge: .leading) {
            Button {
                selectedBlock = block
            } label: { Label("Edit", systemImage: "pencil") }
            .tint(.orange)
            
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    inlineRemarkBlockID = block.id; inlineRemarkText = ""
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { remarkFieldFocused = true }
            } label: { Label("Note", systemImage: "note.text.badge.plus") }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { onDeleteBlock?(block); deleteBlock(block) }
            label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func remarkBullet(_ remark: Remark) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text("›")
                .font(.subheadline).fontWeight(.light)
                .foregroundStyle(.tertiary)
                .padding(.top, 1)

            Text(remark.displayText)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if !remark.tags.isEmpty {
                HStack(spacing: 3) {
                    ForEach(remark.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.7))
                    }
                }
            }
        }
        .padding(.vertical, 1)
    }

    private func quickRemarkField(for block: TimeBlock) -> some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 52)
            Rectangle().fill(.clear).frame(width: 3)
                .padding(.horizontal, 8)

            HStack(spacing: 6) {
                TextField("Add a note… #tags", text: $inlineRemarkText, axis: .vertical)
                    .font(.subheadline)
                    .focused($remarkFieldFocused)
                    .lineLimit(1...3)
                    .submitLabel(.done)
                    .onSubmit { saveRemark(for: block) }

                if !inlineRemarkText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { saveRemark(for: block) } label: {
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.blue)
                    }.buttonStyle(.plain)
                }

                Button {
                    withAnimation { inlineRemarkBlockID = nil; inlineRemarkText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary).font(.caption)
                }.buttonStyle(.plain)
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding(.bottom, 4)
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        .listRowSeparator(.hidden)
    }

    // MARK: - Gap Spacer
    // FIX: Simplified entirely to just trigger the 'Create new timeblock' bridge
    private func gapSpacer(_ gap: ComputedGap) -> some View {
        HStack(spacing: 0) {
            timeGutter(gap.start, muted: true)
            dashedBar()

            HStack(spacing: 5) {
                Text(gap.duration.formattedDuration)
                    .font(.caption).foregroundStyle(.secondary.opacity(0.5)).monospacedDigit()
                Text("untracked")
                    .font(.caption).foregroundStyle(.quaternary)
                Spacer()
                
                Button {
                    onFillGap?(gap)
                } label: {
                    Text("fill")
                        .font(.caption)
                        .foregroundStyle(AnyShapeStyle(.orange))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onFillGap?(gap)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
    }

    // MARK: - Bookend Rows
    private func bookendRow(icon: String, tint: Color, label: String, text: String, time: Date?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if let time {
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    .frame(width: 52, alignment: .trailing).padding(.top, 2)
            } else {
                Spacer().frame(width: 52)
            }

            Image(systemName: icon)
                .foregroundStyle(tint.opacity(0.6))
                .font(.caption2)
                .frame(width: 19).padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundStyle(tint.opacity(0.7))
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 5)
        .listRowSeparator(.hidden)
    }

    private func bookendPlaceholder(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 52)
            Image(systemName: icon)
                .foregroundStyle(tint.opacity(0.25)).font(.caption2).frame(width: 19)
            Text(text).font(.subheadline).foregroundStyle(.quaternary)
            Spacer()
        }
        .padding(.vertical, 3)
        .listRowSeparator(.hidden)
        .contentShape(Rectangle())
    }

    private func timeGutter(_ date: Date, muted: Bool = false) -> some View {
        Text(date.formatted(date: .omitted, time: .shortened))
            .font(.caption).monospacedDigit()
            .foregroundStyle(muted ? .quaternary : .secondary)
            .frame(width: 52, alignment: .trailing)
            .padding(.top, 2)
    }

    private func colorBar(hex: String) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color(hex: hex))
            .frame(width: 3)
            .padding(.horizontal, 8)
    }

    private func dashedBar() -> some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(.secondary.opacity(0.2))
            .frame(width: 1)
            .padding(.horizontal, 9)
    }

    private var selectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton("All Today", icon: "calendar") {
                    selectedBlockIDs.formUnion(
                        blocks.filter { Calendar.current.isDateInToday($0.startTime) }.map { $0.id }
                    )
                }
                if let id = selectedBlockIDs.first, let b = blocks.first(where: { $0.id == id }) {
                    chipButton("All \(b.activityName)", icon: "square.stack") {
                        selectedBlockIDs.formUnion(
                            blocks.filter { $0.activityName == b.activityName }.map { $0.id }
                        )
                    }
                }
                chipButton("Clear", icon: "xmark") { selectedBlockIDs.removeAll() }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(Color.blue.opacity(0.04))
    }

    private func chipButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(.systemGray6)).cornerRadius(14)
        }.buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 32)).foregroundStyle(.quaternary)
            Text("Nothing logged yet")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Start from the Timer tab")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48).listRowSeparator(.hidden)
    }

    private func saveRemark(for block: TimeBlock) {
        let text = inlineRemarkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        modelContext.insert(Remark(timeBlockID: block.id, text: text))
        try? modelContext.save()
        expandedActivityIDs.insert(block.id)
        withAnimation { inlineRemarkBlockID = nil; inlineRemarkText = "" }
    }

    private func deleteBlock(_ block: TimeBlock) {
        let date = block.startTime
        for r in remarks where r.timeBlockID == block.id { modelContext.delete(r) }
        modelContext.delete(block)
        try? modelContext.save()
        HistoryManager.shared.invalidateDate(date, in: modelContext)
    }

    private func overnightCoverageEnd(before dayStart: Date) -> Date? {
        let prev = Calendar.current.date(byAdding: .day, value: -1, to: dayStart)!
        let desc = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.startTime >= prev && $0.startTime < dayStart && $0.activityID != nil }
        )
        return (try? modelContext.fetch(desc))?.compactMap { $0.endTime }.filter { $0 > dayStart }.max()
    }
}
