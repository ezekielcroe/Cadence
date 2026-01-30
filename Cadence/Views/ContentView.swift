// MARK: - Updated ContentView with Reorganized Tabs

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
                    
                    // Sets and time blocks
                    SetsView()
                        .tabItem {
                            Label("Sets", systemImage: "square.grid.2x2")
                        }
                        .tag(3)
                    
                    // Records view
                    RecordsView()
                        .tabItem {
                            Label("Records", systemImage: "list.bullet.rectangle")
                        }
                        .tag(0)
                    
                    // TIMER - CENTRAL TAB (most important)
                    TrackingView(manager: manager)
                        .tabItem {
                            Label("Timer", systemImage: "timer")
                        }
                        .tag(2)
                    
                    // Reports view
                    ReportsView()
                        .tabItem {
                            Label("Reports", systemImage: "chart.xyaxis.line")
                        }
                        .tag(1)
                    
                    // Settings
                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(4)
                }
                .onAppear {
                    // Set Timer as default selected tab
                    selectedTab = 2
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
