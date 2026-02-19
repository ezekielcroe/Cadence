//
//  SplitBlockSheet.swift
//  Cadence
//
//  Split a time block at a precise time
//

import SwiftUI
import SwiftData

struct SplitBlockSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let block: TimeBlock
    let onSplit: () -> Void
    
    @State private var splitTime: Date
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(block: TimeBlock, onSplit: @escaping () -> Void) {
        self.block = block
        self.onSplit = onSplit
        
        // Default to midpoint
        let midpoint = block.startTime.addingTimeInterval(block.duration / 2)
        _splitTime = State(initialValue: midpoint)
    }
    
    private var firstPartDuration: TimeInterval {
        splitTime.timeIntervalSince(block.startTime)
    }
    
    private var secondPartDuration: TimeInterval {
        (block.endTime ?? Date()).timeIntervalSince(splitTime)
    }
    
    private var isValidSplit: Bool {
        firstPartDuration >= 60 && secondPartDuration >= 60 // Minimum 1 minute each
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Original block info
                Section {
                    HStack {
                        Circle()
                            .fill(Color(hex: block.activityColor))
                            .frame(width: 24, height: 24)
                        
                        VStack(alignment: .leading) {
                            Text(block.displayName)
                                .font(.headline)
                            Text("\(block.startTime.formatted(date: .omitted, time: .shortened)) → \((block.endTime ?? Date()).formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(block.duration.formattedDuration)
                            .font(.headline)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Original Block")
                }
                
                // Split time picker
                Section {
                    DatePicker(
                        "Split At",
                        selection: $splitTime,
                        in: block.startTime...(block.endTime ?? Date()),
                        displayedComponents: .hourAndMinute
                    )
                    
                    // Quick presets
                    HStack {
                        Text("Quick:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Button("¼") {
                            splitTime = block.startTime.addingTimeInterval(block.duration * 0.25)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("½") {
                            splitTime = block.startTime.addingTimeInterval(block.duration * 0.5)
                        }
                        .buttonStyle(.bordered)
                        
                        Button("¾") {
                            splitTime = block.startTime.addingTimeInterval(block.duration * 0.75)
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text("Split Point")
                }
                
                // Preview of result
                Section {
                    HStack {
                        Text("Part 1")
                        Spacer()
                        Text("\(block.startTime.formatted(date: .omitted, time: .shortened)) → \(splitTime.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                        Text(firstPartDuration.formattedDuration)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    
                    HStack {
                        Text("Part 2")
                        Spacer()
                        Text("\(splitTime.formatted(date: .omitted, time: .shortened)) → \((block.endTime ?? Date()).formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                        Text(secondPartDuration.formattedDuration)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Result Preview")
                } footer: {
                    Text("Both parts will keep the same activity. You can change this after splitting.")
                }
            }
            .navigationTitle("Split Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") {
                        performSplit()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValidSplit)
                }
            }
            .alert("Cannot Split", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
        .presentationDetents([.medium])
    }
    
    private func performSplit() {
        let editor = TimeBlockEditor(modelContext: modelContext)
        
        do {
            try editor.splitBlock(block, at: splitTime)
            onSplit()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
