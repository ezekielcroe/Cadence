//
//  ComputedGapRow.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 13/2/26.
//


// ComputedGapRow.swift
// Cadence
//
// Renders a computed gap inline between activity rows in the RecordsView timeline.
// This replaces the old AuditRow rendering for gap TimeBlocks.

import SwiftUI

struct ComputedGapRow: View {
    let gap: ComputedGap
    let onResolve: () -> Void

    private var timeRange: String {
        "\(gap.start.formatted(date: .omitted, time: .shortened)) → \(gap.end.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Visual indicator — dashed to signal "missing"
            Rectangle()
                .fill(Color.orange.opacity(0.4))
                .frame(width: 4, height: 36)
                .overlay(
                    Rectangle()
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [4]))
                        .foregroundStyle(Color.orange)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    GapBadge()
                    Text(timeRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(gap.duration.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button("Resolve") { onResolve() }
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange)
                .cornerRadius(12)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.orange.opacity(0.05))
        .contentShape(Rectangle())
    }
}

// MARK: - Previews

#Preview("ComputedGapRow") {
    let gap = ComputedGap(
        start: Date().addingTimeInterval(-2700),
        end:   Date().addingTimeInterval(-900)
    )
    return List {
        ComputedGapRow(gap: gap, onResolve: {})
    }
}
