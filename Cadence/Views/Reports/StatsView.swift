import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    let manager: TimeTrackingManager

    @Environment(\.modelContext) private var modelContext
    @Query private var dayNotes: [DayNote]
    @Query(sort: \Remark.timestamp, order: .forward) private var allRemarks: [Remark]

    @State private var stats: DayStats?
    @State private var timeBlocks: [TimeBlock] = []
    @State private var showingReflection = false

    // MARK: - Today's data

    private var todayNote: DayNote? {
        dayNotes.first { Calendar.current.isDateInToday($0.date) }
    }

    private var todayRemarks: [Remark] {
        let todayBlockIDs = Set(timeBlocks.map { $0.id })
        return allRemarks
            .filter { todayBlockIDs.contains($0.timeBlockID) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private var hasReflection: Bool {
        !(todayNote?.reflection.isEmpty ?? true)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // ── Morning Intention ───────────────────────────────────
                    if let note = todayNote, !note.intention.isEmpty {
                        IntentionCard(intention: note.intention)
                            .padding(.horizontal)
                    }

                    // ── Stat Cards + Charts (original content) ───────────────
                    if let stats = stats {
                        statsContent(stats)
                    } else {
                        ContentUnavailableView(
                            "No Data Yet",
                            systemImage: "chart.bar",
                            description: Text("Start tracking activities to see your stats")
                        )
                    }

                    // ── Today's Remarks (chronological prose thread) ─────────
                    if !todayRemarks.isEmpty {
                        TodayRemarksCard(remarks: todayRemarks, blocks: timeBlocks)
                            .padding(.horizontal)
                    }

                    // ── Evening Reflection ──────────────────────────────────
                    EveningReflectionCard(
                        note: todayNote,
                        onTap: { showingReflection = true }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.top)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: loadStats) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingReflection) {
                ReflectionSheet(existingNote: todayNote)
                    .presentationDetents([.medium])
            }
            .onAppear { loadStats(); startAutoRefresh() }
        }
    }

    // MARK: - Stats Content (original structure preserved)

    @ViewBuilder
    private func statsContent(_ stats: DayStats) -> some View {
        HStack(spacing: 12) {
            StatCard(title: "Total Time",  value: stats.totalDuration.formattedDuration,
                     icon: "clock.fill",   color: .blue)
            StatCard(title: "Activities",  value: "\(stats.blockCount)",
                     icon: "list.bullet",  color: .green)
        }
        .padding(.horizontal)

        HStack(spacing: 12) {
            StatCard(title: "Switches",    value: "\(stats.totalSwitches)",
                     icon: "arrow.triangle.2.circlepath", color: .orange)
            StatCard(title: "Avg Duration",
                     value: stats.blockCount > 0
                        ? (stats.totalDuration / Double(stats.blockCount)).formattedDuration
                        : "0m",
                     icon: "timer",        color: .purple)
        }
        .padding(.horizontal)

        if !stats.sortedActivities.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Activity Breakdown")
                    .font(.headline)
                    .padding(.horizontal)

                Chart {
                    ForEach(stats.sortedActivities, id: \.name) { activity in
                        BarMark(
                            x: .value("Duration", activity.duration),
                            y: .value("Activity", activity.name)
                        )
                        .foregroundStyle(getActivityColor(activity.name))
                        .annotation(position: .trailing) {
                            Text(activity.duration.formattedDuration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: CGFloat(stats.sortedActivities.count) * 50)
                .chartXAxis { AxisMarks(position: .bottom) }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }

        if !timeBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Timeline")
                    .font(.headline)
                    .padding(.horizontal)

                TimelineChart(blocks: timeBlocks)
                    .frame(height: 60)
                    .padding(.horizontal)
            }
            .padding(.vertical)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }

        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Details")
                .font(.headline)
                .padding(.horizontal)

            ForEach(stats.sortedActivities, id: \.name) { activity in
                ActivityDetailRow(
                    name:       activity.name,
                    duration:   activity.duration,
                    percentage: stats.totalDuration > 0
                        ? (activity.duration / stats.totalDuration) * 100
                        : 0,
                    color:      getActivityColor(activity.name)
                )
            }
        }
        .padding(.vertical)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func loadStats() {
        stats      = manager.getTodaysStats()
        timeBlocks = manager.getTodaysTimeBlocks()
    }

    private func startAutoRefresh() {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            loadStats()
        }
    }

    private func getActivityColor(_ name: String) -> Color {
        if let block = timeBlocks.first(where: { $0.activityName == name }) {
            return Color(hex: block.activityColor)
        }
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

    private var startOfDay: Date { Calendar.current.startOfDay(for: Date()) }
    private var endOfDay: Date   { Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)! }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(.systemGray5))
                ForEach(blocks.filter { $0.endTime != nil }) { block in
                    let start       = block.startTime
                    let end         = block.endTime ?? Date()
                    let startOffset = start.timeIntervalSince(startOfDay) / 86400
                    let duration    = end.timeIntervalSince(start) / 86400
                    Rectangle()
                        .fill(Color(hex: block.activityColor))
                        .frame(width: geometry.size.width * duration)
                        .offset(x: geometry.size.width * startOffset)
                }
            }
        }
        .cornerRadius(8)
    }
}

