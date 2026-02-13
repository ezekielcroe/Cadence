//
//  TrackingView.swift
//  Cadence
//

import SwiftUI
import SwiftData
import Combine

struct TrackingView: View {
    @ObservedObject var manager: TimeTrackingManager
    @Environment(\.modelContext) private var modelContext

    @Query private var activitySets: [ActivitySet]
    @Query private var activities: [Activity]

    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var showingQuickRemark = false

    var activeSet: ActivitySet? {
        activitySets.first { $0.isActive }
    }

    var activeSetActivities: [Activity] {
        guard let setID = activeSet?.id else { return [] }
        return activities.filter { $0.setID == setID }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Pause state lives directly on the block — no separate pause block required.
    var isCurrentlyPaused: Bool {
        manager.currentTimeBlock?.isPaused ?? false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CurrentActivityCard(
                    block: manager.currentTimeBlock,
                    isPaused: isCurrentlyPaused,
                    onPause: {
                        manager.pauseCurrentActivity()
                    },
                    onStop: {
                        manager.stopCurrentActivity()
                    },
                    onResume: {
                        // Resume is in-place — no activity argument needed.
                        // The paused block simply continues.
                        manager.resumeFromPause()
                    },
                    onQuickRemark: {
                        showingQuickRemark = true
                    }
                )

                if activitySets.count > 1 {
                    ActivitySetPicker(sets: activitySets)
                        .padding(.horizontal)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(activeSetActivities) { activity in
                        ActivityButton(
                            activity: activity,
                            isActive: manager.currentTimeBlock?.activityID == activity.id && !isCurrentlyPaused
                        ) {
                            if isCurrentlyPaused && manager.currentTimeBlock?.activityID == activity.id {
                                // Tapping the same activity while paused → resume in place
                                manager.resumeFromPause()
                            } else {
                                // Tapping any activity (including while paused on a different one)
                                // → startActivity handles closing the current pause before switching
                                manager.startActivity(activity)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top)
        }
        .onReceive(timer) { _ in
            if manager.currentTimeBlock != nil {
                manager.objectWillChange.send()
            }
        }
        .sheet(isPresented: $showingQuickRemark) {
            if let block = manager.currentTimeBlock {
                QuickRemarkSheet(timeBlock: block)
            }
        }
    }
}

// MARK: - Current Activity Card

struct CurrentActivityCard: View {
    let block: TimeBlock?
    let isPaused: Bool
    let onPause: () -> Void
    let onStop: () -> Void
    let onResume: () -> Void
    let onQuickRemark: () -> Void

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

    // MARK: Active block view

    @ViewBuilder
    private func activeBlockContent(_ block: TimeBlock) -> some View {
        VStack(spacing: 12) {

            // Activity name
            HStack {
                Circle()
                    .fill(Color(hex: block.activityColor))
                    .frame(width: 16, height: 16)
                Text(block.activityName)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            // Elapsed timer (active duration, pauses excluded)
            Text(block.duration.detailedFormattedDuration)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            // Paused indicator
            if isPaused {
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Paused")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Show how long this pause has been running
                    if let pauseStart = block.pauseStartTime {
                        Text("· \(Date().timeIntervalSince(pauseStart).formattedDuration)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            // Pause history summary (shown when active, not paused)
            if !isPaused && block.pauseCount > 0 {
                Text("\(block.pauseCount) pause\(block.pauseCount == 1 ? "" : "s") this session · \(block.totalPauseDuration.formattedDuration) total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Remarks preview
            if !block.remarks.isEmpty {
                Button(action: onQuickRemark) {
                    HStack {
                        Image(systemName: "note.text")
                            .font(.caption)
                        Text(block.remarks.split(separator: "\n").last.map(String.init) ?? "")
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            // Start time
            Text("Since \(block.startTime, style: .time)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Control buttons
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                if isPaused {
                    Button(action: onResume) {
                        Label("Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    Button(action: onPause) {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onStop) {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }

            // Quick Remark — available while active; hidden while paused
            // (remarks on a paused session are still accessible via the preview button above)
            if !isPaused {
                Button(action: onQuickRemark) {
                    Label("Quick Remark", systemImage: "note.text.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
        }
    }

    // MARK: Idle view

    private var idleContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Active Activity")
                .font(.title3)
                .fontWeight(.medium)

            Text("Tap an activity below to start tracking")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Activity Button

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
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: isActive ? 3 : 0)
                        )

                    if let emoji = activity.emoji {
                        Text(emoji)
                            .font(.system(size: 22))
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
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color(hex: activity.color) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity Set Picker

struct ActivitySetPicker: View {
    let sets: [ActivitySet]
    @Environment(\.modelContext) private var modelContext

    var activeSet: ActivitySet? {
        sets.first(where: { $0.isActive })
    }

    var body: some View {
        Menu {
            ForEach(sets) { set in
                Button {
                    selectSet(set)
                } label: {
                    HStack {
                        Text(set.name)
                        if set.isActive {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(activeSet?.name ?? "Select Set")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }

    private func selectSet(_ set: ActivitySet) {
        for s in sets { s.isActive = (s.id == set.id) }
        try? modelContext.save()
    }
}

// MARK: - Quick Remark Sheet

struct QuickRemarkSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var timeBlock: TimeBlock
    @State private var newRemark = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Block context header
                HStack {
                    Circle()
                        .fill(Color(hex: timeBlock.activityColor))
                        .frame(width: 12, height: 12)

                    Text(timeBlock.activityName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(timeBlock.duration.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Input field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Quick Remark")
                        .font(.headline)

                    TextField("Type your note... (use #tags for categories)", text: $newRemark, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFieldFocused)
                        .lineLimit(3...6)
                        .onSubmit {
                            if !newRemark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                addRemark()
                            }
                        }
                        .submitLabel(.done)
                }

                // Existing remarks
                if !timeBlock.remarks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Previous Remarks")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(timeBlock.remarks)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                        .frame(maxHeight: 120)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Quick Remark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addRemark() }
                        .disabled(newRemark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .fontWeight(.semibold)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isTextFieldFocused = false }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func addRemark() {
        let trimmed = newRemark.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeString = formatter.string(from: Date())

        let formatted = "[\(timeString)] \(trimmed)"

        timeBlock.remarks = timeBlock.remarks.isEmpty
            ? formatted
            : timeBlock.remarks + "\n" + formatted

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: Activity.self, ActivitySet.self, TimeBlock.self,
        configurations: config
    )
    let context = container.mainContext

    let workSet = ActivitySet(name: "Work", isActive: true)
    context.insert(workSet)

    let activity1 = Activity(name: "Deep Work", color: "#4CAF50", setID: workSet.id, emoji: "💻")
    let activity2 = Activity(name: "Meetings",  color: "#2196F3", setID: workSet.id, sortOrder: 1, emoji: "👥")
    let activity3 = Activity(name: "Email",     color: "#FF9800", setID: workSet.id, sortOrder: 2, emoji: "📧")
    context.insert(activity1)
    context.insert(activity2)
    context.insert(activity3)

    let manager = TimeTrackingManager(modelContext: context)

    return TrackingView(manager: manager)
        .modelContainer(container)
}
