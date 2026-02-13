import SwiftUI
import SwiftData
import UserNotifications

@main
struct CadenceApp: App {
    let modelContainer: ModelContainer

    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    init() {
        do {
            let schema = Schema([
                Activity.self,
                ActivitySet.self,
                TimeBlock.self,
                TimeBlockRule.self
            ])

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
            )

            setupDefaultData()
            requestNotificationPermissions()

        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .preferredColorScheme(appTheme.colorScheme)
        }
    }

    // MARK: - First Launch Setup

    @MainActor
    private func setupDefaultData() {
        let context = modelContainer.mainContext

        // Only seed default content on a completely fresh install
        let existingSets = (try? context.fetch(FetchDescriptor<ActivitySet>())) ?? []
        guard existingSets.isEmpty else { return }

        // MARK: Sets

        let workSet    = ActivitySet(name: "Work",     isActive: true)
        let personalSet = ActivitySet(name: "Personal", isActive: false)
        let weekendSet  = ActivitySet(name: "Weekend",  isActive: false)

        context.insert(workSet)
        context.insert(personalSet)
        context.insert(weekendSet)

        // MARK: Work Activities

        let workActivities: [(String, String, String)] = [
            ("Focused Work", "#4CAF50", "🎯"),
            ("Meetings",     "#2196F3", "👥"),
            ("Calls",        "#03A9F4", "📞"),
            ("Email",        "#FF9800", "📧"),
            ("Messaging",    "#FFC107", "💬"),
            ("Admin",        "#9E9E9E", "📋"),
            ("Planning",     "#9C27B0", "📝"),
            ("Research",     "#673AB7", "🔍"),
            ("Learning",     "#3F51B5", "📚"),
            ("Lunch",        "#8BC34A", "🍽️"),
            ("Break",        "#795548", "☕"),
            ("Commute",      "#607D8B", "🚗"),
        ]
        for (i, a) in workActivities.enumerated() {
            context.insert(Activity(name: a.0, color: a.1, setID: workSet.id, sortOrder: i, emoji: a.2))
        }

        // MARK: Personal Activities

        let personalActivities: [(String, String, String)] = [
            ("Sleep",          "#3F51B5", "😴"),
            ("Exercise",       "#F44336", "💪"),
            ("Self-Care",      "#E91E63", "🧘"),
            ("Eating",         "#FF9800", "🍽️"),
            ("Cooking",        "#FF5722", "👨‍🍳"),
            ("Family",         "#E91E63", "👨‍👩‍👧"),
            ("Socializing",    "#9C27B0", "🎉"),
            ("Chores",         "#607D8B", "🧹"),
            ("Travel",         "#9E9E9E", "🚶"),
            ("Entertainment",  "#673AB7", "📺"),
            ("Hobbies",        "#009688", "🎨"),
            ("Downtime",       "#795548", "🛋️"),
        ]
        for (i, a) in personalActivities.enumerated() {
            context.insert(Activity(name: a.0, color: a.1, setID: personalSet.id, sortOrder: i, emoji: a.2))
        }

        // MARK: Weekend Activities

        let weekendActivities: [(String, String, String)] = [
            ("Sleep",          "#3F51B5", "😴"),
            ("Eating",         "#FF9800", "🍽️"),
            ("Cooking",        "#FF5722", "👨‍🍳"),
            ("Exercise",       "#F44336", "💪"),
            ("Outdoors",       "#4CAF50", "🌳"),
            ("Family",         "#E91E63", "👨‍👩‍👧"),
            ("Socializing",    "#9C27B0", "🍻"),
            ("Chores",         "#607D8B", "🧹"),
            ("Errands",        "#8BC34A", "🛒"),
            ("Travel",         "#9E9E9E", "🚗"),
            ("Entertainment",  "#673AB7", "📺"),
            ("Hobbies",        "#009688", "🎨"),
        ]
        for (i, a) in weekendActivities.enumerated() {
            context.insert(Activity(name: a.0, color: a.1, setID: weekendSet.id, sortOrder: i, emoji: a.2))
        }

        // MARK: Time Block Rules
        //
        // TrackingMode now controls set auto-switching only — gap creation is no longer
        // a tracking-mode concept. All three rules use .on so their linked sets become
        // active when the time window is entered.

        let calendar = Calendar.current

        let workStart      = calendar.date(from: DateComponents(hour: 8,  minute: 30))!
        let workEnd        = calendar.date(from: DateComponents(hour: 18, minute: 0))!
        let personalStart  = calendar.date(from: DateComponents(hour: 18, minute: 0))!
        let personalEnd    = calendar.date(from: DateComponents(hour: 23, minute: 0))!
        let weekendStart   = calendar.date(from: DateComponents(hour: 9,  minute: 0))!
        let weekendEnd     = calendar.date(from: DateComponents(hour: 18, minute: 0))!

        context.insert(TimeBlockRule(
            name: "Work Hours",
            startTime: workStart,
            endTime: workEnd,
            linkedSetID: workSet.id,
            daysOfWeek: [2, 3, 4, 5, 6],   // Mon–Fri
            trackingMode: .on
        ))
        context.insert(TimeBlockRule(
            name: "Personal Time",
            startTime: personalStart,
            endTime: personalEnd,
            linkedSetID: personalSet.id,
            daysOfWeek: [],                  // Every day
            trackingMode: .on
        ))
        context.insert(TimeBlockRule(
            name: "Weekend Day",
            startTime: weekendStart,
            endTime: weekendEnd,
            linkedSetID: weekendSet.id,
            daysOfWeek: [1, 7],              // Sun & Sat
            trackingMode: .on
        ))

        try? context.save()
    }

    // MARK: - Permissions

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error { print("Notification permission error: \(error)") }
        }
    }
}
