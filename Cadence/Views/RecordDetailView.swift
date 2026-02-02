//
//  RecordDetailView.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 2/2/26.
//

import SwiftUI
import SwiftData

// MARK: - Record Detail View (Updated)
struct RecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let block: TimeBlock
    
    @State private var showingEditSheet = false
    @State private var showingTimeline = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header card
                    VStack(spacing: 16) {
                        HStack {
                            Circle()
                                .fill(Color(hex: block.activityColor))
                                .frame(width: 40, height: 40)
                            
                            VStack(alignment: .leading) {
                                Text(block.displayName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Text(block.blockType.capitalized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        
                        VStack(spacing: 4) {
                            Text(block.duration.detailedFormattedDuration)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("Duration")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: block.activityColor).opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            showingEditSheet = true
                        } label: {
                            Label("Edit Details & Remarks", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        
                        // NEW: Edit in Timeline button replaces Merge/Split
                        Button {
                            showingTimeline = true
                        } label: {
                            Label("Edit in Timeline", systemImage: "chart.bar.xaxis")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Time details
                    VStack(spacing: 12) {
                        DetailRow(label: "Started", value: block.startTime.formatted(date: .abbreviated, time: .shortened), icon: "clock")
                        
                        if let endTime = block.endTime {
                            DetailRow(label: "Ended", value: endTime.formatted(date: .abbreviated, time: .shortened), icon: "clock.fill")
                        } else {
                            DetailRow(label: "Status", value: "Ongoing", icon: "clock.fill", valueColor: .green)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Remarks
                    if !block.remarks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Remarks", systemImage: "note.text").font(.headline)
                            Text(block.remarks)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                    }
                }
                .padding()
            }
            .navigationTitle("Record Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                RecordEditSheet(timeBlock: block)
            }
            .sheet(isPresented: $showingTimeline) {
                NavigationStack {
                    TimelineEditorView(date: block.startTime, modelContext: modelContext)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingTimeline = false }
                            }
                        }
                }
            }
        }
    }
}

// Helper for Detail Row
struct DetailRow: View {
    let label: String
    let value: String
    let icon: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Label(label, systemImage: icon).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).foregroundColor(valueColor)
        }
    }
}

struct FiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedActivity: String?
    let activities: [String]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    Picker("Filter by Activity", selection: $selectedActivity) {
                        Text("All Activities").tag(nil as String?)
                        ForEach(activities, id: \.self) { activity in
                            Text(activity).tag(activity as String?)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
