import SwiftUI

struct DraggableBlockView: View {
    @Bindable var block: TimeBlock
    @ObservedObject var viewModel: TimelineViewModel
    let totalWidth: CGFloat
    
    // Drag States
    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false
    @State private var isDraggingBody = false // New: Moving the whole block
    @State private var showSplitControls = false
    
    // MARK: - Live Calculation Helpers
    
    var currentStart: Date {
        if isDraggingStart {
            let originalY = viewModel.yPosition(for: block.startTime)
            let newY = originalY + dragOffset
            return viewModel.date(for: newY)
        } else if isDraggingBody {
            let originalY = viewModel.yPosition(for: block.startTime)
            let newY = originalY + dragOffset
            return viewModel.date(for: newY)
        }
        return block.startTime
    }
    
    var currentEnd: Date {
        let end = block.endTime ?? Date()
        
        if isDraggingEnd {
            let originalY = viewModel.yPosition(for: end)
            let newY = originalY + dragOffset
            return viewModel.date(for: newY)
        } else if isDraggingBody {
            // When moving body, end moves by same offset as start
            let duration = end.timeIntervalSince(block.startTime)
            return currentStart.addingTimeInterval(duration)
        }
        return end
    }
    
    var topPosition: CGFloat { viewModel.yPosition(for: currentStart) }
    
    var height: CGFloat {
        let duration = currentEnd.timeIntervalSince(currentStart)
        return viewModel.height(for: max(0, duration))
    }
    
    var isBeingInteracted: Bool {
        isDraggingStart || isDraggingEnd || isDraggingBody
    }
    
    var body: some View {
        ZStack {
            // MARK: - The Block Body
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: block.activityColor))
                .shadow(radius: isBeingInteracted ? 6 : 0) // Lift effect
                .scaleEffect(isBeingInteracted ? 1.02 : 1.0) // Pop effect
                .overlay(
                    HStack {
                        // Color Indicator Strip
                        Rectangle()
                            .fill(Color.black.opacity(0.1))
                            .frame(width: 4)
                            .padding(.vertical, 4)
                            .padding(.leading, 4)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.displayName)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            // Only show time if block is tall enough
                            if height > 30 {
                                Text("\(currentStart, style: .time) - \(currentEnd, style: .time)")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            
                            // Only show duration if block is very tall
                            if height > 50 {
                                Text(currentEnd.timeIntervalSince(currentStart).formattedDuration)
                                    .font(.caption2)
                                    .padding(2)
                                    .background(Color.black.opacity(0.2))
                                    .cornerRadius(4)
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(4)
                        Spacer()
                    }
                )
                // Tap to toggle Split controls
                .onTapGesture {
                    if height > 60 {
                        withAnimation { showSplitControls.toggle() }
                    }
                }
                // FIX: Long Press + Drag to move entire block (prevents conflict with Scroll)
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .onEnded { _ in
                            withAnimation { isDraggingBody = true }
                            // Haptic feedback to signal "Grabbed"
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { val in
                                guard isDraggingBody else { return }
                                dragOffset = val.translation.height
                            }
                            .onEnded { _ in
                                if isDraggingBody {
                                    // Commit move for both start and end
                                    // We calculate the delta and apply it
                                    let newStart = currentStart
                                    let duration = block.duration
                                    
                                    // Update Block
                                    viewModel.moveBlock(block, to: newStart)
                                    
                                    isDraggingBody = false
                                    dragOffset = 0
                                }
                            }
                        )
                )
            
            // MARK: - Split Button (Conditional)
            if showSplitControls {
                HStack {
                    Button(action: {
                        let midpoint = block.startTime.addingTimeInterval(block.duration / 2)
                        viewModel.splitBlock(block, at: midpoint)
                        showSplitControls = false
                    }) {
                        Label("Split", systemImage: "scissors")
                            .font(.caption)
                            .padding(6)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(20)
                            .shadow(radius: 2)
                    }
                }
            }
            
            // MARK: - Top Handle (Start Time)
            VStack {
                Capsule()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 40, height: 6)
                    .shadow(radius: 1)
                    .frame(height: 24) // Invisible larger touch target
                    .contentShape(Rectangle())
                    // FIX: High Priority + MinDistance 0 ensures immediate grab
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { val in
                                isDraggingStart = true
                                dragOffset = val.translation.height
                            }
                            .onEnded { _ in
                                viewModel.commitStartTimeChange(for: block, newRawDate: currentStart)
                                isDraggingStart = false
                                dragOffset = 0
                            }
                    )
                Spacer()
            }
            
            // MARK: - Bottom Handle (End Time)
            VStack {
                Spacer()
                Capsule()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 40, height: 6)
                    .shadow(radius: 1)
                    .frame(height: 24) // Invisible larger touch target
                    .contentShape(Rectangle())
                    // FIX: High Priority + MinDistance 0
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { val in
                                isDraggingEnd = true
                                dragOffset = val.translation.height
                            }
                            .onEnded { _ in
                                viewModel.commitEndTimeChange(for: block, newRawDate: currentEnd)
                                isDraggingEnd = false
                                dragOffset = 0
                            }
                    )
            }
        }
        .frame(width: max(0, totalWidth), height: max(20, height))
        .position(x: totalWidth / 2, y: topPosition + (height / 2))
        .zIndex(isBeingInteracted ? 100 : 1) // Bring to front while dragging
    }
}
