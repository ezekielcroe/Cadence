# Cadence - Time-Motion Study for Your Life

**Version:** 1.0.0 MVP  
**Platform:** iOS 17.0+  
**Framework:** SwiftUI + SwiftData

---

## 🎯 What is Cadence?

Cadence is a frictionless time-tracking app that reveals how you *actually* spend your hours. No timers to forget, no start/stop anxiety—just one-tap activity switching that captures your day's true rhythm.

### Core Philosophy
- **Zero friction**: Single tap to switch activities (<2 seconds)
- **Manual logging**: You control what gets tracked (no invasive automation)
- **Honest data**: Every minute has an activity—see patterns, not fantasies
- **No judgment**: No productivity scores, no "ideal day" comparisons

---

## 🚀 MVP Features (Current Implementation)

### ✅ Activity Management
- **Custom Activities**: Define your own activity taxonomy
- **Activity Sets**: Switch between "Work" and "Personal" activity groups
- **Color Coding**: Visual distinction between activities
- **Reorderable**: Drag to arrange activities by priority

### ✅ Time Tracking
- **Single-Tap Switching**: Tap activity → auto-starts, previous auto-ends
- **Pause/Resume**: Track short interruptions without ending the activity
- **Stop Button**: Explicitly end activity without starting a new one
- **Switch Counter**: Measures how fragmented your focus is

### ✅ Current Activity Display
- **Real-time Timer**: See current activity duration
- **Status Indicators**: Active/Paused states clearly shown
- **Quick Controls**: Pause/Resume/Stop always accessible

### ✅ Today's Timeline
- **Chronological View**: List of all time blocks with timestamps
- **Duration Display**: See how long each activity lasted
- **Pause Tracking**: Total pause time per activity shown
- **Switch Count**: Visual indicator of activity fragmentation

### ✅ Statistics & Charts
- **Summary Cards**: Total time, activity count, switches, averages
- **Activity Breakdown**: Horizontal bar chart showing time distribution
- **Timeline Visualization**: Horizontal timeline showing day at a glance
- **Percentage Breakdown**: See what % of your day each activity consumed

### ✅ Data Persistence
- **SwiftData Storage**: All data survives app restart
- **Session Recovery**: Resume tracking if app crashes
- **No Data Loss**: Timestamps saved immediately on switch

---

## 🏗️ Architecture Overview

### Data Layer (SwiftData)
```
Activity
├─ id: UUID
├─ name: String
├─ color: String (hex)
├─ setID: UUID (belongs to which set)
└─ sortOrder: Int

ActivitySet
├─ id: UUID
├─ name: String (e.g., "Work", "Personal")
└─ isActive: Bool (which set is currently shown)

TimeBlock
├─ id: UUID
├─ activityID: UUID
├─ activityName: String (denormalized for queries)
├─ startTime: Date
├─ endTime: Date? (nil = still active)
├─ isPaused: Bool
├─ pauseStartTime: Date?
├─ totalPauseDuration: TimeInterval
└─ switchCount: Int (resumes)
```

### State Management
- **TimeTrackingManager**: Observable class handling all tracking logic
- **Real-time Updates**: 1-second timer for UI refresh
- **State Machine**: Ensures only one activity active at a time

### View Hierarchy
```
ContentView (TabView)
├─ TrackingView (Main tracking interface)
│  ├─ CurrentActivityCard (timer display)
│  ├─ ActivitySetPicker (switch sets)
│  └─ ActivityButton Grid (tap to switch)
├─ TimelineView (Today's activity list)
│  └─ TimeBlockRow (individual entries)
├─ StatsView (Charts and aggregations)
│  ├─ StatCard (summary metrics)
│  ├─ Activity Breakdown Chart
│  └─ Timeline Chart
└─ SettingsView (Activity management)
   ├─ ActivitySet management
   ├─ Activity CRUD
   └─ Color picker
```

---

## 📱 How to Build & Run

### Requirements
- **Xcode 15.0+**
- **iOS 17.0+ Deployment Target**
- **Swift 5.9+**

### Setup Steps

