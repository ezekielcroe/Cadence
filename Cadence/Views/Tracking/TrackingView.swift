//
//  TrackingView.swift
//  Cadence
//
//  STEP 4: the Timer tab became the Today tab (Views/Today/TodayView.swift).
//  This file now holds the tracking components Today is built from:
//  the "since…" counter card, the live timer card, the long-span confirm
//  sheet, intention banner, activity buttons and the set picker.
//  (Feel free to rename it TrackingComponents.swift in Xcode.)
//

import SwiftUI
import SwiftData
import Combine

// MARK: - Retrospective Card

/// "23m since Meetings": the time you haven't logged yet, counting from
/// the end of your last entry (or from a Leave blank).
struct RetrospectiveCard: View {
    let anchor: Date
    let unlabeledDuration: TimeInterval
    /// The activity the counter runs from, when it runs from an entry.
    let sinceActivityName: String?
    /// Shown as "Last: …" when the post-tap banner isn't on screen.
    let lastLogged: LoggedBlockSnapshot?
    let onLeaveBlank: () -> Void
    let onAddNote: (LoggedBlockSnapshot) -> Void
    let onChange: (LoggedBlockSnapshot) -> Void

    private var anchorLabel: String {
        let cal = Calendar.current
        let time = anchor.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(anchor)     { return "since \(time)" }
        if cal.isDateInYesterday(anchor) { return "since yesterday \(time)" }
        return "since \(anchor.formatted(date: .abbreviated, time: .shortened))"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text(sinceActivityName.map { "Since \($0)" } ?? "Not logged yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(anchorLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(unlabeledDuration.formattedDuration)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text("Tap an activity to log this time · hold one to start a timer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let last = lastLogged {
                LastLoggedRow(
                    snapshot: last,
                    onAddNote: { onAddNote(last) },
                    onChange:  { onChange(last) }
                )
                .padding(.top, 4)
            }

            Button(action: onLeaveBlank) {
                Label("Leave Blank", systemImage: "circle.dashed")
                    .font(.subheadline).fontWeight(.medium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

// MARK: - Label Confirm Sheet (long spans)

struct LabelConfirmSheet: View {
    let pending: PendingLabel
    @ObservedObject var manager: TimeTrackingManager

    @State private var start: Date

    init(pending: PendingLabel, manager: TimeTrackingManager) {
        self.pending = pending
        self.manager = manager
        _start = State(initialValue: pending.suggestedStart)
    }

    private var duration: TimeInterval { pending.end.timeIntervalSince(start) }
    private var skipped: TimeInterval { start.timeIntervalSince(pending.suggestedStart) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: pending.activity.color))
                        .frame(width: 14, height: 14)
                    Text(pending.activity.name)
                        .font(.title3).fontWeight(.semibold)
                    Spacer()
                    Text(duration.formattedDuration)
                        .font(.title3).fontWeight(.medium)
                        .monospacedDigit()
                }

                Text("This is over \(manager.confirmThreshold.formattedDuration) long. Check where it starts. Anything before the start stays blank in your journal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                DatePicker(
                    "Starts",
                    selection: $start,
                    in: pending.suggestedStart...pending.end,
                    displayedComponents: [.date, .hourAndMinute]
                )

                LabeledContent("Ends") {
                    Text(pending.end.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)

                if skipped >= 60 {
                    Label("\(skipped.formattedDuration) before this start will stay blank",
                          systemImage: "circle.dashed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Confirm Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { manager.cancelPendingLabel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { manager.commitPendingLabel(start: start) }
                        .fontWeight(.semibold)
                        .disabled(duration < 60)
                }
            }
        }
    }
}

// MARK: - Intention Banner (unchanged)

struct IntentionBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "sun.horizon")
                    .foregroundStyle(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Set today's intention")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("What do you want to accomplish today?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Intention Display Card (unchanged)

struct IntentionDisplayCard: View {
    let intention: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sun.horizon.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                    .padding(.top, 1)

                Text(intention)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// Intention, reflection and note writing: Views/Journal/JournalEditor.swift

// MARK: - Current Activity Card (unchanged)

struct CurrentActivityCard: View {
    let block: TimeBlock?
    let isPaused: Bool
    let onPause: () -> Void
    let onStop: () -> Void
    let onResume: () -> Void
    let onQuickRemark: () -> Void
    let onSetTarget: (TimeInterval?) -> Void

    @State private var showingTimerInput = false
    @State private var targetMinutes: Double = 25

    var body: some View {
        VStack(spacing: 16) {
            if let block = block {
                activeBlockContent(block)
            } else {
                idleContent
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func activeBlockContent(_ block: TimeBlock) -> some View {
        VStack(spacing: 12) {
            HStack {
                Circle().fill(Color(hex: block.activityColor)).frame(width: 16, height: 16)
                Text(block.activityName).font(.title2).fontWeight(.semibold)

                Spacer()

                Button {
                    withAnimation { showingTimerInput.toggle() }
                } label: {
                    Image(systemName: block.targetDuration != nil ? "bell.badge.fill" : "bell")
                        .foregroundStyle(block.targetDuration != nil ? .orange : .secondary)
                }
            }

            if let target = block.targetDuration {
                let remaining = max(0, target - block.duration)
                VStack(spacing: 4) {
                    Text(remaining.detailedFormattedDuration)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(remaining == 0 ? .red : .primary)

                    Text("remaining of \(target.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(block.duration.detailedFormattedDuration)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            if showingTimerInput {
                VStack(spacing: 12) {
                    Divider()
                    HStack {
                        Stepper("\(Int(targetMinutes)) min", value: $targetMinutes, in: 1...120, step: 5)
                            .labelsHidden()

                        Text("\(Int(targetMinutes)) min")
                            .font(.headline)
                            .monospacedDigit()

                        Spacer()

                        if block.targetDuration != nil {
                            Button("Clear") {
                                onSetTarget(nil)
                                withAnimation { showingTimerInput = false }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }

                        Button("Set Goal") {
                            onSetTarget(targetMinutes * 60)
                            withAnimation { showingTimerInput = false }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Divider()
                }
            }

            if isPaused {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                    Text("Paused").font(.subheadline).foregroundStyle(.secondary)
                    if let pauseStart = block.pauseStartTime {
                        Text("· \(Date().timeIntervalSince(pauseStart).formattedDuration)")
                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
                .background(Color.orange.opacity(0.1)).cornerRadius(8)
            }

            if !isPaused && block.pauseCount > 0 {
                Text("\(block.pauseCount) pause\(block.pauseCount == 1 ? "" : "s") this session · \(block.pauseDuration.formattedDuration) total")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text("Since \(block.startTime, style: .time)").font(.caption).foregroundStyle(.secondary)
            Text("Tap another activity to switch · Stop to go back to logging")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }

        VStack(spacing: 12) {
            HStack(spacing: 20) {
                if isPaused {
                    Button(action: onResume) {
                        Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                } else {
                    Button(action: onPause) {
                        Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onStop) {
                        Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(.red)
                }
            }

            if !isPaused {
                Button(action: onQuickRemark) {
                    Label("Quick Remark", systemImage: "note.text.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.blue)
            }
        }
    }

    private var idleContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "timer").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No Active Activity").font(.title3).fontWeight(.medium)
            Text("Hold an activity below to start a timer")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Activity Button (unchanged)

struct ActivityButton: View {
    let activity: Activity
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            let intensity = UserDefaults.standard.double(forKey: "hapticIntensity")
            HapticManager.shared.impact(style: .medium, intensity: intensity > 0 ? intensity : 1.0)
            action()
        }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(hex: activity.color))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Color.white, lineWidth: isActive ? 3 : 0))
                    if let emoji = activity.emoji {
                        Text(emoji).font(.system(size: 22))
                    }
                }
                Text(activity.name)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isActive ? Color(hex: activity.color).opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(isActive ? Color(hex: activity.color) : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity Set Picker (unchanged)

struct ActivitySetPicker: View {
    let sets: [ActivitySet]
    let manager: TimeTrackingManager

    var activeSet: ActivitySet? { sets.first(where: { $0.isActive }) }

    var body: some View {
        Menu {
            ForEach(sets) { set in
                Button { manager.manualSwitchToSet(set) } label: {
                    HStack {
                        Text(set.name)
                        if set.isActive { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack {
                Text(activeSet?.name ?? "Select Set")
                    .font(.subheadline).foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6)).cornerRadius(10)
        }
    }
}
