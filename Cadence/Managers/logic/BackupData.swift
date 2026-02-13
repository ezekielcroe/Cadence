import Foundation
import SwiftData

// MARK: - Archive Models (DTOs)

struct BackupData: Codable {
    let metadata: BackupMetadata
    let activities: [ActivityDTO]
    let activitySets: [ActivitySetDTO]
    let timeBlocks: [TimeBlockDTO]
    let remarks: [RemarkDTO]          // NEW
    let dayNotes: [DayNoteDTO]        // NEW
}

struct BackupMetadata: Codable {
    var version: String = "4.0"   // Bumped: Activity.setID → setIDs (many-to-many sets)
    let exportDate: Date
    let recordCount: Int
    let appVersion: String
}

struct ActivityDTO: Codable {
    let id:        UUID
    let name:      String
    let emoji:     String?
    let color:     String
    let setIDs:    [UUID]   // v4.0+: activity can belong to multiple sets
    let sortOrder: Int
    let goalRaw:   String
}

struct ActivitySetDTO: Codable {
    let id: UUID
    let name: String
    let isActive: Bool
}

struct TimeBlockDTO: Codable {
    let id: UUID
    let activityID: UUID
    let activityName: String
    let activityColor: String
    let activitySetID: UUID?
    let startTime: Date
    let endTime: Date?
    let switchCount: Int
    let pauseCount: Int
    let totalPauseDuration: TimeInterval
    let stopState: String
}

// NEW
struct RemarkDTO: Codable {
    let id: UUID
    let timeBlockID: UUID
    let timestamp: Date
    let text: String
    let tags: [String]
}

// NEW
struct DayNoteDTO: Codable {
    let id: UUID
    let date: Date
    let intention: String
    let reflection: String
}

// MARK: - Manager Class

class DataArchiveManager {
    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Export

