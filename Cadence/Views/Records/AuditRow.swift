//
//  AuditRow.swift
//  Cadence
//
//  Single row in the audit list
//

import SwiftUI

struct AuditRow: View {
    let block: TimeBlock
    let isSelected: Bool
    let isSelectionMode: Bool
    let isEditable: Bool
    let onTap: () -> Void
    let onResolveGap: () -> Void
    
    private var timeRange: String {
        let start = block.startTime.formatted(date: .omitted, time: .shortened)
        if let end = block.endTime {
            let endStr = end.formatted(date: .omitted, time: .shortened)
            return "\(start) → \(endStr)"
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
                
                // Color indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: block.activityColor))
                    .frame(width: 4, height: 44)
                
                // Main content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(block.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        if block.isGap {
                            GapBadge()
                        } else if block.isPauseBlock {
                            PauseBadge()
                        } else if block.isUntrackedBlock {
                            UntrackedBadge()
                        }
                    }
                    
                    Text(timeRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    if !block.remarks.isEmpty {
                        Text(block.remarks)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Duration & Action
                VStack(alignment: .trailing, spacing: 4) {
                    Text(block.duration.formattedDuration)
                        .font(.subheadline)
                        .monospacedDigit()
                        .fontWeight(.medium)
                    
                    if block.isGap && isEditable {
                        Button("Resolve") {
                            onResolveGap()
                        }
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Badges

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

struct PauseBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "pause.fill")
                .font(.caption2)
            Text("PAUSE")
                .font(.caption2)
                .fontWeight(.bold)
        }
        .foregroundStyle(.gray) // Neutral color
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(4)
    }
}

struct UntrackedBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.slash.fill")
                .font(.caption2)
            Text("OFF")
                .font(.caption2)
                .fontWeight(.bold)
        }
        .foregroundStyle(Color(hex: "#9E9E9E"))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(hex: "#9E9E9E").opacity(0.15))
        .cornerRadius(4)
    }
}

#Preview {
    let block = TimeBlock(
        activityID: UUID(),
        activityName: "Deep Work",
        activityColor: "#4CAF50",
        activitySetID: UUID(),
        startTime: Date().addingTimeInterval(-3600),
        blockType: "activity"
    )
    block.endTime = Date()
    
    let gap = TimeBlock.createGap(
        startTime: Date().addingTimeInterval(-1800),
        endTime: Date()
    )
    
    return VStack {
        AuditRow(
            block: block,
            isSelected: false,
            isSelectionMode: false,
            isEditable: true,
            onTap: {},
            onResolveGap: {}
        )
        
        AuditRow(
            block: gap,
            isSelected: false,
            isSelectionMode: false,
            isEditable: true,
            onTap: {},
            onResolveGap: {}
        )
    }
    .padding()
}
