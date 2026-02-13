import SwiftUI

struct AuditRow: View {
    let block: TimeBlock
    let remarks: [Remark]     // pre-fetched by RecordsView, filtered to this block
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

    private var firstRemark: Remark? {
        remarks.sorted { $0.timestamp < $1.timestamp }.first
    }

    private var allTags: [String] {
        Array(Set(remarks.flatMap { $0.tags })).sorted()
    }

    var body: some View {
        Button(action: onTap) {
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

                    Text(timeRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if block.pauseCount > 0 {
                        Label(
                            "\(block.pauseCount) pause\(block.pauseCount == 1 ? "" : "s") · \(block.totalPauseDuration.formattedDuration) total",
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
                        HStack(spacing: 4) {
                            ForEach(allTags.prefix(3), id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.08))
                                    .cornerRadius(4)
                            }
                            if allTags.count > 3 {
                                Text("+\(allTags.count - 3)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Kept for potential future use
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
