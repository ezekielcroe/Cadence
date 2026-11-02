//
//  LogReceiptViews.swift
//  Cadence
//
//  Step 1 — what you see right after a tap:
//    • LogReceiptBanner: bottom card for 10s — Undo · Change · Add note
//    • LastLoggedRow:    afterwards, inside the unlabeled-time card —
//                        "Last: Meetings · 47m" with Add note / Change
//    • RelabelActivitySheet: "Change" — relabel without touching times
//    • TimerReceiptBanner: after starting/switching a live timer — Undo
//

import SwiftUI
import SwiftData

// MARK: - Shared label

/// "● Meetings  10:13–11:00 · 47m"
struct LoggedBlockLabel: View {
    let snapshot: LoggedBlockSnapshot
    var prominent = false

    private var timeRange: String {
        let f = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(snapshot.start.formatted(f))–\(snapshot.end.formatted(f))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: snapshot.activityColor))
                .frame(width: prominent ? 12 : 9, height: prominent ? 12 : 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.activityName)
                    .font(prominent ? Font.subheadline.weight(.semibold) : Font.subheadline)
                    .lineLimit(1)
                Text("\(timeRange) · \(snapshot.duration.formattedDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Post-tap banner

struct LogReceiptBanner: View {
    let receipt: LogReceipt
    let onUndo: () -> Void
    let onChange: () -> Void
    let onAddNote: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label("Logged", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            LoggedBlockLabel(snapshot: receipt.block, prominent: true)

            HStack(spacing: 8) {
                Button(action: onUndo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onChange) {
                    Label("Change", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onAddNote) {
                    Label("Note", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.subheadline.weight(.medium))
            .labelStyle(.titleAndIcon)

            UndoCountdownBar(deadline: receipt.undoDeadline, window: LogReceipt.undoWindow)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - Post-start banner (live timer)

/// "▶ Timer started · ● Focused Work" or "⇄ Switched from Meetings" with Undo.
struct TimerReceiptBanner: View {
    let receipt: TimerReceipt
    let onUndo: () -> Void
    let onDismiss: () -> Void

    private var title: String {
        if let replaced = receipt.replaced { return "Switched from \(replaced.activityName)" }
        return "Timer started"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: receipt.replaced == nil ? "play.circle.fill" : "arrow.left.arrow.right.circle.fill")
                    .foregroundStyle(Color(hex: receipt.activityColor))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(receipt.activityName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onUndo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            if receipt.unlabeledBefore >= 60 {
                Text("The \(receipt.unlabeledBefore.formattedDuration) before it stays blank")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            UndoCountdownBar(deadline: receipt.undoDeadline, window: LogReceipt.undoWindow)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

/// A thin bar that empties as the Undo window runs out.
private struct UndoCountdownBar: View {
    let deadline: Date
    let window: TimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            let remaining = max(0, deadline.timeIntervalSince(context.date))
            GeometryReader { geo in
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: geo.size.width * remaining / window)
                    }
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - "Last: …" row (after the banner is gone)

struct LastLoggedRow: View {
    let snapshot: LoggedBlockSnapshot
    let onAddNote: () -> Void
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Last")
                .font(.caption)
                .foregroundStyle(.secondary)
            LoggedBlockLabel(snapshot: snapshot)
            Spacer(minLength: 4)
            Button(action: onChange) {
                Image(systemName: "arrow.left.arrow.right")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Change activity of \(snapshot.activityName)")

            Button(action: onAddNote) {
                Image(systemName: "square.and.pencil")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.blue)
            .accessibilityLabel("Add note to \(snapshot.activityName)")
        }
        .padding(10)
        .background(Color(.systemBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Change activity

/// "Change": relabel an entry without touching its times. Uses the same
/// picker as Edit Block (grouped by set, searchable), without "None".
struct RelabelActivitySheet: View {
    @Query private var activities: [Activity]
    @Query private var activitySets: [ActivitySet]

    let currentActivityID: UUID?
    let onPick: (Activity) -> Void

    var body: some View {
        ActivityPickerSheet(
            activities: activities,
            activitySets: activitySets,
            selectedActivityID: Binding(
                get: { currentActivityID },
                set: { id in
                    if let id, id != currentActivityID,
                       let activity = activities.first(where: { $0.id == id }) {
                        onPick(activity)
                    }
                }
            ),
            allowsNone: false
        )
    }
}
