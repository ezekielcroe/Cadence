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

                    // Tab 0: Records — raw timeline log
                    RecordsView()
                        .tabItem { Label("Records", systemImage: "timeline.selection") }
                        .tag(0)

                    // Tab 1: Remarks — narrative prose thread + tag search
                    RemarksTimelineView()
                        .tabItem { Label("Remarks", systemImage: "book.pages") }
                        .tag(1)

                    // Tab 2: Timer — center, primary action
                    TrackingView(manager: manager)
                        .tabItem { Label("Timer", systemImage: "timer") }
                        .tag(2)

                    // Tab 3: Reports — periodic summaries
                    ReportsView()
                        .tabItem { Label("Reports", systemImage: "chart.xyaxis.line") }
                        .tag(3)

                    // Tab 4: Settings — includes Sets management
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gear") }
                        .tag(4)
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
        .modelContainer(
            for: [Activity.self, ActivitySet.self, TimeBlock.self, TimeBlockRule.self,
                  Remark.self, DayNote.self],
            inMemory: true
        )
}
