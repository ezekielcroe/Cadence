//
//  CSVExporter.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 29/1/26.
//

import Foundation
import SwiftData

class CSVExporter {

    // MARK: - Export Options

    struct ExportOptions {
        var includeActivity:      Bool = true
        var includeStartTime:     Bool = true
        var includeEndTime:       Bool = true
        var includeDuration:      Bool = true
        var includePauseDuration: Bool = true
        var includeSwitchCount:   Bool = true
        var includeRemarks:       Bool = true   // concatenated remark text per block
        var includeTags:          Bool = true   // deduplicated tags per block
    }

    // MARK: - Export Time Blocks
    //
    // `remarks` is the full Remark table. Pass an empty array to omit remark/tag columns
    // even when the corresponding ExportOptions flags are true.

    func exportTimeBlocks(
        _ blocks: [TimeBlock],
        remarks: [Remark] = [],
        options: ExportOptions = ExportOptions()
    ) -> String {

        // Build a lookup: blockID → sorted remarks
        let remarksByBlock: [UUID: [Remark]] = Dictionary(
            grouping: remarks.sorted { $0.timestamp < $1.timestamp },
            by: { $0.timeBlockID }
        )

        var csv = generateBlockHeader(options: options) + "\n"

        for block in blocks {
            let blockRemarks = remarksByBlock[block.id] ?? []
            csv += buildBlockRow(block: block, remarks: blockRemarks, options: options) + "\n"
        }

        return csv
    }

    // MARK: - Export Remarks
    //
    // A separate flat table: one row per Remark, with its activity context from the
    // block lookup. Useful for tag-level analysis in spreadsheet tools.

    func exportRemarks(
        _ remarks: [Remark],
        blocks: [TimeBlock]
    ) -> String {
        let blockLookup = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })

        let header = ["Timestamp", "Activity", "Text", "Tags"].joined(separator: ",")
        var csv = header + "\n"

        let sorted = remarks.sorted { $0.timestamp < $1.timestamp }
        for remark in sorted {
            let block    = blockLookup[remark.timeBlockID]
            let activity = block?.activityName ?? ""
            let tagsStr  = remark.tags.map { "#\($0)" }.joined(separator: " ")
            let row = [
                formatDateTime(remark.timestamp),
                escapeCSV(activity),
                escapeCSV(remark.text),
                escapeCSV(tagsStr)
            ].joined(separator: ",")
            csv += row + "\n"
        }

        return csv
    }

    // MARK: - Row Builder

    private func buildBlockRow(block: TimeBlock, remarks: [Remark], options: ExportOptions) -> String {
        var row: [String] = []

        if options.includeActivity {
            row.append(escapeCSV(block.activityName))
        }
        if options.includeStartTime {
            row.append(formatDateTime(block.startTime))
        }
        if options.includeEndTime {
            row.append(block.endTime.map { formatDateTime($0) } ?? "Ongoing")
        }
        if options.includeDuration {
            row.append(formatDuration(block.duration))
        }
        if options.includePauseDuration {
            row.append(formatDuration(block.totalPauseDuration))
        }
        if options.includeSwitchCount {
            row.append("\(block.switchCount)")
        }
        if options.includeRemarks {
            // Each remark on its own line within the cell: "[HH:mm] text"
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let joined = remarks
                .map { "[\(formatter.string(from: $0.timestamp))] \($0.text)" }
                .joined(separator: "\n")
            row.append(escapeCSV(joined))
        }
        if options.includeTags {
            // Deduplicated, sorted tags across all remarks on this block
            let allTags = Array(Set(remarks.flatMap { $0.tags })).sorted()
            row.append(escapeCSV(allTags.map { "#\($0)" }.joined(separator: " ")))
        }

        return row.joined(separator: ",")
    }

    // MARK: - Header Builder

    private func generateBlockHeader(options: ExportOptions) -> String {
        var headers: [String] = []
        if options.includeActivity      { headers.append("Activity") }
        if options.includeStartTime     { headers.append("Start Time") }
        if options.includeEndTime       { headers.append("End Time") }
        if options.includeDuration      { headers.append("Duration") }
        if options.includePauseDuration { headers.append("Pause Duration") }
        if options.includeSwitchCount   { headers.append("Switches") }
        if options.includeRemarks       { headers.append("Remarks") }
        if options.includeTags          { headers.append("Tags") }
        return headers.joined(separator: ",")
    }

    // MARK: - Formatting

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours   = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        if hours   > 0 { return String(format: "%dh %dm %ds", hours, minutes, seconds) }
        if minutes > 0 { return String(format: "%dm %ds", minutes, seconds) }
        return String(format: "%ds", seconds)
    }

    private func escapeCSV(_ string: String) -> String {
        guard string.contains(",") || string.contains("\"") || string.contains("\n") else {
            return string
        }
        return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - File I/O

    func saveToFile(csv: String, filename: String) throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    func generateFilename(prefix: String = "cadence_export") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return "\(prefix)_\(formatter.string(from: Date())).csv"
    }
}
