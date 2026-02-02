//
//  TimelineEditorView.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 2/2/26.
//

import SwiftUI
import SwiftData

struct TimelineEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: TimelineViewModel
    
    // Zoom state
    @State private var lastScale: CGFloat = 1.0
    
    init(date: Date, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: TimelineViewModel(modelContext: modelContext, date: date))
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        // 1. Background Grid (The "Ruler")
                        // We attach IDs to these views so ScrollViewReader can find them
                        VStack(spacing: 0) {
                            ForEach(0..<24) { hour in
                                HStack(alignment: .top) {
                                    Text(String(format: "%02d:00", hour))
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .frame(width: 45, alignment: .trailing)
                                        .offset(y: -6)
                                    
                                    Rectangle()
                                        .fill(Color(.systemGray5))
                                        .frame(height: 1)
                                }
                                .frame(height: viewModel.hourHeight, alignment: .top)
                                .id(hour) // ID for auto-scrolling
                            }
                        }
                        .padding(.top, 20)
                        
                        // 2. The Blocks Layer
                        GeometryReader { geo in
                            let blockWidth = max(0, geo.size.width - 60)
                            
                            ZStack(alignment: .topLeading) {
                                ForEach(viewModel.blocks) { block in
                                    DraggableBlockView(
                                        block: block,
                                        viewModel: viewModel,
                                        totalWidth: blockWidth
                                    )
                                }
                            }
                            .offset(x: 55, y: 20)
                        }
                        .frame(height: viewModel.totalHeight + 50)
                        
                        // 3. Current Time Indicator
                        if Calendar.current.isDateInToday(viewModel.currentDate) {
                            CurrentTimeLine(viewModel: viewModel)
                                .offset(x: 55, y: 20)
                        }
                    }
                    .padding(.bottom, 200) // Extra padding at bottom for easy editing of late blocks
                }
                .background(Color(.systemBackground))
                // Pinch to Zoom Gesture
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in
                            let delta = val / lastScale
                            lastScale = val
                            let newScale = viewModel.zoomScale * delta
                            viewModel.setZoom(newScale)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                        }
                )
                
                // Floating Zoom Controls (Alternative to pinch)
                VStack(spacing: 12) {
                    Button {
                        withAnimation { viewModel.setZoom(viewModel.zoomScale + 0.5) }
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    
                    Button {
                        withAnimation { viewModel.setZoom(viewModel.zoomScale - 0.5) }
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding()
            }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Auto-Scroll Logic
                let targetHour = viewModel.getInitialScrollHour()
                
                // Small delay to ensure layout is ready before scrolling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        proxy.scrollTo(targetHour, anchor: .top)
                    }
                }
            }
        }
    }
}

// Helper: Current Time Line
struct CurrentTimeLine: View {
    @ObservedObject var viewModel: TimelineViewModel
    
    var yPos: CGFloat {
        viewModel.yPosition(for: Date())
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
                .offset(x: -3)
            
            Rectangle()
                .fill(.red)
                .frame(height: 1)
        }
        .offset(y: yPos)
    }
}
