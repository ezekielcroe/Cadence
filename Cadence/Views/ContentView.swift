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
                    
                    // Today's timeline
                    TimelineView(manager: manager)
                        .tabItem {
                            Label("Timeline", systemImage: "list.bullet")
                        }
                        .tag(1)
                    
                    // Stats and charts
                    StatsView(manager: manager)
                        .tabItem {
                            Label("Stats", systemImage: "chart.bar")
                        }
                        .tag(2)
                    
                    // Settings and activity management
                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(3)
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
        .modelContainer(for: [Activity.self, ActivitySet.self, TimeBlock.self], inMemory: true)
}
