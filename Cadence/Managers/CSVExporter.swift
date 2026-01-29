//
//  CSVExporter.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 29/1/26.
//


import Foundation
import SwiftData

class CSVExporter {
    
    // MARK: - Export Configuration
    struct ExportOptions {
        var includeActivity: Bool = true
        var includeStartTime: Bool = true
        var includeEndTime: Bool = true
        var includeDuration: Bool = true
        var includePauseDuration: Bool = true
        var includeSwitchCount: Bool = true
        var includeRemarks: Bool = true
    }
    
    // MARK: - Export Time Blocks
    func exportTimeBlocks(_ blocks: [TimeBlock], options: ExportOptions = ExportOptions()) -> String {
        var csv = generateHeader(options: options) + "\n"
        
        for block in blocks {
            var row: [String] = []
            
            if options.includeActivity {
                row.append(escapeCSV(block.activityName))
            }
            
            if options.includeStartTime {
                row.append(formatDateTime(block.startTime))
            }
            
            if options.includeEndTime {
                let endTimeStr = block.endTime.map { formatDateTime($0) } ?? "Ongoing"
                row.append(endTimeStr)
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
                row.append(escapeCSV(block.remarks))
            }
            
            csv += row.joined(separator: ",") + "\n"
        }
        
        return csv
    }
    
    // MARK: - Generate Header
    private func generateHeader(options: ExportOptions) -> String {
        var headers: [String] = []
        
        if options.includeActivity { headers.append("Activity") }
        if options.includeStartTime { headers.append("Start Time") }
        if options.includeEndTime { headers.append("End Time") }
        if options.includeDuration { headers.append("Duration") }
        if options.includePauseDuration { headers.append("Pause Duration") }
        if options.includeSwitchCount { headers.append("Switches") }
        if options.includeRemarks { headers.append("Remarks") }
        
        return headers.joined(separator: ",")
    }
    
    // MARK: - Formatting Helpers
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    private func escapeCSV(_ string: String) -> String {
        // If string contains comma, quote, or newline, wrap in quotes and escape quotes
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            let escaped = string.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return string
    }
    
    // MARK: - Save to File
    func saveToFile(csv: String, filename: String) throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        
        return fileURL
    }
    
    // MARK: - Generate Filename
    func generateFilename(prefix: String = "cadence_export") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let timestamp = formatter.string(from: Date())
        return "\(prefix)_\(timestamp).csv"
    }
}