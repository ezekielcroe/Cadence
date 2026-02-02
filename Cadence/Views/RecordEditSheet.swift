import SwiftUI
import SwiftData

struct RecordEditSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Bindable var timeBlock: TimeBlock
    
    @Query private var allActivities: [Activity]
    @State private var showingConvertConfirmation = false
    @State private var selectedActivity: Activity?
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Status Header
                Section("Current Status") {
                    HStack {
                        Circle()
                            .fill(Color(hex: timeBlock.activityColor))
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading) {
                            Text(timeBlock.displayName)
                                .font(.headline)
                            
                            Text(timeBlock.blockType.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if timeBlock.isGap || timeBlock.isPauseBlock {
                            Text("Can Convert")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(6)
                        }
                    }
                }
                
                // MARK: - Convert Gap/Pause
                if timeBlock.isGap || timeBlock.isPauseBlock {
                    Section {
                        Text("Convert this \(timeBlock.blockType) to a tracked activity:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if allActivities.isEmpty {
                            Text("No activities available. Create activities in the Sets tab first.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            ForEach(allActivities) { activity in
                                Button {
                                    selectedActivity = activity
                                    showingConvertConfirmation = true
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(Color(hex: activity.color))
                                            .frame(width: 16, height: 16)
                                        Text(activity.name)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Convert to Activity")
                    } footer: {
                        Text("Assign this time gap to a specific activity.")
                    }
                }
                
                // MARK: - Time Info (Read Only)
                Section {
                    LabeledContent("Start") {
                        Text(timeBlock.startTime, format: .dateTime)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let endTime = timeBlock.endTime {
                        LabeledContent("End") {
                            Text(endTime, format: .dateTime)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent("End") {
                            Text("Ongoing")
                                .foregroundStyle(.green)
                        }
                    }
                    
                    LabeledContent("Duration") {
                        Text(timeBlock.duration.detailedFormattedDuration)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Time Details")
                } footer: {
                    Text("To edit start/end times, use the Timeline Editor.")
                }
                
                // MARK: - Remarks
                Section {
                    TextEditor(text: $timeBlock.remarks)
                        .frame(minHeight: 100)
                } header: {
                    Text("Remarks")
                } footer: {
                    Text("Add notes about this activity session.")
                }
            }
            .navigationTitle("Edit Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .alert("Convert to \(selectedActivity?.name ?? "Activity")?", isPresented: $showingConvertConfirmation) {
                Button("Cancel", role: .cancel) { selectedActivity = nil }
                Button("Convert") {
                    if let activity = selectedActivity {
                        performConversion(to: activity)
                    }
                }
            } message: {
                Text("This will change this \(timeBlock.blockType) into '\(selectedActivity?.name ?? "")'.")
            }
        }
        .presentationDetents([.large])
    }
    
    private func performConversion(to activity: Activity) {
        timeBlock.activityID = activity.id
        timeBlock.activityName = activity.name
        timeBlock.activityColor = activity.color
        timeBlock.activitySetID = activity.setID
        timeBlock.blockType = "activity"
        
        // Remove pause metadata if converting from pause
        if timeBlock.isPauseBlock {
            timeBlock.stopState = "stopped" // Reset state
        }
        
        try? modelContext.save()
        dismiss()
    }
}