    func createArchive(olderThan date: Date? = nil) throws -> URL {
        let blockDescriptor = FetchDescriptor<TimeBlock>(
            predicate: date != nil ? #Predicate<TimeBlock> { $0.startTime < date! } : nil
        )
        let blocks     = try modelContext.fetch(blockDescriptor)
        let activities = try modelContext.fetch(FetchDescriptor<Activity>())
        let sets       = try modelContext.fetch(FetchDescriptor<ActivitySet>())
        let allRemarks = try modelContext.fetch(FetchDescriptor<Remark>())
        let allNotes   = try modelContext.fetch(FetchDescriptor<DayNote>())

        let blockIDs = Set(blocks.map { $0.id })

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
                switchCount:         block.switchCount,
                pauseCount:          block.pauseCount,
                totalPauseDuration:  block.totalPauseDuration,
                stopState:           block.stopState
            )
        }

        // Only archive remarks that belong to blocks being archived
        let remarkDTOs: [RemarkDTO] = allRemarks
            .filter { blockIDs.contains($0.timeBlockID) }
            .map { r in
                RemarkDTO(id: r.id, timeBlockID: r.timeBlockID,
                          timestamp: r.timestamp, text: r.text, tags: r.tags)
            }

        // Archive day notes within the same date range if filtered
        let noteDTOs: [DayNoteDTO]
        if let cutoff = date {
            noteDTOs = allNotes
                .filter { $0.date < cutoff }
                .map { n in DayNoteDTO(id: n.id, date: n.date, intention: n.intention, reflection: n.reflection) }
        } else {
            noteDTOs = allNotes.map { n in
                DayNoteDTO(id: n.id, date: n.date, intention: n.intention, reflection: n.reflection)
            }
        }

        let activityDTOs = activities.map { act in
            ActivityDTO(id: act.id, name: act.name, emoji: act.emoji,
                        color: act.color, setIDs: act.sets.map { $0.id },
                        sortOrder: act.sortOrder, goalRaw: act.goalRaw)
        }
        let setDTOs = sets.map { ActivitySetDTO(id: $0.id, name: $0.name, isActive: $0.isActive) }

        let metadata = BackupMetadata(
            exportDate:  Date(),
            recordCount: blockDTOs.count,
            appVersion:  Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )

        let backup = BackupData(
            metadata: metadata, activities: activityDTOs, activitySets: setDTOs,
            timeBlocks: blockDTOs, remarks: remarkDTOs, dayNotes: noteDTOs
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting     = [.prettyPrinted, .sortedKeys]
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

        // Restore sets first, then build a lookup for relationship wiring
        let existingSetIDs = try Set(modelContext.fetch(FetchDescriptor<ActivitySet>()).map { $0.id })
        for dto in backup.activitySets where !existingSetIDs.contains(dto.id) {
            let set    = ActivitySet(name: dto.name, isActive: dto.isActive)
            set.id     = dto.id
            modelContext.insert(set)
        }
        // Flush so the sets are queryable for relationship wiring below
        try modelContext.save()

        // Build set lookup from everything now in the store
        let allSets     = try modelContext.fetch(FetchDescriptor<ActivitySet>())
        let setByID     = Dictionary(uniqueKeysWithValues: allSets.map { ($0.id, $0) })

        // Restore activities and wire set memberships
        let existingActivityIDs = try Set(modelContext.fetch(FetchDescriptor<Activity>()).map { $0.id })
        for dto in backup.activities where !existingActivityIDs.contains(dto.id) {
            let act        = Activity(name: dto.name, color: dto.color,
                                      sortOrder: dto.sortOrder, emoji: dto.emoji)
            act.id         = dto.id
            act.goalRaw    = dto.goalRaw
            act.sets       = dto.setIDs.compactMap { setByID[$0] }
            modelContext.insert(act)
        }

        // Restore time blocks
        let existingBlockIDs = try Set(modelContext.fetch(FetchDescriptor<TimeBlock>()).map { $0.id })
        for dto in backup.timeBlocks where !existingBlockIDs.contains(dto.id) {
            let block = TimeBlock(activityID: dto.activityID, activityName: dto.activityName,
                                  activityColor: dto.activityColor, activitySetID: dto.activitySetID,
                                  startTime: dto.startTime)
            block.id                 = dto.id
            block.endTime            = dto.endTime
            block.switchCount        = dto.switchCount
            block.pauseCount         = dto.pauseCount
            block.totalPauseDuration = dto.totalPauseDuration
            block.stopState          = dto.stopState
            modelContext.insert(block)
            restoredCount += 1
        }

        // Restore remarks
        let existingRemarkIDs = try Set(modelContext.fetch(FetchDescriptor<Remark>()).map { $0.id })
        for dto in backup.remarks where !existingRemarkIDs.contains(dto.id) {
            let remark = Remark(timeBlockID: dto.timeBlockID, text: dto.text, timestamp: dto.timestamp)
            remark.id  = dto.id
            modelContext.insert(remark)
        }

        // Restore day notes
        let existingNoteIDs = try Set(modelContext.fetch(FetchDescriptor<DayNote>()).map { $0.id })
        for dto in backup.dayNotes where !existingNoteIDs.contains(dto.id) {
            let note = DayNote(date: dto.date, intention: dto.intention, reflection: dto.reflection)
            note.id  = dto.id
            modelContext.insert(note)
        }

        try modelContext.save()
        return restoredCount
    }

    // MARK: - Prune

    func deleteRecords(olderThan date: Date) throws -> Int {
        // Fetch block IDs being pruned so we can also prune their remarks
        let descriptor = FetchDescriptor<TimeBlock>(
            predicate: #Predicate<TimeBlock> { $0.startTime < date }
        )
        let blocksToDelete = try modelContext.fetch(descriptor)
        let blockIDs = Set(blocksToDelete.map { $0.id })
        let count = blocksToDelete.count

        // Delete associated remarks
        let remarkDescriptor = FetchDescriptor<Remark>()
        let remarks = try modelContext.fetch(remarkDescriptor)
        for remark in remarks where blockIDs.contains(remark.timeBlockID) {
            modelContext.delete(remark)
        }

        // Delete day notes in range
        try modelContext.delete(model: DayNote.self, where: #Predicate<DayNote> { $0.date < date })

        // Delete time blocks
        try modelContext.delete(model: TimeBlock.self, where: #Predicate<TimeBlock> { $0.startTime < date })

        try modelContext.save()
        return count
    }
}
