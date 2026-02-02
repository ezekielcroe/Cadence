//
//  TimelineViewModel.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 2/2/26.
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class TimelineViewModel: ObservableObject {
    private var modelContext: ModelContext
    
    // MARK: - Zoom Configuration
    // Base height for 1 hour (default density)
    private let baseHourHeight: CGFloat = 80.0
    
    // Current zoom scale (1.0 = standard, 2.0 = 2x height, etc.)
    @Published var zoomScale: CGFloat = 1.0
    
    // Dynamic height based on zoom
    var hourHeight: CGFloat { baseHourHeight * zoomScale }
    var totalHeight: CGFloat { hourHeight * 24 }
    
    // Limits
    let minZoom: CGFloat = 0.5  // Compact view
    let maxZoom: CGFloat = 4.0  // High precision view
    
    @Published var blocks: [TimeBlock] = []
    @Published var currentDate: Date
    
    // Day boundaries
    var dayStart: Date { Calendar.current.startOfDay(for: currentDate) }
    var dayEnd: Date { Calendar.current.date(byAdding: .day, value: 1, to: dayStart)! }
    
    init(modelContext: ModelContext, date: Date) {
        self.modelContext = modelContext
        self.currentDate = date
        loadBlocks()
    }
    
    func loadBlocks() {
        let start = dayStart
        let end = dayEnd
        
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate { block in
                block.startTime >= start && block.startTime < end
            },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        
        do {
            blocks = try modelContext.fetch(descriptor)
        } catch {
            print("Error loading blocks: \(error)")
        }
    }
    
    // MARK: - Zoom Actions
    
    func setZoom(_ scale: CGFloat) {
        // Clamp the zoom level
        zoomScale = min(max(scale, minZoom), maxZoom)
    }
    
    // MARK: - Geometry Converters
    
    func yPosition(for date: Date) -> CGFloat {
        let minutes = date.timeIntervalSince(dayStart) / 60
        return CGFloat(minutes) * (hourHeight / 60)
    }
    
    func date(for yPosition: CGFloat) -> Date {
        let minutes = yPosition / (hourHeight / 60)
        return dayStart.addingTimeInterval(minutes * 60)
    }
    
    func height(for duration: TimeInterval) -> CGFloat {
        return CGFloat(duration / 3600) * hourHeight
    }
    
    // MARK: - Smart Scroll Logic
    
    /// Determines the best hour to scroll to initially
    func getInitialScrollHour() -> Int {
        let calendar = Calendar.current
        
        // 1. If the passed date is NOT midnight, user likely clicked a specific block/time
        // Scroll to that specific hour (minus padding)
        let hour = calendar.component(.hour, from: currentDate)
        let minute = calendar.component(.minute, from: currentDate)
        
        // If it's not 00:00 (exact), treat it as a specific target
        if hour != 0 || minute != 0 {
            return max(0, hour - 1)
        }
        
        // 2. If it IS midnight (generic "View Day"), find the first block
        if let firstBlock = blocks.first {
            let firstBlockHour = calendar.component(.hour, from: firstBlock.startTime)
            return max(0, firstBlockHour - 1)
        }
        
        // 3. If no blocks, check if it's "Today"
        if calendar.isDateInToday(currentDate) {
            let currentHour = calendar.component(.hour, from: Date())
            return max(0, currentHour - 1)
        }
        
        // 4. Default to 8 AM for empty past/future days
        return 8
    }
    
    // MARK: - Interaction Logic
    
    func snapToMinute(_ date: Date) -> Date {
        let calendar = Calendar.current
        let seconds = calendar.component(.second, from: date)
        if seconds < 30 {
            return calendar.date(bySetting: .second, value: 0, of: date)!
        } else {
            return calendar.date(byAdding: .minute, value: 1, to: calendar.date(bySetting: .second, value: 0, of: date)!)!
        }
    }
    
    func commitEndTimeChange(for targetBlock: TimeBlock, newRawDate: Date) {
        let newDate = snapToMinute(newRawDate)
        guard newDate > targetBlock.startTime else { return }
        guard newDate <= dayEnd else { return } // Constraint to day end
        
        targetBlock.endTime = newDate
        targetBlock.stopState = "stopped"
        
        let collisions = blocks.filter { block in
            block.id != targetBlock.id &&
            block.startTime >= targetBlock.startTime &&
            block.startTime < newDate
        }
        
        for collision in collisions {
            if let collisionEnd = collision.endTime, collisionEnd <= newDate {
                modelContext.delete(collision)
            } else {
                collision.startTime = newDate
            }
        }
        
        saveAndReload()
    }
    
    func commitStartTimeChange(for targetBlock: TimeBlock, newRawDate: Date) {
        let newDate = snapToMinute(newRawDate)
        if let endTime = targetBlock.endTime { guard newDate < endTime else { return } }
        guard newDate >= dayStart else { return }
        
        targetBlock.startTime = newDate
        
        let collisions = blocks.filter { block in
            block.id != targetBlock.id &&
            block.endTime ?? Date() > newDate &&
            block.startTime < targetBlock.startTime
        }
        
        for collision in collisions {
            if collision.startTime >= newDate {
                modelContext.delete(collision)
            } else {
                collision.endTime = newDate
            }
        }
        
        saveAndReload()
    }
    
    func splitBlock(_ block: TimeBlock, at time: Date) {
        guard let endTime = block.endTime, time > block.startTime && time < endTime else { return }
        
        let part2 = TimeBlock(
            activityID: block.activityID,
            activityName: block.activityName,
            activityColor: block.activityColor,
            activitySetID: block.activitySetID,
            startTime: time,
            blockType: block.blockType
        )
        part2.endTime = endTime
        part2.remarks = block.remarks
        part2.stopState = block.stopState
        
        block.endTime = time
        
        modelContext.insert(part2)
        saveAndReload()
    }
    
    // MARK: - Move Block Logic
        func moveBlock(_ block: TimeBlock, to newRawStart: Date) {
            let newStart = snapToMinute(newRawStart)
            let duration = block.duration
            let newEnd = newStart.addingTimeInterval(duration)
            
            // Validation boundaries
            guard newStart >= dayStart && newEnd <= dayEnd else { return }
            
            block.startTime = newStart
            block.endTime = newEnd
            block.stopState = "stopped"
            
            // Remove ANY blocks that are completely covered by this new range
            // This is a "Bulldozer" move - it overwrites anything underneath
            let collisions = blocks.filter { other in
                other.id != block.id &&
                other.startTime < newEnd &&
                (other.endTime ?? Date()) > newStart
            }
            
            for collision in collisions {
                // Simplified logic: If we overlap, we delete the underlying block
                // (You could make this smarter by trimming, but moving is destructive)
                modelContext.delete(collision)
            }
            
            saveAndReload()
        }
    
    private func saveAndReload() {
        try? modelContext.save()
        loadBlocks()
    }
}
