import SwiftUI
import SwiftData
import UserNotifications

@main
struct CadenceApp: App {
    private let notificationDelegate = NotificationDelegate()
    let modelContainer: ModelContainer
    
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    init() {
        do {
            let schema = Schema([
                Activity.self,
                ActivitySet.self,
                TimeBlock.self,
                TimeBlockRule.self,
                Remark.self,
                DayNote.self
            ])
            
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
            )
            
            setupDefaultData()
            requestNotificationPermissions()
            UNUserNotificationCenter.current().delegate = notificationDelegate
            JournalNotificationManager.shared.rescheduleAll()
            
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
        
        // Check if data exists
        let existingSets = (try? context.fetch(FetchDescriptor<ActivitySet>())) ?? []
        guard existingSets.isEmpty else { return }
        
        // MARK: 1. Create Sets
        let workSet     = ActivitySet(name: "Work",     isActive: true)
        let personalSet = ActivitySet(name: "Personal", isActive: false) // [cite: 13]
        
        context.insert(workSet)
        context.insert(personalSet)
        
        // MARK: 2. Create Shared Activities
        // These are activities that apply to multiple contexts.
        // We create them once so they share the same history and stats regardless of which mode is active.
        let commuteActivity = Activity(name: "Commute", color: "#607D8B", emoji: "🚗")
        let mealsActivity   = Activity(name: "Meals",   color: "#8BC34A", emoji: "🍽️") // Merges "Lunch" and "Eating"
        
        context.insert(commuteActivity)
        context.insert(mealsActivity)
        
        // MARK: 3. Work Specific Activities
        // Note: Removed "Commute" and "Lunch" from here as they are now shared
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
            ("Break",        "#795548", "☕"),
        ]
        
        var workActivitiesArray: [Activity] = []
        
        // Add specific work activities
        for (i, a) in workActivitiesData.enumerated() {
            let activity = Activity(name: a.0, color: a.1, sortOrder: i, emoji: a.2) // [cite: 16]
            context.insert(activity)
            workActivitiesArray.append(activity)
        }
        
        // Add shared activities to Work
        workActivitiesArray.append(mealsActivity)
        workActivitiesArray.append(commuteActivity)
        
        // Assign to Set
        workSet.activities = workActivitiesArray
        
        // MARK: 4. Personal Specific Activities
        let personalActivitiesData: [(String, String, String)] = [
            ("Sleep",         "#3F51B5", "😴"),
            ("Exercise",      "#F44336", "💪"),
            ("Self-Care",     "#E91E63", "🧘"),
            ("Cooking",       "#FF5722", "👨‍🍳"),
            ("Family",        "#E91E63", "👨‍👩‍👧"),
            ("Socializing",   "#9C27B0", "🎉"),
            ("Chores",        "#607D8B", "🧹"),
            ("Entertainment", "#673AB7", "📺"),
            ("Hobbies",       "#009688", "🎨"),
            ("Downtime",      "#795548", "🛋️"),
        ]
        
        var personalActivitiesArray: [Activity] = []
        
        // Add specific personal activities
        for (i, a) in personalActivitiesData.enumerated() {
            let activity = Activity(name: a.0, color: a.1, sortOrder: i, emoji: a.2) // [cite: 20]
            context.insert(activity)
            personalActivitiesArray.append(activity)
        }
        
        personalActivitiesArray.append(mealsActivity)
        personalActivitiesArray.append(commuteActivity)
        
        // Assign to Set
        personalSet.activities = personalActivitiesArray
        
        // MARK: 5. Time Block Rules
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
            daysOfWeek: []
        ))
        
        context.insert(TimeBlockRule(
            name: "Personal Time",
            startTime: personalStart,
            endTime: personalEnd,
            linkedSetID: personalSet.id,
            daysOfWeek: []
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
