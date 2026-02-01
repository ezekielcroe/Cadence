import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var timeTrackingManager: TimeTrackingManager?
    @State private var selectedTab = 2 // Default to Timer
    
    var body: some View {
        Group {
            if let manager = timeTrackingManager {
                TabView(selection: $selectedTab) {
                    
                    // Tab 0: Sets
                    SetsView()
                        .tabItem {
                            Label("Sets", systemImage: "square.grid.2x2")
                        }
                        .tag(0)
                    
                    // Tab 1: Records
                    RecordsView()
                        .tabItem {
                            Label("Records", systemImage: "list.bullet.rectangle")
                        }
                        .tag(1)
                    
                    // Tab 2: TIMER (Center)
                    TrackingView(manager: manager)
                        .tabItem {
                            Label("Timer", systemImage: "timer")
                        }
                        .tag(2)
                    
                    // Tab 3: Reports
                    ReportsView()
                        .tabItem {
                            Label("Reports", systemImage: "chart.xyaxis.line")
                        }
                        .tag(3)
                    
                    // Tab 4: Settings
                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(4)
                }
            } else {
                ProgressView("Loading Cadence...")
                    .onAppear {
                        // Initialize manager on first load
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
