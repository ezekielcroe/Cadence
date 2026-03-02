//
//  ReportsView.swift
//  Cadence
//

import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTimeBlocks: [TimeBlock]
    @Query private var activities: [Activity]
    @Query private var allRemarks: [Remark]

    @State private var selectedPeriod: ReportGenerator.ReportPeriod = .week
    @State private var report: ReportGenerator.Report?
    @State private var showingShareSheet = false

    let reportGenerator = ReportGenerator()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(ReportGenerator.ReportPeriod.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if let report = report {
                        reportContent(report)
                    } else {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.bar.xaxis",
                            description: Text("Start tracking activities to see your reports")
                        )
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: shareReport) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(report == nil)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let report = report {
                    ShareSheet(text: reportGenerator.formatReportAsText(report))
                }
            }
            .onChange(of: selectedPeriod) { _, _ in generateReport() }
            .onAppear { generateReport() }
        }
    }

    // MARK: - Report Content

    @ViewBuilder
    private func reportContent(_ report: ReportGenerator.Report) -> some View {
        // Summary cards — FIX: use totalDuration directly, clamp unaccounted
        HStack(spacing: 12) {
            SummaryCard(
                title: "Tracked",
                value: report.totalDuration.formattedDuration,
                icon:  "clock.badge.checkmark.fill",
                color: .blue
            )
            SummaryCard(
                title: "Unaccounted",
                value: max(0, report.unaccountedDuration).formattedDuration,
                icon:  "questionmark.circle",
                color: .orange
            )
        }
        .padding(.horizontal)

        // Fragmentation card
        FragmentationCard(fragmentation: report.fragmentation)
            .padding(.horizontal)

        // Comparison card
        if let comparison = report.comparisonToPrevious {
            ComparisonCard(comparison: comparison, period: report.period)
                .padding(.horizontal)
        }

        // Activity Breakdown — REDESIGNED: rich rows with progress bars
        if !report.activityBreakdown.isEmpty {
            ActivityBreakdownCard(report: report)
                .padding(.horizontal)
        }

        // Tag Breakdown
        if !report.tagBreakdown.isEmpty {
            TagBreakdownCard(tags: report.tagBreakdown)
                .padding(.horizontal)
        }

        // Remarks Explorer — REDESIGNED: filterable by activity + tag
        let periodRemarks = remarksForPeriod(report.period)
        if !periodRemarks.isEmpty {
            RemarksExplorerCard(
                remarks: periodRemarks,
                blocks: blocksForPeriod(report.period)
            )
            .padding(.horizontal)
        }
    }

    // MARK: - Generate

    private func generateReport() {
        report = reportGenerator.generateReport(
            for: selectedPeriod,
            blocks: allTimeBlocks,
            activities: activities,
            remarks: allRemarks
        )
    }

    private func shareReport() {
        guard report != nil else { return }
        showingShareSheet = true
    }

    // MARK: - Period helpers

    private func blocksForPeriod(_ period: ReportGenerator.ReportPeriod) -> [TimeBlock] {
        let (start, end) = periodRange(period)
        return allTimeBlocks.filter { $0.startTime >= start && $0.startTime < end }
    }

    private func remarksForPeriod(_ period: ReportGenerator.ReportPeriod) -> [Remark] {
        let blocks = blocksForPeriod(period)
        let blockIDs = Set(blocks.map { $0.id })
        return allRemarks
            .filter { blockIDs.contains($0.timeBlockID) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func periodRange(_ period: ReportGenerator.ReportPeriod) -> (Date, Date) {
        let cal = Calendar.current
        let now = Date()
        let start: Date
        switch period {
        case .day:   start = cal.startOfDay(for: now.addingTimeInterval(-86400))
        case .week:  start = cal.startOfDay(for: now.addingTimeInterval(-7 * 86400))
        case .month: start = cal.startOfDay(for: now.addingTimeInterval(-30 * 86400))
        }
        return (start, now)
    }
}

// MARK: - Activity Breakdown Card (REDESIGNED)

struct ActivityBreakdownCard: View {
    let report: ReportGenerator.Report

    @State private var showAll = false

    var body: some View {
        let breakdown = report.activityBreakdown
        let items = showAll ? Array(breakdown) : Array(breakdown.prefix(6))
        let total = report.totalDuration

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Activity Breakdown", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                Text("\(breakdown.count) activities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Mini donut overview
            if breakdown.count > 1 {
                Chart(breakdown.prefix(8), id: \.name) { item in
                    SectorMark(
                        angle: .value("Duration", item.duration),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(Color(hex: item.color))
                }
                .chartLegend(.hidden)
                .frame(height: 140)
                .padding(.bottom, 4)
            }

            // Detailed rows
            ForEach(items, id: \.name) { item in
                let pct: Double = total > 0 ? item.duration / total : 0

                VStack(spacing: 6) {
                    HStack {
                        Circle()
                            .fill(Color(hex: item.color))
                            .frame(width: 10, height: 10)
                        Text(item.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(item.duration.formattedDuration)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                        Text("(\(Int(pct * 100))%)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.systemGray5))
                                .frame(height: 6)
                            Capsule()
                                .fill(Color(hex: item.color))
                                .frame(width: geo.size.width * CGFloat(pct), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }

            if breakdown.count > 6 {
                Button {
                    withAnimation { showAll.toggle() }
                } label: {
                    Text(showAll ? "Show Less" : "Show All \(breakdown.count) Activities")
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Remarks Explorer Card (NEW — replaces Highlights)

struct RemarksExplorerCard: View {
    let remarks: [Remark]
    let blocks: [TimeBlock]

    @State private var selectedActivity: String? = nil
    @State private var selectedTag: String? = nil
    @State private var showAll = false

    private var blockLookup: [UUID: TimeBlock] {
        var lookup: [UUID: TimeBlock] = [:]
        for block in blocks { lookup[block.id] = block }
        return lookup
    }

    private var availableActivities: [String] {
        let names = Set(remarks.compactMap { blockLookup[$0.timeBlockID]?.activityName })
        return names.sorted()
    }

    private var availableTags: [String] {
        let tags = Set(remarks.flatMap { $0.tags })
        return tags.sorted()
    }

    private var filteredRemarks: [Remark] {
        remarks.filter { remark in
            let matchesActivity: Bool = {
                guard let activity = selectedActivity else { return true }
                return blockLookup[remark.timeBlockID]?.activityName == activity
            }()

            let matchesTag: Bool = {
                guard let tag = selectedTag else { return true }
                return remark.tags.contains(tag)
            }()

            return matchesActivity && matchesTag
        }
    }

    private var displayRemarks: [Remark] {
        showAll ? filteredRemarks : Array(filteredRemarks.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header
            HStack {
                Label("Remarks", systemImage: "note.text")
                    .font(.headline)
                Spacer()
                Text("\(filteredRemarks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            }

            // Filter chips
            VStack(alignment: .leading, spacing: 8) {
                // Activity filter
                if availableActivities.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            FilterChip(
                                label: "All Activities",
                                isSelected: selectedActivity == nil,
                                color: .primary
                            ) {
                                withAnimation { selectedActivity = nil }
                            }

                            ForEach(availableActivities, id: \.self) { name in
                                let color = blocks.first(where: { $0.activityName == name })
                                    .map { Color(hex: $0.activityColor) } ?? .gray
                                FilterChip(
                                    label: name,
                                    isSelected: selectedActivity == name,
                                    color: color
                                ) {
                                    withAnimation {
                                        selectedActivity = selectedActivity == name ? nil : name
                                    }
                                }
                            }
                        }
                    }
                }

                // Tag filter
                if !availableTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            FilterChip(
                                label: "All Tags",
                                isSelected: selectedTag == nil,
                                color: .blue
                            ) {
                                withAnimation { selectedTag = nil }
                            }

                            ForEach(availableTags, id: \.self) { tag in
                                FilterChip(
                                    label: "#\(tag)",
                                    isSelected: selectedTag == tag,
                                    color: .blue
                                ) {
                                    withAnimation {
                                        selectedTag = selectedTag == tag ? nil : tag
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Remark list
            if filteredRemarks.isEmpty {
                Text("No remarks match the selected filters.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(displayRemarks) { remark in
                    remarkRow(remark)

                    if remark.id != displayRemarks.last?.id {
                        Divider().padding(.leading, 13)
                    }
                }

                if filteredRemarks.count > 8 {
                    Button {
                        withAnimation { showAll.toggle() }
                    } label: {
                        Text(showAll ? "Show Less" : "Show All \(filteredRemarks.count) Remarks")
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Remark Row

    @ViewBuilder
    private func remarkRow(_ remark: Remark) -> some View {
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
                    Text(remark.timestamp.formatted(date: .abbreviated, time: .shortened))
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
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? color.opacity(0.15) : Color(.systemGray5))
                .foregroundStyle(isSelected ? color : .secondary)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? color.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fragmentation Card

struct FragmentationCard: View {
    let fragmentation: ReportGenerator.FragmentationData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Focus Quality", systemImage: "brain")
                    .font(.headline)
                Spacer()
                Text(fragmentation.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(hex: fragmentation.color))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: fragmentation.color).opacity(0.12))
                    .cornerRadius(8)
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f", fragmentation.switchesPerHour))
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                    Text("switches / hr")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(fragmentation.averageBlockDuration.formattedDuration)
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                    Text("avg block")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Based on context switches and block length across the period.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Tag Breakdown Card

struct TagBreakdownCard: View {
    let tags: [ReportGenerator.TagStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tags", systemImage: "tag")
                .font(.headline)

            ForEach(tags.prefix(8)) { stat in
                HStack(alignment: .top) {
                    Text("#\(stat.tag)")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                        .frame(minWidth: 80, alignment: .leading)

                    Text(stat.activities.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(stat.count)×")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if stat.tag != tags.prefix(8).last?.tag {
                    Divider()
                }
            }

            if tags.count > 8 {
                Text("+ \(tags.count - 8) more tags this period")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Comparison Card (preserved)

struct ComparisonCard: View {
    let comparison: ReportGenerator.Report.ComparisonData
    let period: ReportGenerator.ReportPeriod

    var topChanges: [ActivityChange] { Array(comparison.activityChanges.prefix(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compared to \(comparison.comparisonLabel)").font(.headline)
                    Text(period.comparisonDescription).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Change").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: comparison.durationChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(abs(comparison.durationChange).formattedDuration).fontWeight(.semibold)
                    }
                    .foregroundStyle(comparison.durationChange >= 0 ? .green : .red)
                }
                Spacer()
                Text("\(comparison.durationChange >= 0 ? "+" : "")\(String(format: "%.1f", comparison.percentageChange))%")
                    .font(.title3).fontWeight(.bold)
                    .foregroundStyle(comparison.durationChange >= 0 ? .green : .red)
            }

            if !topChanges.isEmpty {
                Divider()
                Text("Biggest Changes").font(.subheadline).foregroundStyle(.secondary)
                ForEach(topChanges) { ActivityChangeRow(change: $0) }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ActivityChangeRow: View {
    let change: ActivityChange

    private var color: Color {
        switch change.goal {
        case .increase: return change.change > 0 ? .green : .red
        case .decrease: return change.change > 0 ? .red : .green
        case .neutral:  return .secondary
        }
    }

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: change.change > 0 ? "arrow.up" : "arrow.down")
                    .font(.caption).foregroundStyle(color).frame(width: 12)
                Text(change.name).font(.caption).fontWeight(.medium)
            }
            Spacer()
            Text(abs(change.change).formattedDuration)
                .font(.caption).monospacedDigit().foregroundStyle(color)
        }
    }
}

// MARK: - Summary Card (preserved)

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(value).font(.title3).fontWeight(.bold).lineLimit(1).minimumScaleFactor(0.8)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Share Sheet (preserved)

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
