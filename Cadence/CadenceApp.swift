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
                TimeBlockRule.self,
                Remark.self,       // NEW: first-class remarks
                DayNote.self       // NEW: daily intention + reflection
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

        let existingSets = (try? context.fetch(FetchDescriptor<ActivitySet>())) ?? []
        guard existingSets.isEmpty else { return }

        // MARK: Sets
        let workSet     = ActivitySet(name: "Work",     isActive: true)
        let personalSet = ActivitySet(name: "Personal", isActive: false)

        context.insert(workSet)
        context.insert(personalSet)

        // MARK: Work Activities
        let workActivitiesData: [(String, String, String)] = [
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
        var workActivitiesArray: [Activity] = []
        for (i, a) in workActivitiesData.enumerated() {
            let activity = Activity(name: a.0, color: a.1, sortOrder: i, emoji: a.2)
            context.insert(activity)
            workActivitiesArray.append(activity)
        }
        workSet.activities = workActivitiesArray

        // MARK: Personal Activities
        let personalActivitiesData: [(String, String, String)] = [
            ("Sleep",         "#3F51B5", "😴"),
            ("Exercise",      "#F44336", "💪"),
            ("Self-Care",     "#E91E63", "🧘"),
            ("Eating",        "#FF9800", "🍽️"),
            ("Cooking",       "#FF5722", "👨‍🍳"),
            ("Family",        "#E91E63", "👨‍👩‍👧"),
            ("Socializing",   "#9C27B0", "🎉"),
            ("Chores",        "#607D8B", "🧹"),
            ("Travel",        "#9E9E9E", "🚶"),
            ("Entertainment", "#673AB7", "📺"),
            ("Hobbies",       "#009688", "🎨"),
            ("Downtime",      "#795548", "🛋️"),
        ]
        var personalActivitiesArray: [Activity] = []
        for (i, a) in personalActivitiesData.enumerated() {
            let activity = Activity(name: a.0, color: a.1, sortOrder: i, emoji: a.2)
            context.insert(activity)
            personalActivitiesArray.append(activity)
        }
        personalSet.activities = personalActivitiesArray

        // MARK: Time Block Rules
        let calendar = Calendar.current

        let workStart     = calendar.date(from: DateComponents(hour: 8,  minute: 30))!
        let workEnd       = calendar.date(from: DateComponents(hour: 18, minute: 0))!
        let personalStart = calendar.date(from: DateComponents(hour: 18, minute: 0))!
        let personalEnd   = calendar.date(from: DateComponents(hour: 8, minute: 30))!

        context.insert(TimeBlockRule(
            name: "Work Hours",
            startTime: workStart,
            endTime: workEnd,
            linkedSetID: workSet.id,
            daysOfWeek: [],
            trackingMode: .on
        ))
        context.insert(TimeBlockRule(
            name: "Personal Time",
            startTime: personalStart,
            endTime: personalEnd,
            linkedSetID: personalSet.id,
            daysOfWeek: [],
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
