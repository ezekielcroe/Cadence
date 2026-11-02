// AuditRow.swift
// Cadence
//
// REFACTORED: Adds inline time editing via long-press on time range (Fix #1).
// Shows +5m/-5m/+15m/-15m nudge buttons directly in the row, eliminating
// the need to open a sheet for simple time adjustments.

import SwiftUI
import SwiftData

struct AuditRow: View {
    @Environment(\.modelContext) private var modelContext

    let block: TimeBlock
    let remarks: [Remark]
    let isSelected: Bool
    let isSelectionMode: Bool
    let isEditable: Bool
    let onTap: () -> Void

    // Inline time editing state (Fix #1)
    @State private var showTimeNudge = false

    private var timeRange: String {
        let start = block.startTime.formatted(date: .omitted, time: .shortened)
        if let end = block.endTime {
            return "\(start) → \(end.formatted(date: .omitted, time: .shortened))"
        }
        return "\(start) → now"
    }

    private var firstRemark: Remark? {
        remarks.sorted { $0.timestamp < $1.timestamp }.first
    }

    private var allTags: [String] {
        Array(Set(remarks.flatMap { $0.tags })).sorted()
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Main row content
                HStack(spacing: 12) {
                    if isSelectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? .blue : .secondary)
                            .font(.title3)
                    }

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: block.activityColor))
                        .frame(width: 4, height: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(block.activityName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        // Time range — tappable for inline edit (Fix #1)
                        Text(timeRange)
                            .font(.subheadline)
                            .foregroundStyle(showTimeNudge ? .blue : .secondary)
                            .onTapGesture {
                                guard isEditable, !isSelectionMode, block.endTime != nil else { return }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showTimeNudge.toggle()
                                }
                            }

                        if block.pauseCount > 0 {
                            Label(
                                "\(block.pauseCount) pause\(block.pauseCount == 1 ? "" : "s") · \(block.pauseDuration.formattedDuration) total",
                                systemImage: "pause.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        // First remark preview
                        if let remark = firstRemark {
                            Text(remark.preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        // Tag chips (max 3 visible)
                        if !allTags.isEmpty {
                            TagChipRow(tags: allTags)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(block.duration.formattedDuration)
                            .font(.subheadline)
                            .monospacedDigit()
                            .fontWeight(.medium)

                        if remarks.count > 0 {
                            Label("\(remarks.count)", systemImage: "note.text")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)

                // MARK: Inline Time Nudge Buttons (Fix #1)
                if showTimeNudge && block.endTime != nil {
                    timeNudgeBar
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Time Nudge Bar (Fix #1)

    private var timeNudgeBar: some View {
        VStack(spacing: 8) {
            Divider()

            // Start time nudges
            HStack(spacing: 6) {
                Text("Start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 36)

                ForEach([-15, -5, 5, 15], id: \.self) { minutes in
                    Button {
                        nudgeStartTime(by: TimeInterval(minutes * 60))
                    } label: {
                        Text(minutes > 0 ? "+\(minutes)m" : "\(minutes)m")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            // End time nudges
            HStack(spacing: 6) {
                Text("End")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 36)

                ForEach([-15, -5, 5, 15], id: \.self) { minutes in
                    Button {
                        nudgeEndTime(by: TimeInterval(minutes * 60))
                    } label: {
                        Text(minutes > 0 ? "+\(minutes)m" : "\(minutes)m")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Close nudge bar
                Button {
                    withAnimation { showTimeNudge = false }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    // MARK: - Nudge Actions

    private func nudgeStartTime(by interval: TimeInterval) {
        let newStart = block.startTime.addingTimeInterval(interval)

        // Guard: start can't be after end
        guard let endTime = block.endTime, newStart < endTime else { return }
        // Guard: minimum 1-minute block
        guard endTime.timeIntervalSince(newStart) >= 60 else { return }

        block.startTime = newStart
        try? modelContext.save()
        HistoryManager.shared.invalidate(block: block, in: modelContext)
    }

    private func nudgeEndTime(by interval: TimeInterval) {
        guard let endTime = block.endTime else { return }
        let newEnd = endTime.addingTimeInterval(interval)

        // Guard: end can't be before start
        guard newEnd > block.startTime else { return }
        // Guard: minimum 1-minute block
        guard newEnd.timeIntervalSince(block.startTime) >= 60 else { return }

        block.endTime = newEnd
        try? modelContext.save()
        HistoryManager.shared.invalidate(block: block, in: modelContext)
    }
}

// MARK: - Tag Chip Row (shared component)

struct TagChipRow: View {
    let tags: [String]
    var maxVisible: Int = 3
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
            if tags.count > maxVisible {
                Text("+\(tags.count - maxVisible)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Gap Badge (kept from original)

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
