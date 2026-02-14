//
//  GapActionBanner.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 14/2/26.
//


import SwiftUI

// MARK: - Gap Action Banner
// Used by TimelineListView to show the "Unaccounted Time" warning
struct GapActionBanner: View {
    let gapCount: Int
    let totalDuration: TimeInterval
    let onReview: () -> Void

    var body: some View {
        Button(action: onReview) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Unaccounted Time")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(gapCount) gap\(gapCount == 1 ? "" : "s") · \(totalDuration.formattedDuration) total")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Review").fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.2))
                .cornerRadius(8)
            }
            .padding()
            .background(Color.orange)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bulk Action Toolbar
// Used by RecordsView for selection mode actions
struct BulkActionToolbar: View {
    let count: Int
    let onMerge: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Text("\(count) selected")
                    .font(.subheadline).fontWeight(.medium)
                Spacer()
                HStack(spacing: 20) {
                    Button(action: onMerge) {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.merge")
                            Text("Merge").font(.caption2)
                        }
                    }
                    .disabled(count < 2)

                    Button(role: .destructive, action: onDelete) {
                        VStack(spacing: 2) {
                            Image(systemName: "trash")
                            Text("Delete").font(.caption2)
                        }
                    }
                    .disabled(count == 0)
                }
            }
            .padding()
            .background(.regularMaterial)
        }
    }
}

// MARK: - Filters View
// Used by RecordsView for filtering options
struct FiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedActivity: String?
    @Binding var selectedTag: String?
    
    let activities: [String]
    let allTags: [String]

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

                if !allTags.isEmpty {
                    Section("Tag") {
                        Picker("Filter by Tag", selection: $selectedTag) {
                            Text("All Tags").tag(nil as String?)
                            ForEach(allTags, id: \.self) { tag in
                                Label("#\(tag)", systemImage: "tag").tag(tag as String?)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear All") {
                        selectedActivity = nil
                        selectedTag = nil
                    }
                    .disabled(selectedActivity == nil && selectedTag == nil)
                }
            }
        }
    }
}