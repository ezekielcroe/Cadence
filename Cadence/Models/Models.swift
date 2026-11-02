import Foundation
import SwiftData

// MARK: - Activity Goal Enum

enum ActivityGoal: String, Codable, CaseIterable {
    case increase = "increase"
    case decrease = "decrease"
    case neutral  = "neutral"

    var displayName: String {
        switch self {
        case .increase: return "Keep High"
        case .decrease: return "Keep Low"
        case .neutral:  return "Neutral"
        }
    }

    var icon: String {
        switch self {
        case .increase: return "arrow.up.circle"
        case .decrease: return "arrow.down.circle"
        case .neutral:  return "minus.circle"
        }
    }

    var color: String {
        switch self {
        case .increase: return "#4CAF50"
        case .decrease: return "#F44336"
        case .neutral:  return "#9E9E9E"
        }
    }
}

// MARK: - Remark Model

@Model
final class Remark {
    var id:          UUID
    var timeBlockID: UUID
    var timestamp:   Date
    var text:        String
    var tags:        [String]

    init(timeBlockID: UUID, text: String, timestamp: Date = Date()) {
        self.id          = UUID()
        self.timeBlockID = timeBlockID
        self.timestamp   = timestamp
        self.text        = text
        self.tags        = Remark.extractTags(from: text)
    }

    static func extractTags(from text: String) -> [String] {
        let pattern = #"#([a-zA-Z0-9][a-zA-Z0-9\-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]).lowercased() }
        }
    }

    func refreshTags() { tags = Remark.extractTags(from: text) }

    var displayText: String { text }

    var preview: String {
        let first = text.components(separatedBy: "\n").first ?? text
        return first.count > 80 ? String(first.prefix(80)) + "…" : first
    }
}

// MARK: - DayNote Model

@Model
final class DayNote {
    var id:         UUID
    var date:       Date    // normalized to startOfDay
    var intention:  String
    var reflection: String

    var intentionUpdatedAt:  Date?
    var reflectionUpdatedAt: Date?

    init(date: Date, intention: String = "", reflection: String = "") {
        self.id         = UUID()
        self.date       = Calendar.current.startOfDay(for: date)
        self.intention  = intention
        self.reflection = reflection
        self.intentionUpdatedAt  = intention.isEmpty  ? nil : Date()
        self.reflectionUpdatedAt = reflection.isEmpty ? nil : Date()
    }

    static func normalizedDate(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}

// MARK: - Activity Model

@Model
final class Activity {
    var id:        UUID
    var name:      String
    var emoji:     String?
    var color:     String
    var createdAt: Date
    var sortOrder: Int
    var goalRaw:   String = "neutral"

    var goal: ActivityGoal {
        get { ActivityGoal(rawValue: goalRaw) ?? .neutral }
        set { goalRaw = newValue.rawValue }
    }

    @Relationship(inverse: \ActivitySet.activities)
    var sets: [ActivitySet] = []

    init(name: String, color: String, sortOrder: Int = 0, emoji: String? = nil, goal: ActivityGoal = .neutral) {
        self.id        = UUID()
        self.name      = name
        self.emoji     = emoji
        self.color     = color
        self.createdAt = Date()
        self.sortOrder = sortOrder
        self.goalRaw   = goal.rawValue
    }
}

// MARK: - ActivitySet Model

@Model
final class ActivitySet {
    var id:           UUID
    var name:         String
    var isActive:     Bool
    var createdAt:    Date

    @Relationship var activities: [Activity] = []

    init(name: String, isActive: Bool = false) {
        self.id           = UUID()
        self.name         = name
        self.isActive     = isActive
        self.createdAt    = Date()
    }
}

// MARK: - TimeBlockRule Model
// Drives automatic activity-set switching by time of day. The tracking
// window (accountable hours) is a separate concept — see TrackingWindow.swift.

@Model
final class TimeBlockRule {
    var id:              UUID
    var name:            String
    var startTime:       Date
    var endTime:         Date
    var linkedSetID:     UUID?
    var isEnabled:       Bool
    var daysOfWeek:      [Int]
    var createdAt:       Date

    init(name: String, startTime: Date, endTime: Date, linkedSetID: UUID? = nil,
         daysOfWeek: [Int] = []) {
        self.id              = UUID()
        self.name            = name
        self.startTime       = startTime
        self.endTime         = endTime
        self.linkedSetID     = linkedSetID
        self.isEnabled       = true
        self.daysOfWeek      = daysOfWeek
        self.createdAt       = Date()
    }

    func isActiveNow() -> Bool {
        guard isEnabled else { return false }
        let now = Date(); let cal = Calendar.current
        if !daysOfWeek.isEmpty {
            guard daysOfWeek.contains(cal.component(.weekday, from: now)) else { return false }
        }
        let nowC = cal.dateComponents([.hour,.minute], from: now)
        let sC   = cal.dateComponents([.hour,.minute], from: startTime)
        let eC   = cal.dateComponents([.hour,.minute], from: endTime)
        guard let n = nowC.hour.map({ $0*60 + (nowC.minute ?? 0) }),
              let s = sC.hour.map({ $0*60 + (sC.minute ?? 0) }),
              let e = eC.hour.map({ $0*60 + (eC.minute ?? 0) }) else { return false }
        return e < s ? (n >= s || n < e) : (n >= s && n < e)
    }

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var timeRangeDisplay: String {
        let f = Self.shortTimeFormatter
        return "\(f.string(from: startTime)) – \(f.string(from: endTime))"
    }

