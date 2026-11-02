//
//  JournalEditor.swift
//  Cadence
//
//  Step 3 — one full-screen place to write. Used for:
//    • a new note on a block        .newNote(blockID:)
//    • editing an existing note     .editNote(remarkID:)
//    • a day's intention            .intention(day:)
//    • a day's reflection           .reflection(day:)
//
//  Present with:
//    .fullScreenCover(item: $editorTarget) { JournalEditorView(target: $0) }
//
//  What it does for you:
//    • drafts are kept as you type and restored if the app was closed,
//    • Cancel with changes asks before throwing them away,
//    • #tag suggestions above the keyboard (most-used first, filtered as
//      you type a tag),
//    • saving an edited note empty deletes it (after asking); saving an
//      intention/reflection empty clears it.
//

import SwiftUI
import SwiftData

// MARK: - Target

enum JournalEditorTarget: Identifiable, Hashable {
    case newNote(blockID: UUID)
    case editNote(remarkID: UUID)
    case intention(day: Date)
    case reflection(day: Date)

    var id: String { draftKey }

    /// Stable per thing being written: the same day's intention gets the
    /// same key whatever time it's opened.
    var draftKey: String {
        switch self {
        case .newNote(let blockID):  return "note.new.\(blockID.uuidString)"
        case .editNote(let remarkID): return "note.\(remarkID.uuidString)"
        case .intention(let day):     return "intention.\(Self.dayKey(day))"
        case .reflection(let day):    return "reflection.\(Self.dayKey(day))"
        }
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Editor

struct JournalEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allRemarks: [Remark]

    let target: JournalEditorTarget
    var draftStore = EditorDraftStore()

    @State private var context: EditorContext?
    @State private var text = ""
    @State private var originalText = ""
    @State private var restoredDraft = false
    @State private var showingDiscard = false
    @State private var showingDeleteConfirm = false
    @State private var showingEarlierNotes = false
    @FocusState private var isFocused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasChanges: Bool { trimmed != originalText }
    private var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace }).count }

    private var isEditingExistingNote: Bool {
        if case .editNote = target { return true }
        return false
    }

    /// Tags to offer above the keyboard right now.
    private var tagSuggestions: [String] {
        let known = TagIndex.mostUsed(allRemarks.map(\.tags))
        if let partial = TagCompletion.partialTag(atEndOf: text) {
            return TagCompletion.suggestions(for: partial, from: known)
        }
        return Array(known.prefix(6))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let context {
                    header(context)
                    if let quote = context.quote { quoteBlock(quote) }
                    if !context.earlierNotes.isEmpty { earlierNotes(context.earlierNotes) }
                }

                if restoredDraft { restoredBanner }

                editor

                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .navigationTitle(context?.navigationTitle ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog("Discard your changes?", isPresented: $showingDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { discard() }
                Button("Keep Writing", role: .cancel) { }
            }
            .confirmationDialog("Delete this note?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Note", role: .destructive) { save() }
                Button("Keep Writing", role: .cancel) { }
            } message: {
                Text("You removed all the text. Saving now deletes the note.")
            }
        }
        .onAppear(perform: load)
        .onChange(of: text) { _, newValue in
            guard context != nil else { return }
            // Only a real change is worth keeping as a draft.
            let changed = newValue.trimmingCharacters(in: .whitespacesAndNewlines) != originalText
            draftStore.save(changed ? newValue : "", for: target.draftKey)
        }
    }

    // MARK: - Pieces

    private func header(_ context: EditorContext) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let hex = context.colorHex {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 12, height: 12)
                    .padding(.top, 6)
            } else if let symbol = context.symbol {
                Image(systemName: symbol)
                    .foregroundStyle(context.symbolTint)
                    .padding(.top, 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(context.title)
                    .font(.title3.weight(.semibold))
                if let subtitle = context.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func quoteBlock(_ quote: EditorContext.Quote) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(quote.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(quote.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func earlierNotes(_ notes: [EditorContext.EarlierNote]) -> some View {
        DisclosureGroup(isExpanded: $showingEarlierNotes) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.time)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                            Text(note.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 6)
            }
            .frame(maxHeight: 140)
        } label: {
            Text("\(notes.count) earlier note\(notes.count == 1 ? "" : "s") on this entry")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var restoredBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.counterclockwise.circle")
            Text("Restored your unsaved draft")
            Spacer()
            Button("Revert") {
                text = originalText
                restoredDraft = false
                draftStore.clear(for: target.draftKey)
            }
            .font(.caption.weight(.semibold))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty, let placeholder = context?.placeholder {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .lineSpacing(4)
        }
        .font(.body)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if !originalText.isEmpty && trimmed.isEmpty {
                Label(isEditingExistingNote ? "Saving empty deletes this note" : "Saving empty clears this",
                      systemImage: "eraser")
            }
            Spacer()
            Text("\(wordCount) word\(wordCount == 1 ? "" : "s")")
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.bottom, 6)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if hasChanges { showingDiscard = true } else { discard() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                if isEditingExistingNote && trimmed.isEmpty {
                    showingDeleteConfirm = true
                } else {
                    save()
                }
            }
            .fontWeight(.semibold)
            .disabled(!hasChanges)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Button {
                text = TagCompletion.insertHash(into: text)
            } label: {
                Image(systemName: "number")
            }
            .accessibilityLabel("Insert tag")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tagSuggestions, id: \.self) { tag in
                        Button("#\(tag)") {
                            text = TagCompletion.complete(text, with: tag)
                        }
                        .font(.subheadline)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }
            }

            Button {
                isFocused = false
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
            }
            .accessibilityLabel("Hide keyboard")
        }
    }

    // MARK: - Load / save

    private func load() {
        guard context == nil else { return }   // onAppear can fire again after a dialog

        let stored: String
        switch target {
        case .newNote(let blockID):
            stored = ""
            context = EditorContext.note(block: blockByID(blockID),
                                         earlier: RemarkStore.notes(forBlock: blockID, in: modelContext),
                                         isNew: true, writtenAt: nil)
        case .editNote(let remarkID):
            guard let remark = RemarkStore.note(withID: remarkID, in: modelContext) else {
                dismiss(); return
            }
            stored = remark.text
            let others = RemarkStore.notes(forBlock: remark.timeBlockID, in: modelContext)
                .filter { $0.id != remarkID }
            context = EditorContext.note(block: blockByID(remark.timeBlockID), earlier: others,
                                         isNew: false, writtenAt: remark.timestamp)
        case .intention(let day):
            let note = DayNoteStore.note(for: day, in: modelContext)
            stored = note?.intention ?? ""
            context = EditorContext.intention(day: day)
        case .reflection(let day):
            let note = DayNoteStore.note(for: day, in: modelContext)
            stored = note?.reflection ?? ""
            context = EditorContext.reflection(day: day, intention: note?.intention ?? "",
                                               summary: DayPageFetch.page(for: day, in: modelContext).summary)
        }

        originalText = stored
        if let draft = draftStore.draft(for: target.draftKey),
           draft.trimmingCharacters(in: .whitespacesAndNewlines) != stored {
            text = draft
            restoredDraft = true
        } else {
            text = stored
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { isFocused = true }
    }

    private func save() {
        switch target {
        case .newNote(let blockID):
            RemarkStore.addNote(text, toBlock: blockID, in: modelContext)
        case .editNote(let remarkID):
            if let remark = RemarkStore.note(withID: remarkID, in: modelContext) {
                RemarkStore.updateNote(remark, text: text, in: modelContext)
            }
        case .intention(let day):
            DayNoteStore.setIntention(text, for: day, in: modelContext)
        case .reflection(let day):
            DayNoteStore.setReflection(text, for: day, in: modelContext)
        }
        draftStore.clear(for: target.draftKey)
        dismiss()
    }

    private func discard() {
        draftStore.clear(for: target.draftKey)
        dismiss()
    }

    private func blockByID(_ id: UUID) -> TimeBlock? {
        var descriptor = FetchDescriptor<TimeBlock>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

// MARK: - Editor context (what the header says)

/// Everything the editor shows around the text, worked out once on open.
struct EditorContext {
    struct Quote { let label: String; let text: String }
    struct EarlierNote: Identifiable { let id: UUID; let time: String; let text: String }

    var navigationTitle: String
    var title: String
    var subtitle: String?
    var colorHex: String?
    var symbol: String?
    var symbolTint: Color = .secondary
    var placeholder: String
    var quote: Quote?
    var earlierNotes: [EarlierNote] = []

    private static let time = Date.FormatStyle(date: .omitted, time: .shortened)

    static func dayLabel(_ day: Date) -> String {
        Calendar.current.isDateInToday(day) ? "Today" : day.formatted(date: .complete, time: .omitted)
    }

    static func note(block: TimeBlock?, earlier: [Remark], isNew: Bool, writtenAt: Date?) -> EditorContext {
        var subtitle: String?
        if let block {
            let start = block.startTime.formatted(time)
            if let end = block.endTime {
                subtitle = "\(start)–\(end.formatted(time)) · \(block.duration.formattedDuration)"
            } else {
                subtitle = "Since \(start) · running"
            }
            if !Calendar.current.isDateInToday(block.startTime) {
                subtitle = "\(block.startTime.formatted(date: .abbreviated, time: .omitted)) · " + (subtitle ?? "")
            }
        }
        if let writtenAt {
            subtitle = (subtitle.map { $0 + "\n" } ?? "") + "Written \(writtenAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return EditorContext(
            navigationTitle: isNew ? "New Note" : "Edit Note",
            title: block?.activityName ?? "Note",
            subtitle: subtitle,
            colorHex: block?.activityColor,
            placeholder: "What happened? Use #tags to group notes.",
            earlierNotes: earlier.map {
                EarlierNote(id: $0.id, time: $0.timestamp.formatted(time), text: $0.text)
            }
        )
    }

    static func intention(day: Date) -> EditorContext {
        EditorContext(
            navigationTitle: "Intention",
            title: "What do you want from today?",
            subtitle: dayLabel(day),
            symbol: "sun.horizon.fill",
            symbolTint: .orange,
            placeholder: "One thing that would make today a good day…"
        )
    }

    /// `summary`: "6h 20m logged · mostly Meetings · 3 notes", shown under the day.
    static func reflection(day: Date, intention: String, summary: String? = nil) -> EditorContext {
        EditorContext(
            navigationTitle: "Reflection",
            title: "How did it go?",
            subtitle: [dayLabel(day), summary].compactMap { $0 }.joined(separator: "\n"),
            symbol: "moon.stars.fill",
            symbolTint: .indigo,
            placeholder: "What worked, what didn't, what you'd do differently…",
            quote: intention.isEmpty ? nil : Quote(label: "Your intention", text: intention)
        )
    }
}