1. **Open Xcode** and create a new iOS App project:
   - Product Name: `Cadence`
   - Interface: SwiftUI
   - Storage: None (we're using SwiftData manually)
   - Language: Swift

2. **Add the source files** in this structure:
   ```
   Cadence/
   ├─ CadenceApp.swift (app entry point)
   ├─ Models/
   │  └─ Models.swift
   ├─ Managers/
   │  └─ TimeTrackingManager.swift
   └─ Views/
      ├─ ContentView.swift
      ├─ TrackingView.swift
      ├─ TimelineView.swift
      ├─ StatsView.swift
      └─ SettingsView.swift
   ```

3. **Configure Project Settings**:
   - Minimum Deployment: iOS 17.0
   - Bundle Identifier: `com.yourname.Cadence`
   - Team: Select your Apple Developer account

4. **Build and Run**:
   - Select iPhone simulator or device
   - Press `Cmd+R`
   - App will launch with default "Work" and "Personal" sets

---

## 🎨 Usage Guide

### First Launch
The app creates two default activity sets:
- **Work**: Deep Work, Meetings, Email, Planning, Break
- **Personal**: Exercise, Reading, Family Time, Hobbies, Rest

### Starting Your Day
1. Open Cadence
2. Tap an activity to start tracking
3. Timer begins automatically

### Switching Activities
1. Simply tap another activity
2. Previous activity auto-ends
3. New activity auto-starts
4. No confirmation dialogs!

### Taking Breaks
1. Tap "Pause" to temporarily stop timer
2. Tap "Resume" when back
3. Pause duration is tracked separately

### Ending Your Day
1. Tap "Stop" to end current activity
2. View Timeline tab to see your day
3. Check Stats tab for insights

### Customizing Activities
1. Go to Settings tab
2. Tap "Add Activity" for current set
3. Choose name and color
4. Drag to reorder activities

### Switching Activity Sets
1. In Tracking view, use the segmented picker
2. Or go to Settings and tap a different set
3. Activities instantly change

---

## 🔧 Technical Implementation Details

### State Machine Logic
```swift
// When user taps activity
func startActivity(_ activity: Activity) {
    // 1. End current activity (if exists)
    if let current = currentTimeBlock {
        current.endTime = Date()
        current.isPaused = false
    }
    
    // 2. Create new time block
    let newBlock = TimeBlock(...)
    newBlock.startTime = Date()
    
    // 3. Save to database
    modelContext.insert(newBlock)
    modelContext.save()
}
```

### Duration Calculation
```swift
var duration: TimeInterval {
    let end = endTime ?? Date()
    let raw = end.timeIntervalSince(startTime)
    let pauseTime = totalPauseDuration
    let currentPause = isPaused ? Date().timeIntervalSince(pauseStartTime!) : 0
    return raw - pauseTime - currentPause
}
```

### Query Performance
- Uses `FetchDescriptor` with predicates
- Filters by date range efficiently
- Denormalized activity name/color for faster queries

---

## 🐛 Known Limitations (MVP)

### Current Constraints
- ❌ No retroactive editing (coming in v1.1)
- ❌ No weekly/monthly aggregation (MVP shows today only)
- ❌ No CSV export (coming in v1.2)
- ❌ No background time tracking (iOS limitation)
- ❌ No automatic set switching by time (coming in v1.3)
- ❌ No undo feature for accidental taps

### Design Decisions
- **No background tracking**: iOS suspends apps aggressively. Users must be in-app to track.
- **Manual switching only**: No automation means no privacy invasion, but requires discipline.
- **Today-only stats**: Keeps MVP simple, prevents analysis paralysis.

---

## 🚦 Future Roadmap

### v1.1 - Data Integrity (Next Priority)
- Retroactive editing of time blocks
- Gap detection ("You forgot to log 2 hours")
- Timeline editing UI

### v1.2 - Insights
- Weekly/monthly aggregation
- Category grouping (Email + Meetings = "Communication")
- CSV export for external analysis
- Pattern detection ("You do deep work best 9-11am")

### v1.3 - Advanced Features
- Automatic set switching by time blocks
- Recurring activities (daily standup)
- Dark mode support
- iPad optimization

### v2.0 - Intelligence
- Activity suggestions based on patterns
- Focus mode integration
- Widgets
- Apple Watch companion

---

## 🎯 Design Principles

### Speed First
- Every interaction <2 seconds
- No confirmation dialogs
- No loading spinners (SwiftData is fast)

### Honest Data
- Every minute has an activity
- Pause tracking shows real interruptions
- Switch counter reveals fragmentation

### No Shame
- No productivity scores
- No "you should" goals
- Just data, you decide what it means

### Manual Control
- You choose what to track
- You decide when to switch
- No invasive automation

---

## 🧪 Testing Recommendations

### Unit Tests (Add Later)
```swift
// Test state transitions
func testActivitySwitching()
func testPauseResumeLogic()
func testDurationCalculations()
```

### UI Tests (Add Later)
```swift
// Test user flows
func testStartStopActivity()
func testActivitySetSwitching()
func testTimelineDisplay()
```

### Manual Testing Checklist
- [ ] Start activity → timer runs
- [ ] Switch activity → previous ends, new starts
- [ ] Pause/Resume → duration calculation correct
- [ ] Stop → activity ends, no new activity starts
- [ ] App restart → resumes active activity
- [ ] Timeline shows correct order
- [ ] Stats calculate correctly
- [ ] Add/edit/delete activities works
- [ ] Set switching updates button grid

---

## 📚 Key SwiftUI/SwiftData Patterns Used

### @Query for Reactive Data
```swift
@Query private var activities: [Activity]
// Automatically updates view when data changes
```

### @Observable for State
```swift
@Observable class TimeTrackingManager
// Replace old @ObservedObject pattern
```

### Environment for Dependency Injection
```swift
@Environment(\.modelContext) private var modelContext
// Access SwiftData context anywhere
```

### Bindable for Two-Way Binding
```swift
@Bindable var activity: Activity
TextField("Name", text: $activity.name) // Direct binding
```

---

## 🤝 Contributing

This is an MVP. Contributions welcome for:
- Bug fixes
- Performance improvements
- UI polish
- Feature implementations from roadmap

### Code Style
- Use SwiftUI best practices
- Follow Swift API Design Guidelines
- Comment non-obvious logic
- Keep functions small (<30 lines)

---

## 📄 License

MIT License - Use freely, attribution appreciated

---

## 🙏 Credits

**Inspired by:**
- Time-motion studies in industrial engineering
- YNAB's "every dollar has a job" philosophy
- The brutal honesty of RescueTime
- The simplicity of Toggl

**Built with:**
- SwiftUI (Apple)
- SwiftData (Apple)
- Swift Charts (Apple)

---

## 📬 Feedback

Found a bug? Have a feature request? Want to share your time-tracking insights?

Submit issues on GitHub or reach out directly.

---

**Remember:** The goal isn't optimization—it's *visibility*. Once you see how you actually spend time, you can make informed choices about how to spend it better.

**Track honestly. Adjust intentionally. Live deliberately.**

---

*Cadence v1.0.0 MVP - January 2026*
