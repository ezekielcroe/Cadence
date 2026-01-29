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
    
    @State private var selectedPeriod: ReportGenerator.ReportPeriod = .thisWeek
    @State private var report: ReportGenerator.Report?
    @State private var showingShareSheet = false
    @State private var reportText = ""
    
    let reportGenerator = ReportGenerator()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Period Picker
                    Picker("Period", selection: $selectedPeriod) {
                        Text("This Week").tag(ReportGenerator.ReportPeriod.thisWeek)
                        Text("Last Week").tag(ReportGenerator.ReportPeriod.lastWeek)
                        Text("This Month").tag(ReportGenerator.ReportPeriod.thisMonth)
                        Text("Last Month").tag(ReportGenerator.ReportPeriod.lastMonth)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    if let report = report {
                        // Summary Cards
                        HStack(spacing: 12) {
                            SummaryCard(
                                title: "Total Time",
                                value: report.totalDuration.formattedDuration,
                                icon: "clock.fill",
                                color: .blue
                            )
                            
                            SummaryCard(
                                title: "Activities",
                                value: "\(report.totalBlocks)",
                                icon: "list.bullet",
                                color: .green
                            )
                        }
                        .padding(.horizontal)
                        
                        HStack(spacing: 12) {
                            SummaryCard(
                                title: "Switches",
                                value: "\(report.totalSwitches)",
                                icon: "arrow.triangle.2.circlepath",
                                color: .orange
                            )
                            
                            if let mostProductive = report.mostProductiveDay {
                                SummaryCard(
                                    title: "Best Day",
                                    value: mostProductive.duration.formattedDuration,
                                    icon: "star.fill",
                                    color: .yellow
                                )
                            }
                        }
                        .padding(.horizontal)
                        
                        // Comparison Card
                        if let comparison = report.comparisonToPrevious {
                            ComparisonCard(comparison: comparison, currentTotal: report.totalDuration)
                                .padding(.horizontal)
                        }
                        
                        // Top Activities
                        if !report.topActivities.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Top Activities")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                ForEach(Array(report.topActivities.enumerated()), id: \.offset) { index, activity in
                                    HStack {
                                        Text("\(index + 1)")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 30)
                                        
                                        if let breakdown = report.activityBreakdown.first(where: { $0.name == activity.name }) {
                                            Circle()
                                                .fill(Color(hex: breakdown.color))
                                                .frame(width: 12, height: 12)
                                        }
                                        
                                        Text(activity.name)
                                            .font(.subheadline)
                                        
                                        Spacer()
                                        
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(activity.duration.formattedDuration)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .monospacedDigit()
                                            
                                            if let breakdown = report.activityBreakdown.first(where: { $0.name == activity.name }) {
                                                Text("\(Int(breakdown.percentage))%")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                }
                            }
                            .padding(.vertical)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                        // Activity Breakdown Chart
                        if !report.activityBreakdown.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Activity Breakdown")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                Chart(report.activityBreakdown.prefix(8), id: \.name) { activity in
                                    BarMark(
                                        x: .value("Duration", activity.duration),
                                        y: .value("Activity", activity.name)
                                    )
                                    .foregroundStyle(Color(hex: activity.color))
                                    .annotation(position: .trailing) {
                                        Text(activity.duration.formattedDuration)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(height: CGFloat(min(report.activityBreakdown.count, 8)) * 50)
                                .chartXAxis {
                                    AxisMarks(position: .bottom)
                                }
                                .padding(.horizontal)
                            }
                            .padding(.vertical)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                        // Daily Trend Chart
                        if !report.dailyTotals.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Daily Trend")
                                    .font(.headline)
                                    .padding(.horizontal)
                                
                                Chart(report.dailyTotals, id: \.date) { daily in
                                    BarMark(
                                        x: .value("Date", daily.date, unit: .day),
                                        y: .value("Duration", daily.duration / 3600) // Convert to hours
                                    )
                                    .foregroundStyle(.blue.gradient)
                                }
                                .frame(height: 200)
                                .chartXAxis {
                                    AxisMarks(values: .stride(by: .day)) { value in
                                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks { value in
                                        AxisValueLabel {
                                            if let hours = value.as(Double.self) {
                                                Text("\(Int(hours))h")
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.vertical)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                    } else {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.bar.xaxis",
                            description: Text("No activities tracked for this period")
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
            .onChange(of: selectedPeriod) { _, _ in
                generateReport()
            }
            .onAppear {
                generateReport()
            }
        }
    }
    
    private func generateReport() {
        report = reportGenerator.generateReport(for: selectedPeriod, blocks: allTimeBlocks)
    }
    
    private func shareReport() {
        guard let report = report else { return }
        reportText = reportGenerator.formatReportAsText(report)
        showingShareSheet = true
    }
}

// MARK: - Summary Card
struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Comparison Card
struct ComparisonCard: View {
    let comparison: ReportGenerator.Report.ComparisonData
    let currentTotal: TimeInterval
    
    var changeColor: Color {
        comparison.durationChange >= 0 ? .green : .red
    }
    
    var changeIcon: String {
        comparison.durationChange >= 0 ? "arrow.up.right" : "arrow.down.right"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.blue)
                Text("Compared to Previous Period")
                    .font(.headline)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Change")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: changeIcon)
                            .font(.caption)
                        Text(abs(comparison.durationChange).formattedDuration)
                            .fontWeight(.semibold)
                        Text("(\(String(format: "%.1f", abs(comparison.percentageChange)))%)")
                            .font(.caption)
                    }
                    .foregroundStyle(changeColor)
                }
                
                Spacer()
            }
            
            if !comparison.activityChanges.isEmpty {
                Divider()
                
                Text("Biggest Changes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                ForEach(comparison.activityChanges.prefix(3), id: \.name) { change in
                    HStack {
                        Image(systemName: change.change >= 0 ? "arrow.up" : "arrow.down")
                            .font(.caption)
                            .foregroundStyle(change.change >= 0 ? .green : .red)
                        
                        Text(change.name)
                            .font(.caption)
                        
                        Spacer()
                        
                        Text(abs(change.change).formattedDuration)
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Activity.self, ActivitySet.self, TimeBlock.self, TimeBlockRule.self, configurations: config)
    
    return ReportsView()
        .modelContainer(container)
}
