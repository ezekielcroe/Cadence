import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var timeTrackingManager: TimeTrackingManager?
    @State private var selectedTab = 0 // Today

    var body: some View {
        Group {
            if let manager = timeTrackingManager {
                TabView(selection: $selectedTab) {

                    // Tab 0: Today — the day so far, the "now" card and the activity grid
                    TodayView(manager: manager)
                        .tabItem { Label("Today", systemImage: "sun.max") }
                        .tag(0)

                    // Tab 1: Journal — past days as diary pages, or the Ledger to edit them
                    JournalView()
                        .tabItem { Label("Journal", systemImage: "book") }
                        .tag(1)

                    // Tab 2: Insights — periodic summaries
                    ReportsView()
                        .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
                        .tag(2)

                    // Tab 3: Settings — includes Sets management
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gear") }
                        .tag(3)
                }
            } else {
                ProgressView("Loading Cadence...")
                    .onAppear {
                        timeTrackingManager = TimeTrackingManager(modelContext: modelContext)
                    }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(try! CadenceSchema.makeContainer(inMemory: true))
}
