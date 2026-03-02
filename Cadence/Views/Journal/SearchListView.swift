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

    @Query private var matches: [Remark]

    // Block cache — populated lazily from the matched remark set.
    @State private var blockCache: [UUID: TimeBlock] = [:]

    private let searchText: String

    init(searchText: String) {
        self.searchText = searchText

        _matches = Query(
            filter: #Predicate {
                $0.text.localizedStandardContains(searchText)
            },
            sort: \.timestamp,
            order: .reverse
        )
    }

    private func block(for remark: Remark) -> TimeBlock? {
        blockCache[remark.timeBlockID]
    }

    // Build a cache of only the blocks we actually need to display.
    private func populateBlockCache() {
        let neededIDs = Set(matches.map { $0.timeBlockID })
            .subtracting(blockCache.keys)

        guard !neededIDs.isEmpty else { return }

        for id in neededIDs {
            let descriptor = FetchDescriptor<TimeBlock>(
                predicate: #Predicate<TimeBlock> { $0.id == id }
            )
            if let block = try? modelContext.fetch(descriptor).first {
                blockCache[id] = block
            }
        }
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
        .onAppear { populateBlockCache() }
        .onChange(of: matches.count) { _, _ in populateBlockCache() }
    }
    
    // Optional: Highlight the search term in results
    private func highlightedText(_ text: String) -> AttributedString {
        let attributed = AttributedString(text)
        // A simple highlighting implementation would go here.
        // For Phase 3, standard text is sufficient.
        return attributed
    }
}
