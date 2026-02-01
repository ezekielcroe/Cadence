//
//  BackupData.swift
//  Cadence
//
//  Created by Zhi Zheng Yeo on 1/2/26.
//


import Foundation
import SwiftData

// MARK: - Archive Models (DTOs)
// These structs ensure data is portable and independent of SwiftData context
struct BackupData: Codable {
    let metadata: BackupMetadata
    let activities: [ActivityDTO]
    let activitySets: [ActivitySetDTO]
    let timeBlocks: [TimeBlockDTO]
}

struct BackupMetadata: Codable {
    var version: String = "1.0"
    let exportDate: Date
    let recordCount: Int
    let appVersion: String
}

struct ActivityDTO: Codable {
    let id: UUID
    let name: String
    let emoji: String?
    let color: String
    let setID: UUID
    let sortOrder: Int
}

struct ActivitySetDTO: Codable {
    let id: UUID
    let name: String
    let isActive: Bool
}

struct TimeBlockDTO: Codable {
    let id: UUID
    let activityID: UUID?
    let activityName: String
    let activityColor: String
    let startTime: Date
    let endTime: Date?
    let remarks: String
    let blockType: String
    let duration: TimeInterval
    let switchCount: Int
    let totalPauseDuration: TimeInterval
}

// MARK: - Manager Class
class DataArchiveManager {
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Archive (Export JSON)
    func createArchive(olderThan date: Date? = nil) throws -> URL {
        // 1. Fetch Data
        // If date is provided, filter. If nil, export all.
        let blockDescriptor = FetchDescriptor<TimeBlock>(
            predicate: date != nil ? #Predicate<TimeBlock> { $0.startTime < date! } : nil
        )
        let blocks = try modelContext.fetch(blockDescriptor)
        
        let activities = try modelContext.fetch(FetchDescriptor<Activity>())
        let sets = try modelContext.fetch(FetchDescriptor<ActivitySet>())
        
        // 2. Map to DTOs
        let blockDTOs = blocks.map { block in
            TimeBlockDTO(
                id: block.id,
                activityID: block.activityID,
                activityName: block.activityName,
                activityColor: block.activityColor,
                startTime: block.startTime,
                endTime: block.endTime,
                remarks: block.remarks,
                blockType: block.blockType,
                duration: block.duration,
                switchCount: block.switchCount,
                totalPauseDuration: block.totalPauseDuration
            )
        }
        
        let activityDTOs = activities.map { act in
            ActivityDTO(id: act.id, name: act.name, emoji: act.emoji, color: act.color, setID: act.setID, sortOrder: act.sortOrder)
        }
        
        let setDTOs = sets.map { set in
            ActivitySetDTO(id: set.id, name: set.name, isActive: set.isActive)
        }
        
        // 3. Create Backup Object
        let metadata = BackupMetadata(
            exportDate: Date(),
            recordCount: blockDTOs.count,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
        
        let backup = BackupData(
            metadata: metadata,
            activities: activityDTOs,
            activitySets: setDTOs,
            timeBlocks: blockDTOs
        )
        
        // 4. Encode and Write
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(backup)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let timestamp = formatter.string(from: Date())
        let filename = "Cadence_Archive_\(timestamp).json"
        
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        
        return url
    }
    
    // MARK: - Restore (Import JSON)
    func restoreFromArchive(url: URL) throws -> Int {
        // 1. Decode
        // Access security scoped resource if necessary (for picking files outside sandbox)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let backup = try decoder.decode(BackupData.self, from: data)
        var restoredCount = 0
        
        // 2. Insert Data
        // Strategy: We strictly add data. We do not delete existing data.
        // We check for ID collisions to prevent duplicates.
        
        // A. Restore Sets
        let existingSetIDs = try Set(modelContext.fetch(FetchDescriptor<ActivitySet>()).map { $0.id })
        for setDTO in backup.activitySets {
            if !existingSetIDs.contains(setDTO.id) {
                let newSet = ActivitySet(name: setDTO.name, isActive: setDTO.isActive)
                newSet.id = setDTO.id // Preserve ID
                modelContext.insert(newSet)
            }
        }
        
        // B. Restore Activities
        let existingActivityIDs = try Set(modelContext.fetch(FetchDescriptor<Activity>()).map { $0.id })
        for actDTO in backup.activities {
            if !existingActivityIDs.contains(actDTO.id) {
                let newActivity = Activity(
                    name: actDTO.name,
                    color: actDTO.color,
                    setID: actDTO.setID,
                    sortOrder: actDTO.sortOrder,
                    emoji: actDTO.emoji
                )
                newActivity.id = actDTO.id // Preserve ID
                modelContext.insert(newActivity)
            }
        }
        
        // C. Restore TimeBlocks
        // This can be slow for large datasets, so we do it in a batch if possible
        let existingBlockIDs = try Set(modelContext.fetch(FetchDescriptor<TimeBlock>()).map { $0.id })
        
        for blockDTO in backup.timeBlocks {
            if !existingBlockIDs.contains(blockDTO.id) {
                let newBlock = TimeBlock(
                    activityID: blockDTO.activityID,
                    activityName: blockDTO.activityName,
                    activityColor: blockDTO.activityColor,
                    activitySetID: nil, // We don't strictly need to link this for archives
                    startTime: blockDTO.startTime,
                    blockType: blockDTO.blockType
                )
                newBlock.id = blockDTO.id
                newBlock.endTime = blockDTO.endTime
                newBlock.remarks = blockDTO.remarks
                newBlock.switchCount = blockDTO.switchCount
                newBlock.totalPauseDuration = blockDTO.totalPauseDuration
                newBlock.stopState = blockDTO.endTime != nil ? "stopped" : "ongoing"
                
                modelContext.insert(newBlock)
                restoredCount += 1
            }
        }
        
        try modelContext.save()
        return restoredCount
    }
    
    // MARK: - Prune
    func deleteRecords(olderThan date: Date) throws -> Int {
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate<TimeBlock> { $0.startTime < date }
        )
        let count = try modelContext.fetchCount(descriptor)
        
        try modelContext.delete(model: TimeBlock.self, where: #Predicate<TimeBlock> { $0.startTime < date })
        try modelContext.save()
        
        return count
    }
}
