// AuditRow.swift
// Cadence
//

import SwiftUI

struct AuditRow: View {
    let block: TimeBlock
    let isSelected: Bool
    let isSelectionMode: Bool
    let isEditable: Bool
    let onTap: () -> Void

    private var timeRange: String {
        let start = block.startTime.formatted(date: .omitted, time: .shortened)
        if let end = block.endTime {
            return "\(start) → \(end.formatted(date: .omitted, time: .shortened))"
        }
        return "\(start) → now"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection checkbox
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .blue : .secondary)
                        .font(.title3)
                }

                // Activity color bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: block.activityColor))
                    .frame(width: 4, height: 44)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.activityName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(timeRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Pause summary (only shown if pauses occurred)
                    if block.pauseCount > 0 {
                        Label(
                            "\(block.pauseCount) pause\(block.pauseCount == 1 ? "" : "s") · \(block.totalPauseDuration.formattedDuration) total",
                            systemImage: "pause.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if !block.remarks.isEmpty {
                        Text(block.remarks)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Duration
                Text(block.duration.formattedDuration)
                    .font(.subheadline)
                    .monospacedDigit()
                    .fontWeight(.medium)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Badges (kept for potential future use)

struct GapBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text("GAP")
                .font(.caption2)
                .fontWeight(.bold)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(4)
    }
}

#Preview {
    let block = TimeBlock(
        activityID: UUID(),
        activityName: "Deep Work",
        activityColor: "#4CAF50",
        activitySetID: UUID(),
        startTime: Date().addingTimeInterval(-3600)
    )
    block.endTime = Date()
    block.pauseCount = 2
    block.totalPauseDuration = 480
    block.remarks = "[10:22] Finished the auth PR"

    return List {
        AuditRow(
            block: block,
            isSelected: false,
            isSelectionMode: false,
            isEditable: true,
            onTap: {}
        )
    }
}
