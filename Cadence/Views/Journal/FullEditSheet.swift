// FullEditSheet.swift
// Cadence
//
// FIX #6: The full editor, opened from QuickEditSheet → "More Options".
// Contains: remarks management, split block, pause info, metadata.
// Time/Activity editing is handled in QuickEditSheet.

import SwiftUI
import SwiftData

struct FullEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var block: TimeBlock
    let conflictDetector: ConflictDetector
    let onSave: () -> Void

    @Query private var activities: [Activity]
    @Query private var blockRemarks: [Remark]

    // Inline new-remark state
    @State private var newRemarkText = ""
    @FocusState private var remarkFieldFocused: Bool

    // UI state
    @State private var showingSplitSheet = false
    
    init(block: TimeBlock, conflictDetector: ConflictDetector, onSave: @escaping () -> Void) {
        self.block = block
        self.conflictDetector = conflictDetector
        self.onSave = onSave

        let blockID = block.id
        _blockRemarks = Query(
            filter: #Predicate<Remark> { $0.timeBlockID == blockID },
            sort: \.timestamp
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Block Info (read-only summary)
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: block.activityColor))
                            .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(block.activityName)
                                .font(.headline)
                            Text(
                                "\(block.startTime.formatted(date: .abbreviated, time: .shortened))" +
                                " → " +
                                "\((block.endTime ?? Date()).formatted(date: .omitted, time: .shortened))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(block.duration.formattedDuration)
                            .font(.title3)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                }

                // Pause Metadata
                if block.pauseCount > 0 {
                    Section("Pauses") {
                        HStack {
                            Label("Pause Count", systemImage: "pause.circle")
                            Spacer()
                            Text("\(block.pauseCount)")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Label("Total Paused", systemImage: "clock.badge.xmark")
                            Spacer()
                            Text(block.totalPauseDuration.formattedDuration)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                // Stop State
                Section("Status") {
                    HStack {
                        Label("Stop State", systemImage: stopStateIcon)
                        Spacer()
                        Text(block.stopState.capitalized)
                            .foregroundStyle(.secondary)
                    }
                    if block.switchCount > 0 {
                        HStack {
                            Label("Switches", systemImage: "arrow.left.arrow.right")
                            Spacer()
                            Text("\(block.switchCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: - Remarks Section
                Section {
                    if blockRemarks.isEmpty {
                        Text("No remarks yet")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(blockRemarks) { remark in
                            RemarkRow(remark: remark) {
                                deleteRemark(remark)
                            }
                        }
                    }

                    // Inline add field
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.secondary)
                            .font(.body)
                            .padding(.top, 2)

                        TextField("Add a remark… (#tags supported)", text: $newRemarkText, axis: .vertical)
                            .focused($remarkFieldFocused)
                            .lineLimit(1...6)
                            .submitLabel(.done)
                            .onSubmit { addRemark() }

                        if !newRemarkText.isEmpty {
                            Button("Add") { addRemark() }
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                } header: {
                    HStack {
                        Text("Remarks")
                        Spacer()
                        Text("\(blockRemarks.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if blockRemarks.isEmpty {
                        Text("Use #tags to create searchable categories")
                    }
                }

                // MARK: - Actions
                Section("Actions") {
                    Button("Split This Block…") { showingSplitSheet = true }
                        .disabled(block.duration < 120)

                    // Block ID for debugging / advanced use
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Block ID")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(block.id.uuidString)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }

                        if let activityID = block.activityID {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Activity ID")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(activityID.uuidString)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .textSelection(.enabled)
                            }
                        }
                    } label: {
                        Label("Technical Details", systemImage: "info.circle")
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Full Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingSplitSheet) {
                SplitBlockSheet(block: block, onSplit: { onSave() })
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Helpers

    private var stopStateIcon: String {
        switch block.stopState {
        case "switched": return "arrow.right.circle"
        case "stopped":  return "stop.circle"
        default:         return "circle"
        }
    }

    // MARK: - Actions

    private func addRemark() {
        let trimmed = newRemarkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let remark = Remark(timeBlockID: block.id, text: trimmed)
        modelContext.insert(remark)
        try? modelContext.save()
        newRemarkText = ""
        remarkFieldFocused = false
    }

    private func deleteRemark(_ remark: Remark) {
        modelContext.delete(remark)
        try? modelContext.save()
    }
}

// MARK: - RemarkRow

struct RemarkRow: View {
    let remark: Remark
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(remark.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
            }

            Text(remark.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !remark.tags.isEmpty {
                TagChipRow(tags: remark.tags)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
