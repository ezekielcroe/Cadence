//
//  TimesheetExportView.swift
//  Cadence
//
//  Created by Yeo Zhi Zheng on 7/7/26.
//


//
//  TimesheetExportView.swift
//  Cadence
//
//  Present from ReportsView (toolbar button) or DataManagementView.
//  Builds one DayLedger per day in the period, maps through
//  TimesheetBuilder, renders with TimesheetRenderer, shares the PDF.
//  The PDF cannot disagree with any screen because both read the ledger.
//

import SwiftUI
import SwiftData

struct TimesheetExportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Period: String, CaseIterable, Identifiable {
        case thisWeek = "This Week"
        case lastWeek = "Last Week"
        case custom   = "Custom"
        var id: String { rawValue }
    }

    @AppStorage("timesheetOwnerName") private var ownerName = ""
    @AppStorage("timesheetIncludeGaps") private var includeGaps = true
    @AppStorage("timesheetIncludeRemarks") private var includeRemarks = true

    @State private var period: Period = .thisWeek
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    @State private var customEnd   = Date()
    @State private var isGenerating = false
    @State private var generatedURL: URL?
    @State private var errorMessage: String?

    private var dateRange: ClosedRange<Date> {
        let cal = Calendar.current
        switch period {
        case .thisWeek:
            let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
            return start...Date()
        case .lastWeek:
            let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
            let start = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!
            let end = cal.date(byAdding: .second, value: -1, to: thisWeekStart)!
            return start...end
        case .custom:
            let start = cal.startOfDay(for: customStart)
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: customEnd))!
            return start...max(start, cal.date(byAdding: .second, value: -1, to: end)!)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Period") {
                    Picker("Period", selection: $period) {
                        ForEach(Period.allCases) { p in Text(p.rawValue).tag(p) }
                    }
                    .pickerStyle(.segmented)

                    if period == .custom {
                        DatePicker("From", selection: $customStart, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd,
                                   in: customStart...Date(), displayedComponents: .date)
                    }
                }

                Section("Document") {
                    TextField("Name (appears in header)", text: $ownerName)
                    Toggle("Show unaccounted time", isOn: $includeGaps)
                    Toggle("Include remarks", isOn: $includeRemarks)
                }

                Section {
                    LabeledContent("Accountable hours") {
                        Text(TrackingWindow.current.displayString)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Unaccounted time is only reported inside your accountable hours. Change them in Settings.")
                }

                Section {
                    Button {
                        generate()
                    } label: {
                        if isGenerating {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Generate Timesheet", systemImage: "doc.text")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isGenerating)

                    if let url = generatedURL {
                        ShareLink(item: url) {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Export Timesheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: period) { _, _ in generatedURL = nil }
            .onChange(of: includeGaps) { _, _ in generatedURL = nil }
            .onChange(of: includeRemarks) { _, _ in generatedURL = nil }
        }
    }

    private func generate() {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let cal = Calendar.current
        let range = dateRange

        // One ledger per day in the period.
        var ledgers: [DayLedger] = []
        var day = cal.startOfDay(for: range.lowerBound)
        while day <= range.upperBound {
            ledgers.append(LedgerBuilder.makeLedger(for: day, context: modelContext))
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }

        // Remarks for every block appearing in the period.
        let blockIDs = Set(ledgers.flatMap { $0.blocks.map(\.block.id) })
        let remarkDescriptor = FetchDescriptor<Remark>(sortBy: [SortDescriptor(\.timestamp)])
        let allRemarks = (try? modelContext.fetch(remarkDescriptor)) ?? []
        let remarksByBlock = Dictionary(
            grouping: allRemarks.filter { blockIDs.contains($0.timeBlockID) },
            by: \.timeBlockID
        )

        // Day notes in the period.
        let noteDescriptor = FetchDescriptor<DayNote>()
        let notes = (try? modelContext.fetch(noteDescriptor)) ?? []
        let notesByDay = Dictionary(
            notes.map { (cal.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { a, _ in a }
        )

        let document = TimesheetBuilder.build(
            ledgers: ledgers,
            remarksByBlock: remarksByBlock,
            notesByDay: notesByDay,
            options: .init(
                includeGaps: includeGaps,
                includeRemarks: includeRemarks,
                stripHashtags: true,
                ownerName: ownerName.trimmingCharacters(in: .whitespaces)
            )
        )

        guard !document.days.isEmpty else {
            errorMessage = "No tracked time in this period."
            return
        }

        do {
            generatedURL = try TimesheetRenderer.render(document)
        } catch {
            errorMessage = "Could not write the PDF: \(error.localizedDescription)"
        }
    }
}
