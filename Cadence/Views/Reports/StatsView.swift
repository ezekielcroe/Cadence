import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    let manager: TimeTrackingManager
    @Environment(\.modelContext) private var modelContext

    // We fetch DayNotes and Remarks specifically for the *selected* date
    // using a dynamic query approach is hard in a single view, so we fetch
    // relevant items manually in loadData() for performance.
    
    @State private var selectedDate: Date = Date()
    @State private var dayStats: DayStats?
    @State private var dayBlocks: [TimeBlock] = []
    @State private var dayRemarks: [Remark] = []
    @State private var dayNote: DayNote?
    
    // UI State
    @State private var showingReflection = false
    @State private var showingDatePicker = false

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // MARK: - Date Navigator
                    HStack {
                        Button(action: { changeDate(by: -1) }) {
                            Image(systemName: "chevron.left").padding(8)
                        }
                        
                        Spacer()
                        
                        Button { showingDatePicker = true } label: {
                            HStack {
                                Image(systemName: "calendar")
                                Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                                    .monospacedDigit()
                            }
                            .font(.headline)
                            .foregroundStyle(.primary)
                        }
                        
                        Spacer()
                        
                        Button(action: { changeDate(by: 1) }) {
                            Image(systemName: "chevron.right").padding(8)
                        }
                        .disabled(isToday) // Future dates disabled
                    }
                    .padding(.horizontal)

                    // MARK: - Content
                    
                    // 1. Intention
                    if let note = dayNote, !note.intention.isEmpty {
                        IntentionCard(intention: note.intention)
                            .padding(.horizontal)
                    }

                    // 2. Stats & Charts
                    if let stats = dayStats {
                        statsContent(stats)
                    } else {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.bar",
                            description: Text("No tracking data available for this date.")
                        )
                        .padding(.top, 40)
                    }

                    // 3. Remarks Timeline
                    if !dayRemarks.isEmpty {
                        TodayRemarksCard(remarks: dayRemarks, blocks: dayBlocks)
                            .padding(.horizontal)
                    }

                    // 4. Reflection
                    // Only show for Today or if a reflection exists for past days
                    if isToday || (dayNote?.reflection.isEmpty == false) {
                        EveningReflectionCard(
                            note: dayNote,
                            onTap: { showingReflection = true }
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                }
                .padding(.top)
            }
            .navigationTitle(isToday ? "Today" : "History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { loadData() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingReflection) {
                ReflectionSheet(existingNote: dayNote)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingDatePicker) {
                VStack {
                    DatePicker("Select Date", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                    Button("Done") { showingDatePicker = false }
                        .buttonStyle(.borderedProminent)
                }
                .presentationDetents([.medium])
            }
            .onChange(of: selectedDate) { _, _ in loadData() }
            .onAppear { loadData(); startAutoRefresh() }
        }
    }

    // MARK: - Data Loading Logic

    private func changeDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            withAnimation { selectedDate = newDate }
        }
    }

    private func loadData() {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        // 1. Fetch Blocks (Fast query for single day)
        // We need blocks for the TimelineChart even if we have cached stats
        let blockDesc = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.startTime >= dayStart && $0.startTime < dayEnd },
            sortBy: [SortDescriptor(\.startTime)]
        )
        dayBlocks = (try? modelContext.fetch(blockDesc)) ?? []
        
        // 2. Fetch Remarks (Manual filter optimization)
        // Only fetch remarks linked to these blocks
        let blockIDs = Set(dayBlocks.map { $0.id })
        let remarkDesc = FetchDescriptor<Remark>(sortBy: [SortDescriptor(\.timestamp)])
        if let all = try? modelContext.fetch(remarkDesc) {
            dayRemarks = all.filter { blockIDs.contains($0.timeBlockID) }
        } else {
            dayRemarks = []
        }

        // 3. Fetch Note
        let noteDesc = FetchDescriptor<DayNote>(
            predicate: #Predicate { $0.date == dayStart }
        )
        dayNote = (try? modelContext.fetch(noteDesc))?.first

        // 4. Determine Stats Source
        if isToday {
            // LIVE Mode: Calculate on the fly
            dayStats = manager.getTodaysStats()
        } else {
            // HISTORY Mode: Use cached summary
            if let summary = HistoryManager.shared.getOrGenerateSummary(for: selectedDate, in: modelContext) {
                dayStats = summary.asDayStats
                // Refresh note from summary if needed (though we fetched fresh above)
            } else {
                dayStats = nil
            }
        }
    }

    private func startAutoRefresh() {
        // Only auto-refresh if we are looking at Today
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            if isToday { loadData() }
        }
    }
    
    // MARK: - Subviews (Reusing existing logic)

    @ViewBuilder
    private func statsContent(_ stats: DayStats) -> some View {
        // Total & Count
        HStack(spacing: 12) {
            StatCard(title: "Total Time",  value: stats.totalDuration.formattedDuration, icon: "clock.fill",   color: .blue)
            StatCard(title: "Activities",  value: "\(stats.blockCount)",                 icon: "list.bullet",  color: .green)
        }
        .padding(.horizontal)

        // Switches & Avg
        HStack(spacing: 12) {
            StatCard(title: "Switches",    value: "\(stats.totalSwitches)", icon: "arrow.triangle.2.circlepath", color: .orange)
            StatCard(title: "Avg Duration",
                     value: stats.blockCount > 0 ? (stats.totalDuration / Double(stats.blockCount)).formattedDuration : "0m",
                     icon: "timer",        color: .purple)
        }
        .padding(.horizontal)

        // Breakdown Chart
        if !stats.sortedActivities.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Activity Breakdown").font(.headline).padding(.horizontal)
                Chart {
                    ForEach(stats.sortedActivities, id: \.name) { activity in
                        BarMark(
                            x: .value("Duration", activity.duration),
                            y: .value("Activity", activity.name)
                        )
                        .foregroundStyle(getActivityColor(activity.name))
                        .annotation(position: .trailing) {
                            Text(activity.duration.formattedDuration)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: CGFloat(max(3, stats.sortedActivities.count) * 50))
                .chartXAxis { AxisMarks(position: .bottom) }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }

        // Timeline Chart (Requires raw blocks)
        if !dayBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Timeline").font(.headline).padding(.horizontal)
                TimelineChart(blocks: dayBlocks)
                    .frame(height: 60)
                    .padding(.horizontal)
            }
            .padding(.vertical)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }

        // Detailed List
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Details").font(.headline).padding(.horizontal)
            ForEach(stats.sortedActivities, id: \.name) { activity in
                ActivityDetailRow(
                    name:       activity.name,
                    duration:   activity.duration,
                    percentage: stats.totalDuration > 0 ? (activity.duration / stats.totalDuration) * 100 : 0,
                    color:      getActivityColor(activity.name)
                )
            }
        }
        .padding(.vertical)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func getActivityColor(_ name: String) -> Color {
        // Optimization: Try to find color in today's blocks first
        if let block = dayBlocks.first(where: { $0.activityName == name }) {
            return Color(hex: block.activityColor)
        }
        // Fallback: If not in blocks (rare case for cached stats vs live blocks mismatch), return gray
        return .gray
    }
}

