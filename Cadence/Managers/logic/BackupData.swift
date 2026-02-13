//
//  BackupData.swift
//  Cadence
//

import Foundation
import SwiftData

// MARK: - Archive Models (DTOs)

struct BackupData: Codable {
    let metadata: BackupMetadata
    let activities: [ActivityDTO]
    let activitySets: [ActivitySetDTO]
    let timeBlocks: [TimeBlockDTO]
}

struct BackupMetadata: Codable {
    var version: String = "2.0"   // Bumped: blockType removed, pauseCount added
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
    let activityID: UUID        // Non-optional: only activity blocks are archived
    let activityName: String
    let activityColor: String
    let activitySetID: UUID?
    let startTime: Date
    let endTime: Date?
    let remarks: String
    let switchCount: Int
    let pauseCount: Int
    let totalPauseDuration: TimeInterval
    let stopState: String
}

// MARK: - Manager Class

class DataArchiveManager {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Export

    func createArchive(olderThan date: Date? = nil) throws -> URL {
        // Fetch blocks, filtered by date if provided
        let blockDescriptor = FetchDescriptor<TimeBlock>(
            predicate: date != nil ? #Predicate<TimeBlock> { $0.startTime < date! } : nil
        )
        let blocks     = try modelContext.fetch(blockDescriptor)
        let activities = try modelContext.fetch(FetchDescriptor<Activity>())
        let sets       = try modelContext.fetch(FetchDescriptor<ActivitySet>())

        // Only archive real activity blocks — gaps are computed and need not be stored
        let blockDTOs: [TimeBlockDTO] = blocks.compactMap { block in
            guard let activityID = block.activityID else { return nil }
            return TimeBlockDTO(
                id:                  block.id,
                activityID:          activityID,
                activityName:        block.activityName,
                activityColor:       block.activityColor,
                activitySetID:       block.activitySetID,
                startTime:           block.startTime,
                endTime:             block.endTime,
                remarks:             block.remarks,
                switchCount:         block.switchCount,
                pauseCount:          block.pauseCount,
                totalPauseDuration:  block.totalPauseDuration,
                stopState:           block.stopState
            )
        }

        let activityDTOs = activities.map { act in
            ActivityDTO(
                id:        act.id,
                name:      act.name,
                emoji:     act.emoji,
                color:     act.color,
                setID:     act.setID,
                sortOrder: act.sortOrder
            )
        }

        let setDTOs = sets.map { set in
            ActivitySetDTO(id: set.id, name: set.name, isActive: set.isActive)
        }

        let metadata = BackupMetadata(
            exportDate:  Date(),
            recordCount: blockDTOs.count,
            appVersion:  Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )

        let backup = BackupData(
            metadata:      metadata,
            activities:    activityDTOs,
            activitySets:  setDTOs,
            timeBlocks:    blockDTOs
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy  = .iso8601
        encoder.outputFormatting      = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let filename = "Cadence_Archive_\(formatter.string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)

        return url
    }

    // MARK: - Import

    func restoreFromArchive(url: URL) throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data    = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupData.self, from: data)

        var restoredCount = 0

        // Restore sets
        let existingSetIDs = try Set(modelContext.fetch(FetchDescriptor<ActivitySet>()).map { $0.id })
        for dto in backup.activitySets where !existingSetIDs.contains(dto.id) {
            let set    = ActivitySet(name: dto.name, isActive: dto.isActive)
            set.id     = dto.id
            modelContext.insert(set)
        }

        // Restore activities
        let existingActivityIDs = try Set(modelContext.fetch(FetchDescriptor<Activity>()).map { $0.id })
        for dto in backup.activities where !existingActivityIDs.contains(dto.id) {
            let act    = Activity(name: dto.name, color: dto.color, setID: dto.setID, sortOrder: dto.sortOrder, emoji: dto.emoji)
            act.id     = dto.id
            modelContext.insert(act)
        }

        // Restore time blocks
        let existingBlockIDs = try Set(modelContext.fetch(FetchDescriptor<TimeBlock>()).map { $0.id })
        for dto in backup.timeBlocks where !existingBlockIDs.contains(dto.id) {
            let block = TimeBlock(
                activityID:    dto.activityID,
                activityName:  dto.activityName,
                activityColor: dto.activityColor,
                activitySetID: dto.activitySetID,
                startTime:     dto.startTime
            )
            block.id                 = dto.id
            block.endTime            = dto.endTime
            block.remarks            = dto.remarks
            block.switchCount        = dto.switchCount
            block.pauseCount         = dto.pauseCount
            block.totalPauseDuration = dto.totalPauseDuration
            block.stopState          = dto.stopState

            modelContext.insert(block)
            restoredCount += 1
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
