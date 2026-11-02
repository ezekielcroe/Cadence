//
//  DayPageViews.swift
//  Cadence
//
//  The pieces a day page is made of, shared by Today and the Journal:
//
//    DiaryEntryRow   an entry with its notes in full (Diary)
//    LedgerEntryRow  a compact entry row (Ledger), selectable
//    BlankTimeRow    the time between entries: quiet in Diary,
//                    "unlogged · Fill" with accountability or in Ledger
//    BookendRow      the day's intention / reflection
//    DayHeaderView   "Yesterday" + one-line summary
//    UndoToast       "Deleted Meetings · Undo"
//
//  Gestures are deliberately few: tap opens, swipe deletes (in lists),
//  and a long-press menu holds everything else.
//

import SwiftUI
import SwiftData

// MARK: - Navigation

/// Pushes an entry page: `.navigationDestination(for: EntryRoute.self)`.
struct EntryRoute: Hashable {
    let blockID: UUID
}

// MARK: - Actions

/// What a day page can ask its screen to do. Today and the Journal each
/// supply their own (e.g. Today also refreshes the timer's anchor).
struct DayPageActions {
    var open: (TimeBlock) -> Void
    var addNote: (TimeBlock) -> Void
    var editNote: (Remark) -> Void
    var editTimes: (TimeBlock) -> Void
    var delete: (TimeBlock) -> Void
    var fill: (ComputedGap) -> Void
    var editIntention: (Date) -> Void
    var editReflection: (Date) -> Void
}

// MARK: - Labels

enum DayLabel {
    static func text(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static let time = Date.FormatStyle(date: .omitted, time: .shortened)
}

// MARK: - Shared bits

private struct TimeGutter: View {
    let date: Date
    var muted = false

    var body: some View {
        Text(date.formatted(DayLabel.time))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(muted ? .quaternary : .secondary)
            .frame(width: 52, alignment: .trailing)
            .padding(.top, 2)
    }
}

private struct ColorRail: View {
    let hex: String

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color(hex: hex))
            .frame(width: 3)
            .padding(.horizontal, 8)
    }
}

private struct DashedRail: View {
    var body: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(.secondary.opacity(0.25))
            .frame(width: 1)
            .padding(.horizontal, 9)
    }
}

// MARK: - Diary entry

struct DiaryEntryRow: View {
    let entry: DayPage.Entry
    let onOpen: () -> Void
    let onAddNote: () -> Void
    let onEditNote: (Remark) -> Void
    /// nil hides the action (e.g. for a running timer).
    var onEditTimes: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            TimeGutter(date: entry.clip.start)
            ColorRail(hex: entry.block.activityColor)

            VStack(alignment: .leading, spacing: 6) {
                Button(action: onOpen) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.block.activityName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if entry.isRunning {
                            Text("running")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Spacer(minLength: 8)
                        Text(entry.duration.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if entry.startsBeforeDay {
                    Text("Continues from the day before")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ForEach(entry.notes) { note in
                    Button { onEditNote(note) } label: {
                        Text(note.text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit note")
                }

                Button(action: onAddNote) {
                    Label(entry.notes.isEmpty ? "Add a note" : "Add another", systemImage: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 4)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: onOpen) { Label("Open Entry", systemImage: "doc.text") }
            Button(action: onAddNote) { Label("Add Note", systemImage: "square.and.pencil") }
            if let onEditTimes {
                Button(action: onEditTimes) { Label("Edit Times & Activity", systemImage: "slider.horizontal.3") }
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) { Label("Delete Entry", systemImage: "trash") }
            }
        }
    }
}

// MARK: - Ledger entry

struct LedgerEntryRow: View {
    let entry: DayPage.Entry
    var isSelecting = false
    var isSelected = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .opacity(entry.isRunning ? 0.3 : 1)
                    .padding(.leading, 8)
                    .padding(.top, 1)
            }
            TimeGutter(date: entry.clip.start)
            ColorRail(hex: entry.block.activityColor)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.block.activityName)
                        .font(.subheadline.weight(.medium))
                    if !entry.notes.isEmpty {
                        Label("\(entry.notes.count)", systemImage: "text.bubble")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                    if entry.isRunning {
                        Text("running").font(.caption2).foregroundStyle(.green)
                    }
                    Spacer()
                    Text(entry.duration.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                let tags = entry.tags
                if !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags.prefix(4), id: \.self) { tag in
                            Text("#\(tag)").font(.caption2).foregroundStyle(.blue.opacity(0.7))
                        }
                        if tags.count > 4 {
                            Text("+\(tags.count - 4)").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

// MARK: - Blank time

struct BlankTimeRow: View {
    let gap: ComputedGap
    /// true: "47m unlogged · Fill" (accountability on, or the Ledger).
    /// false: just a quiet "47m".
    let emphasised: Bool
    let onFill: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            TimeGutter(date: gap.start, muted: true)
            DashedRail()
            HStack(spacing: 6) {
                if emphasised {
                    Text("\(gap.duration.formattedDuration) unlogged")
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.85))
                    Spacer()
                    Text("Fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                } else {
                    Text(gap.duration.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .monospacedDigit()
        }
        .padding(.vertical, emphasised ? 6 : 3)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFill)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Log what you did in this time")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Intention / reflection

enum BookendKind {
    case intention, reflection

    var icon: String { self == .intention ? "sun.horizon.fill" : "moon.stars.fill" }
    var emptyIcon: String { self == .intention ? "sun.horizon" : "moon.stars" }
    var tint: Color { self == .intention ? .orange : .indigo }
    var label: String { self == .intention ? "Intention" : "Reflection" }
}

struct BookendRow: View {
    let kind: BookendKind
    /// nil or empty shows the placeholder.
    let text: String?
    var placeholder: String? = nil
    var compact = false
    let onTap: () -> Void

    private var hasText: Bool { !(text ?? "").isEmpty }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: hasText ? kind.icon : kind.emptyIcon)
                    .foregroundStyle(kind.tint.opacity(hasText ? 0.8 : 0.4))
                    .font(.subheadline)
                    .frame(width: 20)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    if hasText {
                        Text(kind.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(kind.tint.opacity(0.8))
                        Text(text ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(compact ? 2 : nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: !compact)
                    } else if let placeholder {
                        Text(placeholder)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Day header

struct DayHeaderView: View {
    let day: Date
    let summary: String?
    /// Shown only when accountability is on.
    var gapCount: Int? = nil
    /// Overrides "Today" / "Yesterday" / the date.
    var title: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title ?? DayLabel.text(for: day))
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                if let summary {
                    Text(summary)
                }
                if let gapCount, gapCount > 0 {
                    Text("· \(gapCount) unlogged")
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Undo toast

struct UndoToast: View {
    let label: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text(label)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
