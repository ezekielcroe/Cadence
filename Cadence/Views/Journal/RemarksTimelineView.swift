// RemarksTimelineView.swift
// Cadence
//


import SwiftUI
import SwiftData

// MARK: - Week Bucket

/// Groups day-level remark data into a calendar week for collapsible display.
private struct WeekBucket: Identifiable {
    let id: String                  // e.g. "2026-W09"
    let weekStart: Date
    let weekEnd: Date
    let days: [DayBucket]
    let isCurrentWeek: Bool

    var remarkCount: Int { days.reduce(0) { $0 + $1.remarks.count } }
    var noteCount: Int { days.filter { $0.note != nil }.count }
    var topTags: [String] {
        let all = days.flatMap { $0.remarks.flatMap { $0.tags } }
        let counts = Dictionary(all.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
    }

    var dateRangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let start = fmt.string(from: weekStart)
        fmt.dateFormat = "d"
        let end = fmt.string(from: weekEnd)
        return "\(start)–\(end)"
    }
}

private struct DayBucket: Identifiable {
    let id: Date      // startOfDay
    let label: String
    let remarks: [Remark]
    let note: DayNote?
}

// MARK: - RemarksTimelineView

struct RemarksTimelineView: View {
    @Environment(\.modelContext) private var modelContext

    // Navigation & filter state
    @State private var currentMonth: Date = Date()
    @State private var searchText = ""
    @State private var selectedTag: String? = nil
    @State private var expandedWeekIDs: Set<String> = []

    // Data
    @Query(sort: \Remark.timestamp, order: .reverse) private var allRemarks: [Remark]
    @Query(sort: \DayNote.date, order: .reverse) private var allNotes: [DayNote]
    @Query private var allBlocks: [TimeBlock]

    @State private var cachedTags: [String] = []

    private var allTags: [String] { cachedTags }

