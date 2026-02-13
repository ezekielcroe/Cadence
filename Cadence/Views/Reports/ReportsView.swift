//
//  ReportsView.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 29/1/26.
//

import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allTimeBlocks: [TimeBlock]
    @Query private var activities: [Activity]
    @Query private var allRemarks: [Remark]   // NEW: passed to generator

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
        // Summary cards
        HStack(spacing: 12) {
            SummaryCard(
                title: "Tracked",
                value: (report.totalDuration - report.unaccountedDuration).formattedDuration,
                icon:  "clock.badge.checkmark.fill",
                color: .blue
            )
            SummaryCard(
                title: "Unaccounted",
                value: report.unaccountedDuration.formattedDuration,
                icon:  "questionmark.circle",
                color: .orange
            )
        }
        .padding(.horizontal)

        // Fragmentation card (NEW)
        FragmentationCard(fragmentation: report.fragmentation)
            .padding(.horizontal)

        // Comparison card
        if let comparison = report.comparisonToPrevious {
            ComparisonCard(comparison: comparison, period: report.period)
                .padding(.horizontal)
        }

        // Activity Breakdown Chart
        if !report.activityBreakdown.isEmpty {
            BreakdownChart(report: report)
                .padding(.horizontal)
        }

        // Top Activities
        if !report.topActivities.isEmpty {
            TopActivitiesCard(report: report)
                .padding(.horizontal)
        }

        // Tag Breakdown (NEW)
        if !report.tagBreakdown.isEmpty {
            TagBreakdownCard(tags: report.tagBreakdown)
                .padding(.horizontal)
        }

        // Highlights (NEW)
        if !report.highlights.isEmpty {
            HighlightsCard(highlights: report.highlights, period: report.period)
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
        guard let report = report else { return }
        showingShareSheet = true
        _ = reportGenerator.formatReportAsText(report)
    }
}

// MARK: - Fragmentation Card (NEW)

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

// MARK: - Tag Breakdown Card (NEW)

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

// MARK: - Highlights Card (NEW)

struct HighlightsCard: View {
    let highlights: [ReportGenerator.RemarkHighlight]
    let period: ReportGenerator.ReportPeriod

    private var periodLabel: String {
        switch period {
        case .day:   return "Yesterday's Highlights"
        case .week:  return "Week's Highlights"
        case .month: return "Month's Highlights"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(periodLabel, systemImage: "sparkles")
                .font(.headline)

            ForEach(highlights) { highlight in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: highlight.activityColor))
                        .frame(width: 3)
                        .frame(minHeight: 40)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(highlight.activityName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(highlight.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Text(highlight.text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !highlight.tags.isEmpty {
                            TagChipRow(tags: highlight.tags)
                        }
                    }
                }

                if highlight.id != highlights.last?.id {
                    Divider().padding(.leading, 13)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Existing cards (preserved, unchanged) ──────────────────────────────

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

struct TopActivitiesCard: View {
    let report: ReportGenerator.Report

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Activities").font(.headline)
            ForEach(Array(report.topActivities.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text("\(index + 1)").font(.headline).foregroundStyle(.secondary).frame(width: 25)
                    Text(item.name).font(.subheadline)
                    Spacer()
                    Text(item.duration.formattedDuration).font(.subheadline).monospacedDigit()
                }
                if index < report.topActivities.count - 1 { Divider() }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct BreakdownChart: View {
    let report: ReportGenerator.Report

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Breakdown").font(.headline)
            Chart(report.activityBreakdown.prefix(8), id: \.name) { item in
                BarMark(
                    x: .value("Duration", item.duration),
                    y: .value("Activity", item.name)
                )
                .foregroundStyle(Color(hex: item.color))
            }
            .frame(height: 250)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

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

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
