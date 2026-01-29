import SwiftUI
import SwiftData
import UserNotifications

@main
struct CadenceApp: App {
    let modelContainer: ModelContainer
    
    init() {
        do {
            // Configure SwiftData model container
            let schema = Schema([
                Activity.self,
                ActivitySet.self,
                TimeBlock.self
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
            
            context.insert(workSet)
            context.insert(personalSet)
            
            // Create some default activities for Work set
            let defaultWorkActivities = [
                ("Deep Work", "#4CAF50"),
                ("Meetings", "#2196F3"),
                ("Email", "#FF9800"),
                ("Planning", "#9C27B0"),
                ("Break", "#607D8B")
            ]
            
            for (index, (name, color)) in defaultWorkActivities.enumerated() {
                let activity = Activity(
                    name: name,
                    color: color,
                    setID: workSet.id,
                    sortOrder: index
                )
                context.insert(activity)
            }
            
            // Create some default activities for Personal set
            let defaultPersonalActivities = [
                ("Exercise", "#F44336"),
                ("Reading", "#3F51B5"),
                ("Family Time", "#E91E63"),
                ("Hobbies", "#00BCD4"),
                ("Rest", "#795548")
            ]
            
            for (index, (name, color)) in defaultPersonalActivities.enumerated() {
                let activity = Activity(
                    name: name,
                    color: color,
                    setID: personalSet.id,
                    sortOrder: index
                )
                context.insert(activity)
            }
            
            try? context.save()
        }
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
}
