//
//  EntryDetailView.swift
//  Cadence
//
//  The page for one entry, pushed from Today, the Journal or search:
//  what it was, when, its notes in full (tap to edit, swipe to delete),
//  and the editing actions that used to be hidden behind long-presses.
//

import SwiftUI
import SwiftData

struct EntryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var blocks: [TimeBlock]
    @Query private var notes: [Remark]

    @State private var editorTarget: JournalEditorTarget?
    @State private var editingBlock: TimeBlock?
    @State private var showingDeleteConfirm = false

    let blockID: UUID

    init(blockID: UUID) {
        self.blockID = blockID
        _blocks = Query(filter: #Predicate<TimeBlock> { $0.id == blockID })
        _notes = Query(filter: #Predicate<Remark> { $0.timeBlockID == blockID },
                       sort: \.timestamp)
    }

    var body: some View {
        Group {
            if let block = blocks.first {
                content(block)
            } else {
                ContentUnavailableView("Entry Deleted", systemImage: "trash",
                                       description: Text("This entry no longer exists."))
            }
        }
        .navigationTitle(blocks.first?.activityName ?? "Entry")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $editorTarget) { target in
            JournalEditorView(target: target)
        }
        .sheet(item: $editingBlock) { block in
            QuickEditSheet(block: block,
                           conflictDetector: ConflictDetector(modelContext: modelContext),
                           onSave: { try? modelContext.save() })
        }
        .confirmationDialog("Delete this entry?", isPresented: $showingDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete Entry", role: .destructive) {
                if let block = blocks.first {
                    BlockDeletion.delete(block, in: modelContext)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(notes.isEmpty
                 ? "The time becomes blank again."
                 : "Its \(notes.count) note\(notes.count == 1 ? "" : "s") will be deleted too. The time becomes blank again.")
        }
    }

    // MARK: - Content

    private func content(_ block: TimeBlock) -> some View {
        List {
            Section {
                header(block)
            }

            Section("Notes") {
                ForEach(notes) { note in
                    Button {
                        editorTarget = .editNote(remarkID: note.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.text)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Text("Written \(note.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            RemarkStore.deleteNote(note, in: modelContext)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button {
                    editorTarget = .newNote(blockID: block.id)
                } label: {
                    Label(notes.isEmpty ? "Add a note" : "Add another note", systemImage: "square.and.pencil")
                }
            }

            Section {
                if BlockDeletion.canDelete(block) {
                    Button {
                        editingBlock = block
                    } label: {
                        Label("Edit Times & Activity", systemImage: "slider.horizontal.3")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Entry", systemImage: "trash")
                    }
                } else {
                    Label("This timer is still running. Stop it on the Today tab to edit it.",
                          systemImage: "timer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if BlockDeletion.canDelete(block) {
                    Text("Edit Times & Activity also lets you split this entry in two.")
                }
            }
        }
    }

    private func header(_ block: TimeBlock) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(hex: block.activityColor))
                .frame(width: 14, height: 14)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(block.activityName)
                    .font(.title3.weight(.semibold))
                Text(block.startTime.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(timeRange(block))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if block.pauseCount > 0 {
                    Text("Paused \(block.pauseCount)× · \(block.pauseDuration.formattedDuration) in total")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func timeRange(_ block: TimeBlock) -> String {
        let start = block.startTime.formatted(DayLabel.time)
        guard let end = block.endTime else {
            return "Since \(start) · running · \(block.duration.formattedDuration)"
        }
        let crossesDay = !Calendar.current.isDate(block.startTime, inSameDayAs: end)
        let endText = crossesDay ? end.formatted(date: .abbreviated, time: .shortened) : end.formatted(DayLabel.time)
        return "\(start)–\(endText) · \(block.duration.formattedDuration)"
    }
}
