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
    @Query private var dayNotes: [DayNote]

    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var showingQuickRemark = false
    @State private var showingIntention  = false

    var activeSet: ActivitySet? { activitySets.first { $0.isActive } }

    var activeSetActivities: [Activity] {
        guard let activities = activeSet?.activities else { return [] }
        return activities.sorted { $0.sortOrder < $1.sortOrder }
    }

    var isCurrentlyPaused: Bool {
        if manager.currentEntryMode == .prospective {
            return manager.currentTimeBlock?.isPaused ?? false
        }
        return false // Handled separately in retrospective mode
    }

    /// Today's DayNote if it exists
    private var todayNote: DayNote? {
        let today = DayNote.normalizedDate(Date())
        return dayNotes.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    /// Show the intention banner only before 2pm if no intention is set
    private var shouldShowIntentionBanner: Bool {
        guard todayNote?.intention.isEmpty ?? true else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 14
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // Morning intention banner
                if shouldShowIntentionBanner {
                    IntentionBanner { showingIntention = true }
                        .padding(.horizontal)
                } else if let note = todayNote, !note.intention.isEmpty {
                    IntentionDisplayCard(intention: note.intention) { showingIntention = true }
                        .padding(.horizontal)
                }

                // Mode-specific Tracking Cards
                if manager.currentEntryMode == .prospective {
                    CurrentActivityCard(
                        block: manager.currentTimeBlock,
                        isPaused: isCurrentlyPaused,
                        onPause:  { manager.handlePauseTap() },
                        onStop:   { manager.handleStopTap() },
                        onResume: { manager.handleResumeTap() },
                        onQuickRemark: { showingQuickRemark = true },
                        onSetTarget: { target in
                            if let currentBlock = manager.currentTimeBlock {
                                manager.setTargetDuration(for: currentBlock, duration: target)
                            }
                        }
                    )
                } else if manager.currentEntryMode == .retrospective {
                    RetrospectiveCard(
                        unlabeledDuration: manager.unlabeledDuration,
                        isPaused: manager.retrospectiveIsPaused,
                        hasAnchor: manager.retrospectiveAnchorTime != nil,
                        onPause:  { manager.handlePauseTap() },
                        onResume: { manager.handleResumeTap() },
                        onDiscard: { manager.handleStopTap() }
                    )
                }

                // Set Picker & Mode Indicator
                if activitySets.count > 1 {
                    HStack {
                        ActivitySetPicker(sets: activitySets)
                        
                        // Mode badge
                        Label(
                            manager.currentEntryMode.displayName,
                            systemImage: manager.currentEntryMode.icon
                        )
                        .font(.caption2).fontWeight(.medium)
                        .foregroundStyle(manager.currentEntryMode == .retrospective ? .orange : .blue)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(
                            (manager.currentEntryMode == .retrospective ? Color.orange : Color.blue)
                                .opacity(0.12)
                        )
                        .cornerRadius(6)
                    }
                    .padding(.horizontal)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(activeSetActivities) { activity in
                        ActivityButton(
                            activity: activity,
                            isActive: manager.currentEntryMode == .prospective && manager.currentTimeBlock?.activityID == activity.id && !isCurrentlyPaused
                        ) {
                            if manager.currentEntryMode == .prospective && isCurrentlyPaused && manager.currentTimeBlock?.activityID == activity.id {
                                manager.handleResumeTap()
                            } else {
                                manager.handleActivityTap(activity)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top)
        }
        .onReceive(timer) { _ in
            let isActivelyTrackingProspective = manager.currentTimeBlock != nil && manager.currentTimeBlock?.endTime == nil
            let isActivelyTrackingRetrospective = manager.currentEntryMode == .retrospective && manager.retrospectiveAnchorTime != nil
            
            if isActivelyTrackingProspective || isActivelyTrackingRetrospective {
                manager.objectWillChange.send()
            }
        }
        .onAppear {
            manager.updateIdleTimerState()
        }
        .onDisappear {
            // Handled automatically by idle timer updates
        }
        .sheet(isPresented: $showingQuickRemark) {
            if let block = manager.currentTimeBlock {
                QuickRemarkSheet(timeBlock: block)
            }
        }
        .sheet(isPresented: $showingIntention) {
            IntentionSheet(existingNote: todayNote)
                .presentationDetents([.medium])
        }
    }
}

// MARK: - New Retrospective Card

struct RetrospectiveCard: View {
    let unlabeledDuration: TimeInterval
    let isPaused: Bool
    let hasAnchor: Bool
    let onPause: () -> Void
    let onResume: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Status label
            HStack {
                Image(systemName: "clock.badge.questionmark")
                    .foregroundStyle(.orange)
                Text("Unlabeled Time")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if isPaused {
                    Text("PAUSED")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                }
            }

            // Elapsed time — large display
            if hasAnchor {
                Text(unlabeledDuration.formattedDuration)
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(isPaused ? .secondary : .primary)
                    .contentTransition(.numericText())
            } else {
                Text("Tap an activity to start logging")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 14)
            }

            // Hint text
            if hasAnchor {
                Text("Tap an activity below to label this time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Controls
            if hasAnchor {
                HStack(spacing: 16) {
                    Button(action: isPaused ? onResume : onPause) {
                        Label(
                            isPaused ? "Resume" : "Pause",
                            systemImage: isPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.subheadline).fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(isPaused ? .green : .blue)

                    Button(role: .destructive, action: onDiscard) {
                        Label("Discard", systemImage: "xmark")
                            .font(.subheadline).fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding(.horizontal)
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

// MARK: - Intention Sheet (unchanged)

struct IntentionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existingNote: DayNote?

    @State private var intentionText = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today's Intention")
                        .font(.headline)
                    Text("What do you want to do or accomplish today?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextField("Write your intention here…", text: $intentionText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .lineLimit(3...6)

                Spacer()
            }
            .padding()
            .navigationTitle("Morning Intention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(intentionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                intentionText = existingNote?.intention ?? ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isFocused = true }
            }
        }
    }

    private func save() {
        let trimmed = intentionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { dismiss(); return }

        if let note = existingNote {
            note.intention = trimmed
            note.intentionUpdatedAt = Date()
        } else {
            let note = DayNote(date: Date(), intention: trimmed)
            modelContext.insert(note)
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Updated QuickRemarkSheet (unchanged)

struct QuickRemarkSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var blockRemarks: [Remark]

    @Bindable var timeBlock: TimeBlock
    @State private var newRemark = ""
    @FocusState private var isTextFieldFocused: Bool

    init(timeBlock: TimeBlock) {
        self.timeBlock = timeBlock
        let blockID = timeBlock.id
        _blockRemarks = Query(
            filter: #Predicate<Remark> { $0.timeBlockID == blockID },
            sort: \.timestamp
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Block context header
                HStack {
                    Circle()
                        .fill(Color(hex: timeBlock.activityColor))
                        .frame(width: 12, height: 12)
                    Text(timeBlock.activityName)
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(timeBlock.duration.formattedDuration)
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Input field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Remark")
                        .font(.headline)

                    TextField("Type your note… (#tags for categories)", text: $newRemark, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTextFieldFocused)
                        .lineLimit(3...6)
                        .submitLabel(.done)
                        .onSubmit {
                            if !newRemark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addRemark() }
                        }
                }

                // Existing remarks for this block
                if !blockRemarks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Previous Remarks")
                            .font(.caption).foregroundStyle(.secondary)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(blockRemarks) { remark in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(remark.timestamp.formatted(date: .omitted, time: .shortened))
                                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                            Spacer()
                                        }
                                        Text(remark.text)
                                            .font(.caption).foregroundStyle(.primary)
                                        if !remark.tags.isEmpty {
                                            TagChipRow(tags: remark.tags)
                                        }
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .frame(maxHeight: 150)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isTextFieldFocused = true }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func addRemark() {
        let trimmed = newRemark.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let remark = Remark(timeBlockID: timeBlock.id, text: trimmed)
        modelContext.insert(remark)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Current Activity Card (unchanged from original)

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
                
                // Inline timer toggle button
                Button {
                    withAnimation { showingTimerInput.toggle() }
                } label: {
                    Image(systemName: block.targetDuration != nil ? "bell.badge.fill" : "bell")
                        .foregroundStyle(block.targetDuration != nil ? .orange : .secondary)
                }
            }

            // Conditional display for Countdown vs Elapsed Time
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

            // Inline Timer Input
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
                Text("\(block.pauseCount) pause\(block.pauseCount == 1 ? "" : "s") this session · \(block.totalPauseDuration.formattedDuration) total")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Text("Since \(block.startTime, style: .time)").font(.caption).foregroundStyle(.secondary)
        }

        // Action Buttons
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
            Text("Tap an activity below to start tracking")
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
    @Environment(\.modelContext) private var modelContext

    var activeSet: ActivitySet? { sets.first(where: { $0.isActive }) }

    var body: some View {
        Menu {
            ForEach(sets) { set in
                Button { selectSet(set) } label: {
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

    private func selectSet(_ set: ActivitySet) {
        for s in sets { s.isActive = (s.id == set.id) }
        try? modelContext.save()
    }
}