    var daysOfWeekDisplay: String {
        if daysOfWeek.isEmpty { return "Every day" }
        let names = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        return daysOfWeek.sorted().map { names[$0 - 1] }.joined(separator: ", ")
    }
}

// MARK: - PauseSpan

/// A single pause as an interval in time. `end == nil` means the pause is
/// still open. Persisted per block so pause time can be clipped exactly
/// when a block spans a day boundary, and so timesheets can show breaks.
struct PauseSpan: Codable, Hashable {
    var start: Date
    var end: Date?

    func duration(asOf now: Date = Date()) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

// MARK: - TimeBlock Model

@Model
final class TimeBlock {
    var id:             UUID
    var activityID:     UUID?
    var activityName:   String
    var activityColor:  String
    var activitySetID:  UUID?
    var targetDuration: TimeInterval?

    var startTime:  Date
    var endTime:    Date?

    var isPaused:           Bool
    var pauseStartTime:     Date?
    var pauseCount:         Int

    /// LEGACY. Pre-migration blocks carry their accumulated pause time here.
    /// New code never writes to it — new pauses are recorded in `pauseSpans`.
    /// Total pause time is always read through `pauseDuration`.
    var totalPauseDuration: TimeInterval

    /// Every pause of this block as a dated interval. Source of truth for
    /// pause time on all post-migration blocks.
    var pauseSpans: [PauseSpan] = []

    var stopState:   String         // "ongoing" | "switched" | "stopped"
    var switchCount: Int

    init(activityID: UUID?, activityName: String, activityColor: String,
         activitySetID: UUID?, startTime: Date, targetDuration: TimeInterval? = nil) {
        self.id                 = UUID()
        self.activityID         = activityID
        self.activityName       = activityName
        self.activityColor      = activityColor
        self.activitySetID      = activitySetID
        self.startTime          = startTime
        self.endTime            = nil
        self.isPaused           = false
        self.pauseStartTime     = nil
        self.pauseCount         = 0
        self.totalPauseDuration = 0
        self.pauseSpans         = []
        self.stopState          = "ongoing"
        self.switchCount        = 0
        self.targetDuration     = targetDuration
    }

    convenience init(activity: Activity, startTime: Date, activeSetID: UUID? = nil) {
        self.init(
            activityID:    activity.id,
            activityName:  activity.name,
            activityColor: activity.color,
            activitySetID: activeSetID ?? activity.sets.first(where: { $0.isActive })?.id,
            startTime:     startTime
        )
    }

    /// Total pause time: legacy accumulator + all spans (an open span counts
    /// up to now). Legacy and spans never double-count because writes moved
    /// exclusively to spans at migration.
    var pauseDuration: TimeInterval {
        totalPauseDuration + pauseSpans.reduce(0) { $0 + $1.duration() }
    }

    var duration: TimeInterval {
        let raw = (endTime ?? Date()).timeIntervalSince(startTime)
        return max(0, raw - pauseDuration)
    }

    var remainingDuration: TimeInterval? {
        guard let target = targetDuration else { return nil }
        let remain = target - duration
        return remain > 0 ? remain : 0
    }

    var isActive:    Bool   { endTime == nil && !isPaused }
    var displayName: String { pauseCount > 0 ? "\(activityName) (paused \(pauseCount)×)" : activityName }

    // MARK: Pause mutation
    // All pause writes go through these two so the stored flags and the
    // span array can never disagree.

    func beginPause(at time: Date = Date()) {
        guard !isPaused, endTime == nil else { return }
        isPaused = true
        pauseStartTime = time
        pauseCount += 1
        pauseSpans = pauseSpans + [PauseSpan(start: time)]
    }

    func endPause(at time: Date = Date()) {
        guard isPaused else { return }
        if let idx = pauseSpans.lastIndex(where: { $0.end == nil }) {
            var spans = pauseSpans
            spans[idx].end = max(time, spans[idx].start)
            pauseSpans = spans
        } else if let pauseStart = pauseStartTime {
            // Block was paused before the migration added spans:
            // fall back to the legacy accumulator once.
            totalPauseDuration += max(0, time.timeIntervalSince(pauseStart))
        }
        isPaused = false
        pauseStartTime = nil
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    var formattedDuration: String {
        let clamped = max(0, self)
        let h = Int(clamped)/3600, m = Int(clamped)/60%60, s = Int(clamped)%60
        if h > 0      { return String(format: "%dh %dm", h, m) }
        if m > 0      { return String(format: "%dm %ds", m, s) }
        return          String(format: "%ds", s)
    }

    var detailedFormattedDuration: String {
        let clamped = max(0, self)
        let h = Int(clamped)/3600, m = Int(clamped)/60%60, s = Int(clamped)%60
        return h > 0 ? String(format: "%dh %dm %ds", h, m, s) : String(format: "%dm %ds", m, s)
    }
}

// MARK: - DayStats

struct DayStats {
    let totalDuration:       TimeInterval
    let activityDurations:   [String: TimeInterval]
    let totalSwitches:       Int
    let blockCount:          Int
    let unaccountedDuration: TimeInterval

    var sortedActivities: [(name: String, duration: TimeInterval)] {
        activityDurations.sorted { $0.value > $1.value }.map { (name: $0.key, duration: $0.value) }
    }
}
