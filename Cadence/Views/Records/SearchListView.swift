//
//  SearchListView.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 14/2/26.
//


import SwiftUI
import SwiftData

struct SearchListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // We use a raw query here so we can dynamically change the predicate
    @Query private var matches: [Remark]
    
    // We also need blocks to show context (activity color/name)
    // Optimization: We fetch blocks only for the displayed remarks
    @Query private var blocks: [TimeBlock]
    
    private let searchText: String
    
    init(searchText: String) {
        self.searchText = searchText
        
        // DYNAMIC PREDICATE: This runs on the database, not in memory.
        // It finds remarks where the text OR the tags match.
        _matches = Query(
            filter: #Predicate {
                $0.text.localizedStandardContains(searchText) // Case-insensitive, diacritic-insensitive
            },
            sort: \.timestamp,
            order: .reverse
        )
        
        // We fetch all blocks to resolve relationships. 
        // In a true large-scale app, we would fetch these lazily by ID,
        // but SwiftData handles caching well enough for this lookup pattern.
        _blocks = Query()
    }
    
    // Helper to resolve block details
    private func block(for remark: Remark) -> TimeBlock? {
        blocks.first { $0.id == remark.timeBlockID }
    }
    
    var body: some View {
        List {
            if matches.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                Section(header: Text("\(matches.count) Result\(matches.count == 1 ? "" : "s")")) {
                    ForEach(matches) { remark in
                        // Reusing your existing row component
                        // We wrap it in a link to jump to that day (future enhancement)
                        // For now, just showing the context is enough.
                        VStack(alignment: .leading, spacing: 6) {
                            
                            // Context Header (Date + Activity)
                            HStack {
                                Text(remark.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                if let b = block(for: remark) {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color(hex: b.activityColor))
                                            .frame(width: 8, height: 8)
                                        Text(b.activityName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(4)
                                }
                            }
                            
                            // The Remark Content
                            Text(highlightedText(remark.text))
                                .font(.body)
                            
                            // Tags
                            if !remark.tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(remark.tags, id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(.caption2)
                                                .foregroundStyle(.blue)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.1))
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // Optional: Highlight the search term in results
    private func highlightedText(_ text: String) -> AttributedString {
        let attributed = AttributedString(text)
        // A simple highlighting implementation would go here.
        // For Phase 3, standard text is sufficient.
        return attributed
    }
}
