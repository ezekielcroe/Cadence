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
    
    @State private var selectedPeriod: ReportGenerator.ReportPeriod = .thisWeek
    @State private var report: ReportGenerator.Report?
    @State private var showingShareSheet = false
    @State private var reportText = ""
    
    let reportGenerator = ReportGenerator()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Picker("Period", selection: $selectedPeriod) {
                        Text("This Week").tag(ReportGenerator.ReportPeriod.thisWeek)
                        Text("Last Week").tag(ReportGenerator.ReportPeriod.lastWeek)
                        Text("This Month").tag(ReportGenerator.ReportPeriod.thisMonth)
                        Text("Last Month").tag(ReportGenerator.ReportPeriod.lastMonth)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    if let report = report {
                        // Summaries
                        HStack(spacing: 12) {
                            SummaryCard(title: "Total Time", value: report.totalDuration.formattedDuration, icon: "clock.fill", color: .blue)
                            SummaryCard(title: "Activities", value: "\(report.totalBlocks)", icon: "list.bullet", color: .green)
                        }
                        .padding(.horizontal)
                        
                        // Comparison
                        if let comparison = report.comparisonToPrevious {
                            ComparisonCard(comparison: comparison)
                                .padding(.horizontal)
                        }
                        
                        // Top Activities
                        if !report.topActivities.isEmpty {
                            TopActivitiesCard(report: report)
                                .padding(.horizontal)
                        }
                        
                        // Charts
                        if !report.activityBreakdown.isEmpty {
                            BreakdownChart(report: report)
                                .padding(.horizontal)
                        }
                        
                    } else {
                        ContentUnavailableView("No Data", systemImage: "chart.bar.xaxis")
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
    
    private func generateReport() {
        report = reportGenerator.generateReport(for: selectedPeriod, blocks: allTimeBlocks, activities: activities)
    }
    
    private func shareReport() {
        guard let report = report else { return }
        reportText = reportGenerator.formatReportAsText(report)
        showingShareSheet = true
    }
}

// MARK: - Subviews

struct ComparisonCard: View {
    let comparison: ReportGenerator.Report.ComparisonData
    
    // Explicitly compute the array to avoid Slice/Binding issues
    var topChanges: [ActivityChange] {
        Array(comparison.activityChanges.prefix(3))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.blue)
                Text("Compared to Previous").font(.headline)
            }
            
            // Total Change
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
            }
            
            if !topChanges.isEmpty {
                Divider()
                Text("Biggest Changes").font(.subheadline).foregroundStyle(.secondary)
                
                // Clean Loop: Iterating over a clear array of ActivityChange
                ForEach(topChanges) { change in
                    ActivityChangeRow(change: change)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - The Isolated Row View (Fixes the logic errors)
struct ActivityChangeRow: View {
    let change: ActivityChange
    
    private var color: Color {
        let isIncrease = change.change > 0
        switch change.goal {
        case .increase:
            return isIncrease ? .green : .red
        case .decrease:
            return isIncrease ? .red : .green
        case .neutral:
            return .secondary
        }
    }
    private var icon: String {
        let isIncrease = change.change > 0
        switch change.goal {
        case .increase, .decrease:
            return isIncrease ? "arrow.up" : "arrow.down"
        case .neutral:
            return isIncrease ? "arrow.up" : "arrow.down"
        }
    }
    
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                    .frame(width: 12)
                
                Text(change.name)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            Text(abs(change.change).formattedDuration)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(color)
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
                .foregroundStyle(Color(item.color))
            }
            .frame(height: 250)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct SummaryCard: View {
    let title: String, value: String, icon: String, color: Color
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
