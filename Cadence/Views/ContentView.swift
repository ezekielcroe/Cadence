import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var timeTrackingManager: TimeTrackingManager?
    @State private var selectedTab = 0
    
    var body: some View {
        Group {
            if let manager = timeTrackingManager {
                TabView(selection: $selectedTab) {
                    // Main tracking view
                    TrackingView(manager: manager)
                        .tabItem {
                            Label("Track", systemImage: "timer")
                        }
                        .tag(0)
                    
                    // Records view
                    RecordsView()
                        .tabItem {
                            Label("Records", systemImage: "list.bullet.rectangle")
                        }
                        .tag(1)
                    
                    // NEW: Reports
                    ReportsView()
                        .tabItem {
                            Label("Reports", systemImage: "chart.xyaxis.line")
                        }
                        .tag(2)
                    
                    // Stats and charts (Today only - keep for quick daily view)
                    StatsView(manager: manager)
                        .tabItem {
                            Label("Today", systemImage: "chart.bar")
                        }
                        .tag(3)
                    
                    // Sets and time blocks
                    SetsView()
                        .tabItem {
                            Label("Sets", systemImage: "square.grid.2x2")
                        }
                        .tag(4)
                    
                    // Settings
                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(5)
                }
            } else {
                ProgressView("Loading...")
                    .onAppear {
                        timeTrackingManager = TimeTrackingManager(modelContext: modelContext)
                    }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Activity.self, ActivitySet.self, TimeBlock.self, TimeBlockRule.self], inMemory: true)
}