    private var isViewingCurrentMonth: Bool {
        Calendar.current.isDate(currentMonth, equalTo: Date(), toGranularity: .month)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Month navigator (hidden during search)
                if searchText.isEmpty {
                    monthNavigator
                }

                // Tag chip bar
                if searchText.isEmpty && !allTags.isEmpty {
                    tagBar
                }

                // Content
                if !searchText.isEmpty {
                    SearchListView(searchText: searchText)
                } else {
                    weekGroupedList
                }
            }
            .navigationTitle("Remarks")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search all remarks…")
            .onChange(of: currentMonth) { _, _ in resetExpansion() }
        }
    }

    // MARK: - Month Navigator

    private var monthNavigator: some View {
        HStack {
            Button { changeMonth(by: -1) } label: {
                Image(systemName: "chevron.left").padding(8)
            }

            Spacer()

            if isViewingCurrentMonth {
                Text(currentMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .monospacedDigit()
                    .id(currentMonth)
                    .transition(.push(from: .top))
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { currentMonth = Date() }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentMonth.formatted(.dateTime.month(.abbreviated).year()))
                            .font(.headline)
                            .monospacedDigit()

                        Divider().frame(height: 16)

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward").font(.caption)
                            Text("Today").font(.subheadline).fontWeight(.semibold)
                        }
                        .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button { changeMonth(by: 1) } label: {
                Image(systemName: "chevron.right").padding(8)
            }
            .disabled(isViewingCurrentMonth)
            .opacity(isViewingCurrentMonth ? 0.3 : 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.systemGroupedBackground))
    }

    private func changeMonth(by value: Int) {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentMonth = Calendar.current.date(byAdding: .month, value: value, to: currentMonth) ?? currentMonth
        }
    }

    // MARK: - Tag Bar

    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tagChip(label: "All", isSelected: selectedTag == nil) {
                    withAnimation { selectedTag = nil }
                }
                ForEach(allTags, id: \.self) { tag in
                    tagChip(label: "#\(tag)", isSelected: selectedTag == tag) {
                        withAnimation { selectedTag = selectedTag == tag ? nil : tag }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func tagChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption).fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.blue.opacity(0.15) : Color(.systemGray5))
                .foregroundStyle(isSelected ? .blue : .secondary)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
    
    private func recomputeTags() {
        let tags = Array(Set(allRemarks.flatMap { $0.tags })).sorted()
        if tags != cachedTags { cachedTags = tags }
    }

    // MARK: - Data Pipeline

    private var blockLookup: [UUID: TimeBlock] {
        Dictionary(uniqueKeysWithValues: allBlocks.compactMap { ($0.id, $0) })
    }

    /// Remarks filtered by tag, then scoped to the selected month.
    private var monthRemarks: [Remark] {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth))!
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart)!

        let tagFiltered: [Remark]
        if let tag = selectedTag {
            tagFiltered = allRemarks.filter { $0.tags.contains(tag) }
        } else {
            tagFiltered = Array(allRemarks)
        }

        return tagFiltered.filter { $0.timestamp >= monthStart && $0.timestamp < monthEnd }
    }

    /// Notes scoped to the selected month.
    private var monthNotes: [DayNote] {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: currentMonth))!
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart)!
        return allNotes.filter { $0.date >= monthStart && $0.date < monthEnd }
    }

    /// Build week buckets from month-scoped data.
    private var weekBuckets: [WeekBucket] {
        let cal = Calendar.current
        let lookup = blockLookup

        let notesByDay = Dictionary(
            monthNotes.map { (cal.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { a, _ in a }
        )

        // Group remarks by day
        let remarksByDay = Dictionary(grouping: monthRemarks) { cal.startOfDay(for: $0.timestamp) }

        // Collect all relevant days (remarks + non-empty notes)
        var allDays = Set(remarksByDay.keys)
        if selectedTag == nil {
            for note in monthNotes where !note.intention.isEmpty || !note.reflection.isEmpty {
                allDays.insert(cal.startOfDay(for: note.date))
            }
        }

        // Build day buckets
        let dayBuckets: [DayBucket] = allDays.sorted(by: >).compactMap { dayStart in
            let rawRemarks = remarksByDay[dayStart] ?? []

            let dayRemarks = rawRemarks.sorted { a, b in
                let blockA = lookup[a.timeBlockID]
                let blockB = lookup[b.timeBlockID]
                let actA = blockA?.startTime ?? a.timestamp
                let actB = blockB?.startTime ?? b.timestamp
                if abs(actA.timeIntervalSince(actB)) > 0.1 { return actA > actB }
                return a.timestamp > b.timestamp
            }

            let note = notesByDay[dayStart]

            if selectedTag != nil && dayRemarks.isEmpty { return nil }
            if dayRemarks.isEmpty && (note == nil || (note!.intention.isEmpty && note!.reflection.isEmpty)) { return nil }

            let label: String
            if cal.isDateInToday(dayStart) { label = "Today" }
            else if cal.isDateInYesterday(dayStart) { label = "Yesterday" }
            else { label = dayStart.formatted(date: .abbreviated, time: .omitted) }

            return DayBucket(id: dayStart, label: label, remarks: dayRemarks, note: note)
        }

        // Group day buckets by calendar week
        let byWeek = Dictionary(grouping: dayBuckets) { day -> Int in
            cal.component(.weekOfYear, from: day.id)
        }

        let year = cal.component(.year, from: currentMonth)
        let currentWeekOfYear = cal.component(.weekOfYear, from: Date())
        let currentYear = cal.component(.year, from: Date())

        return byWeek.keys.sorted(by: >).map { weekNum in
            let days = byWeek[weekNum]!.sorted { $0.id > $1.id }

            // Compute the Monday (or locale week start) of this week
            var weekStartComps = DateComponents()
            weekStartComps.yearForWeekOfYear = year
            weekStartComps.weekOfYear = weekNum
            weekStartComps.weekday = cal.firstWeekday
            let weekStart = cal.date(from: weekStartComps) ?? days.last!.id
            let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? days.first!.id

            let isCurrent = (weekNum == currentWeekOfYear && year == currentYear)

            let weekID = "\(year)-W\(String(format: "%02d", weekNum))"

            return WeekBucket(
                id: weekID,
                weekStart: weekStart,
                weekEnd: weekEnd,
                days: days,
                isCurrentWeek: isCurrent
            )
        }
    }

    // MARK: - Expansion Logic

    private func isWeekExpanded(_ week: WeekBucket) -> Bool {
        // Current week is always expanded by default; others need explicit expansion
        if week.isCurrentWeek && !expandedWeekIDs.contains("collapsed-\(week.id)") {
            return true
        }
        return expandedWeekIDs.contains(week.id)
    }

    private func toggleWeek(_ week: WeekBucket) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if week.isCurrentWeek {
                // For current week, use a "collapsed" marker to override the default-expanded
                if expandedWeekIDs.contains("collapsed-\(week.id)") {
                    expandedWeekIDs.remove("collapsed-\(week.id)")
                } else {
                    expandedWeekIDs.insert("collapsed-\(week.id)")
                }
            } else {
                if expandedWeekIDs.contains(week.id) {
                    expandedWeekIDs.remove(week.id)
                } else {
                    expandedWeekIDs.insert(week.id)
                }
            }
        }
    }

    private func resetExpansion() {
        expandedWeekIDs.removeAll()
    }

    // MARK: - Week-Grouped List

    @ViewBuilder
    private var weekGroupedList: some View {
        let buckets = weekBuckets

        if buckets.isEmpty {
            emptyState
        } else {
            List {
                ForEach(buckets) { week in
                    Section {
                        if isWeekExpanded(week) {
                            // Expanded: show all day sections inline
                            ForEach(week.days) { day in
                                dayHeader(day)
                                dayContent(day)
                            }
                        } else {
                            // Collapsed: summary row
                            collapsedWeekRow(week)
                        }
                    } header: {
                        weekSectionHeader(week)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Week Section Header

    private func weekSectionHeader(_ week: WeekBucket) -> some View {
        Button { toggleWeek(week) } label: {
            HStack {
                if week.isCurrentWeek {
                    Text("This Week")
                        .fontWeight(.semibold)
                } else {
                    Text(week.dateRangeLabel)
                        .fontWeight(.semibold)
                }

                Spacer()

                if !isWeekExpanded(week) {
                    Text("\(week.remarkCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }

                Image(systemName: isWeekExpanded(week) ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }

    // MARK: - Collapsed Week Row

    private func collapsedWeekRow(_ week: WeekBucket) -> some View {
        Button { toggleWeek(week) } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Summary line
                HStack(spacing: 12) {
                    Label("\(week.remarkCount) remark\(week.remarkCount == 1 ? "" : "s")",
                          systemImage: "text.quote")
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    if week.noteCount > 0 {
                        Label("\(week.noteCount) note\(week.noteCount == 1 ? "" : "s")",
                              systemImage: "sun.horizon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                // Top tags preview
                if !week.topTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(week.topTags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundStyle(.blue.opacity(0.7))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.08))
                                .cornerRadius(4)
                        }
                    }
                }

                // Day preview: show first remark text from each day (max 2 days)
                let previewDays = week.days.prefix(2)
                ForEach(previewDays) { day in
                    if let firstRemark = day.remarks.first {
                        HStack(spacing: 6) {
                            if let block = blockLookup[firstRemark.timeBlockID] {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color(hex: block.activityColor))
                                    .frame(width: 2, height: 14)
                            }
                            Text(firstRemark.preview)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                // "Tap to expand" hint
                Text("Tap to expand")
                    .font(.caption2)
                    .foregroundStyle(.blue.opacity(0.6))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day Header (within expanded week)

    private func dayHeader(_ day: DayBucket) -> some View {
        HStack {
            Text(day.label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(day.remarks.count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 6)
        .listRowSeparator(.hidden, edges: .bottom)
    }

    // MARK: - Day Content (within expanded week)

    @ViewBuilder
    private func dayContent(_ day: DayBucket) -> some View {
        // Reflection
        if selectedTag == nil, let note = day.note, !note.reflection.isEmpty {
            compactBookend(icon: "moon.stars.fill", tint: .indigo,
                           label: "Reflection", text: note.reflection)
        }

        // Remarks
        ForEach(day.remarks) { remark in
            remarkRow(remark)
        }
        .onDelete { offsets in
            for i in offsets { modelContext.delete(day.remarks[i]) }
            try? modelContext.save()
        }

        // Intention
        if selectedTag == nil, let note = day.note, !note.intention.isEmpty {
            compactBookend(icon: "sun.horizon.fill", tint: .orange,
                           label: "Intention", text: note.intention)
        }
    }

    // MARK: - Remark Row

    private func remarkRow(_ remark: Remark) -> some View {
        let block = blockLookup[remark.timeBlockID]

        return HStack(alignment: .top, spacing: 10) {
            if let block {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(hex: block.activityColor))
                    .frame(width: 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    if let block {
                        Text(block.activityName)
                            .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(remark.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }

                Text(remark.displayText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !remark.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(remark.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundStyle(.blue.opacity(0.7))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.08))
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Compact Bookend Row

    private func compactBookend(icon: String, tint: Color, label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint.opacity(0.6))
                .font(.caption)
                .padding(.top, 2)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2).fontWeight(.semibold).foregroundStyle(tint.opacity(0.7))
                Text(text)
                    .font(.subheadline).foregroundStyle(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 3)
        .listRowBackground(tint.opacity(0.03))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: 32)).foregroundStyle(.quaternary)
            if selectedTag != nil {
                Text("No remarks with this tag")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Clear filter") { selectedTag = nil }
                    .font(.caption)
            } else {
                Text("No remarks this month")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Add notes to your activities from the Records tab")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
