import SwiftUI
import SwiftData
import UserNotifications

@main
struct CadenceApp: App {
    let modelContainer: ModelContainer
    
    // 1. Listen for the theme setting
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    init() {
        do {
            // Configure SwiftData model container
            let schema = Schema([
                Activity.self,
                ActivitySet.self,
                TimeBlock.self,
                TimeBlockRule.self
            ])
            
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            
            // Create default activity sets if needed
            setupDefaultData()
            
            // Request notification permissions
            requestNotificationPermissions()
            
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                // 2. Apply the theme to the entire window
                .preferredColorScheme(appTheme.colorScheme)
        }
    }
    
    @MainActor
    private func setupDefaultData() {
        let context = modelContainer.mainContext
        
        // Check if we already have sets
        let descriptor = FetchDescriptor<ActivitySet>()
        let existingSets = (try? context.fetch(descriptor)) ?? []
        
        if existingSets.isEmpty {
            // Create default sets
            let workSet = ActivitySet(name: "Work", isActive: true)
            let personalSet = ActivitySet(name: "Personal", isActive: false)
            let weekendSet = ActivitySet(name: "Weekend", isActive: false)
            
            context.insert(workSet)
            context.insert(personalSet)
            context.insert(weekendSet)
            
            // MARK: - Work Activities (12 items)
            let defaultWorkActivities: [(name: String, color: String, emoji: String)] = [
                ("Focused Work", "#4CAF50", "🎯"),
                ("Meetings", "#2196F3", "👥"),
                ("Calls", "#03A9F4", "📞"),
                ("Email", "#FF9800", "📧"),
                ("Messaging", "#FFC107", "💬"),
                ("Admin", "#9E9E9E", "📋"),
                ("Planning", "#9C27B0", "📝"),
                ("Research", "#673AB7", "🔍"),
                ("Learning", "#3F51B5", "📚"),
                ("Lunch", "#8BC34A", "🍽️"),
                ("Break", "#795548", "☕"),
                ("Commute", "#607D8B", "🚗"),
            ]
            
            for (index, activity) in defaultWorkActivities.enumerated() {
                context.insert(Activity(name: activity.name, color: activity.color, setID: workSet.id, sortOrder: index, emoji: activity.emoji))
            }
            
            // MARK: - Personal Activities
            let defaultPersonalActivities: [(name: String, color: String, emoji: String)] = [
                ("Sleep", "#3F51B5", "😴"),
                ("Exercise", "#F44336", "💪"),
                ("Self-Care", "#E91E63", "🧘"),
                ("Eating", "#FF9800", "🍽️"),
                ("Cooking", "#FF5722", "👨‍🍳"),
                ("Family", "#E91E63", "👨‍👩‍👧"),
                ("Socializing", "#9C27B0", "🎉"),
                ("Chores", "#607D8B", "🧹"),
                ("Travel", "#9E9E9E", "🚶"),
                ("Entertainment", "#673AB7", "📺"),
                ("Hobbies", "#009688", "🎨"),
                ("Downtime", "#795548", "🛋️"),
            ]
            
            for (index, activity) in defaultPersonalActivities.enumerated() {
                context.insert(Activity(name: activity.name, color: activity.color, setID: personalSet.id, sortOrder: index, emoji: activity.emoji))
            }
            
            // MARK: - Weekend Activities
            let defaultWeekendActivities: [(name: String, color: String, emoji: String)] = [
                ("Sleep", "#3F51B5", "😴"),
                ("Eating", "#FF9800", "🍽️"),
                ("Cooking", "#FF5722", "👨‍🍳"),
                ("Exercise", "#F44336", "💪"),
                ("Outdoors", "#4CAF50", "🌳"),
                ("Family", "#E91E63", "👨‍👩‍👧"),
                ("Socializing", "#9C27B0", "🍻"),
                ("Chores", "#607D8B", "🧹"),
                ("Errands", "#8BC34A", "🛒"),
                ("Travel", "#9E9E9E", "🚗"),
                ("Entertainment", "#673AB7", "📺"),
                ("Hobbies", "#009688", "🎨"),
            ]
            
            for (index, activity) in defaultWeekendActivities.enumerated() {
                context.insert(Activity(name: activity.name, color: activity.color, setID: weekendSet.id, sortOrder: index, emoji: activity.emoji))
            }
            
            // MARK: - Time Block Rules
            let calendar = Calendar.current
            
            // Default Rules Setup...
            let workStart = calendar.date(from: DateComponents(hour: 8, minute: 30))!
            let workEnd = calendar.date(from: DateComponents(hour: 18, minute: 0))!
            let personalStart = calendar.date(from: DateComponents(hour: 18, minute: 0))!
            let personalEnd = calendar.date(from: DateComponents(hour: 23, minute: 0))!
            let weekendDayStart = calendar.date(from: DateComponents(hour: 9, minute: 0))!
            let weekendDayEnd = calendar.date(from: DateComponents(hour: 18, minute: 0))!
            
            context.insert(TimeBlockRule(name: "Work Hours", startTime: workStart, endTime: workEnd, linkedSetID: workSet.id, daysOfWeek: [2, 3, 4, 5, 6], trackingMode: .on))
            context.insert(TimeBlockRule(name: "Personal Time", startTime: personalStart, endTime: personalEnd, linkedSetID: personalSet.id, daysOfWeek: [], trackingMode: .off))
            context.insert(TimeBlockRule(name: "Weekend Day", startTime: weekendDayStart, endTime: weekendDayEnd, linkedSetID: weekendSet.id, daysOfWeek: [1, 7], trackingMode: .off))
            
            try? context.save()
        }
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
}
