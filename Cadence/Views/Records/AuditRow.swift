//
//  AuditRow.swift
//  Cadence
//
//  Single row in the audit list
//

import SwiftUI

// MARK: - Audit Row (Updated with editability indicator)

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
                // Selection checkbox (when in selection mode)
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .blue : .secondary)
                        .font(.title3)
                }
                
                // Color indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(block.activityColor))
                    .frame(width: 4, height: 44)
                
                // Main content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(block.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        
                        if block.isGap {
                            GapBadge()
                        } else if block.isPauseBlock {
                            PauseBadge()
                        }
                        
                        Spacer()
                        
                        Text(block.duration.formattedDuration)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    
                    HStack {
                        Text(timeRange)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        
                        if block.endTime == nil {
                            Text("ACTIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                        
                        if !isEditable {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        
                        Spacer()
                        
                        if !block.remarks.isEmpty {
                            Image(systemName: "note.text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Action indicator
                if !isSelectionMode {
                    if block.isGap && isEditable {
                        Button(action: onResolveGap) {
                            Text("Resolve")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.orange)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(rowBackground)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var rowBackground: Color {
        if isSelected {
            return Color.blue.opacity(0.1)
        } else if block.isGap {
            return Color.orange.opacity(0.05)
        }
        return Color.clear
    }
}

// MARK: - Supporting Views

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
        .foregroundStyle(.gray)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.gray.opacity(0.15))
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