// MARK: - Intention Card (read-only display in StatsView)

struct IntentionCard: View {
    let intention: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today's Intention", systemImage: "sun.horizon.fill")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.orange)

            Text(intention)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - Today's Remarks Card

struct TodayRemarksCard: View {
    let remarks: [Remark]
    let blocks: [TimeBlock]

    private var blockLookup: [UUID: TimeBlock] {
        Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Remarks", systemImage: "note.text")
                .font(.headline)

            ForEach(remarks.prefix(5)) { remark in
                HStack(alignment: .top, spacing: 10) {
                    if let block = blockLookup[remark.timeBlockID] {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: block.activityColor))
                            .frame(width: 3)
                            .frame(minHeight: 32)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if let block = blockLookup[remark.timeBlockID] {
                                Text(block.activityName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(remark.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Text(remark.text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !remark.tags.isEmpty {
                            TagChipRow(tags: remark.tags)
                        }
                    }
                }

                if remark.id != remarks.prefix(5).last?.id {
                    Divider().padding(.leading, 13)
                }
            }

            if remarks.count > 5 {
                Text("+ \(remarks.count - 5) more remarks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Evening Reflection Card

struct EveningReflectionCard: View {
    let note: DayNote?
    let onTap: () -> Void

    private var hasReflection: Bool { !(note?.reflection.isEmpty ?? true) }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Evening Reflection", systemImage: "moon.stars")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.indigo)

                if hasReflection, let reflection = note?.reflection {
                    Text(reflection)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("How did today go? Tap to write a reflection.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.indigo.opacity(0.07))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(hasReflection ? Color.clear : Color.indigo.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reflection Sheet

struct ReflectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    let existingNote: DayNote?

    @State private var reflectionText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Evening Reflection")
                        .font(.headline)
                    Text("How did today go? What worked, what didn't?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextField("Write your reflection here…", text: $reflectionText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .lineLimit(4...10)

                Spacer()
            }
            .padding()
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                reflectionText = existingNote?.reflection ?? ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isFocused = true }
            }
        }
    }

    private func save() {
        let trimmed = reflectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { dismiss(); return }

        if let note = existingNote {
            note.reflection = trimmed
            note.reflectionUpdatedAt = Date()      // stamp write time
        } else {
            let note = DayNote(date: Date(), reflection: trimmed)
            // reflectionUpdatedAt is set inside DayNote.init when reflection is non-empty
            modelContext.insert(note)
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Supporting views (unchanged from original)

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(value).font(.title3).fontWeight(.bold).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ActivityDetailRow: View {
    let name: String
    let duration: TimeInterval
    let percentage: Double
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(name).font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(duration.formattedDuration).font(.subheadline).fontWeight(.semibold).monospacedDigit()
                Text("\(Int(percentage))%").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct TimelineChart: View {
    let blocks: [TimeBlock]

    // MARK: - Derived range

    /// The left edge of the chart. For a normal day this is startOfDay;
    /// for a day that starts with an overnight block from the night before
    /// we still anchor to startOfDay so the chart always begins at 00:00.
    private var chartStart: Date {
        Calendar.current.startOfDay(for: blocks.first?.startTime ?? Date())
    }

    /// The right edge of the chart: whichever is latest between calendar
    /// midnight (endOfDay) and the actual end of the last block.
    /// Capped at the current moment so we don't draw future empty space.
    private var chartEnd: Date {
        let cal        = Calendar.current
        let endOfDay   = cal.date(byAdding: .day, value: 1, to: chartStart)!
        let latestEnd  = blocks.compactMap { $0.endTime }.max() ?? Date()
        return min(max(endOfDay, latestEnd), Date() + 60) // +60s so "now" never clips
    }

    private var totalSpan: TimeInterval {
        max(chartEnd.timeIntervalSince(chartStart), 1)  // guard against zero-division
    }

    /// True when the chart range crosses at least one calendar midnight
    /// (i.e. any block ends after the calendar day of chartStart).
    private var spansMultipleDays: Bool {
        let endOfDay = Calendar.current.date(
            byAdding: .day, value: 1, to: chartStart
        )!
        return blocks.contains {
            ($0.endTime ?? Date()) > endOfDay
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color(.systemGray5))

                // Block bars
                ForEach(blocks) { block in
                    let start    = block.startTime
                    let end      = block.endTime ?? Date()
                    let xOffset  = offset(for: start,  width: geometry.size.width)
                    let barWidth = width(from: start, to: end, totalWidth: geometry.size.width)

                    Rectangle()
                        .fill(Color(hex: block.activityColor))
                        .frame(width: max(barWidth, 2))   // min 2pt so tiny blocks stay visible
                        .offset(x: xOffset)
                }

                // Midnight marker — only when the range spans multiple days
                if spansMultipleDays {
                    let midnight   = Calendar.current.date(
                        byAdding: .day, value: 1, to: chartStart
                    )!
                    let markerX = offset(for: midnight, width: geometry.size.width)

                    Rectangle()
                        .fill(Color(.systemBackground).opacity(0.6))
                        .frame(width: 1.5)
                        .offset(x: markerX)
                }
            }
        }
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func offset(for date: Date, width: CGFloat) -> CGFloat {
        let ratio = date.timeIntervalSince(chartStart) / totalSpan
        return width * CGFloat(ratio.clamped(to: 0...1))
    }

    private func width(from start: Date, to end: Date, totalWidth: CGFloat) -> CGFloat {
        let duration = end.timeIntervalSince(start)
        let ratio    = duration / totalSpan
        // Clamp so a block that ends beyond chartEnd doesn't overflow the frame
        let clampedRatio = min(ratio, 1.0 - start.timeIntervalSince(chartStart) / totalSpan)
        return totalWidth * CGFloat(max(clampedRatio, 0))
    }
}

// MARK: - Comparable clamping helper (local to this file)

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
