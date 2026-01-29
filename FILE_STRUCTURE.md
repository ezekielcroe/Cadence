# Cadence iOS App - File Structure

## 📁 Complete File Organization

```
CadenceApp/
│
├─ CadenceApp.swift                    (Main app entry point with SwiftData setup)
│
├─ Models/
│  └─ Models.swift                     (Data models: Activity, ActivitySet, TimeBlock)
│
├─ Managers/
│  └─ TimeTrackingManager.swift        (Core state management and business logic)
│
├─ Views/
│  ├─ ContentView.swift                (Main tab view container)
│  ├─ TrackingView.swift               (Activity tracking interface)
│  ├─ TimelineView.swift               (Today's activity timeline)
│  ├─ StatsView.swift                  (Charts and statistics)
│  └─ SettingsView.swift               (Activity and set management)
│
├─ Info.plist                          (App configuration)
├─ README.md                           (Comprehensive documentation)
└─ QUICKSTART.md                       (5-minute setup guide)
```

---

## 📄 File Descriptions

### CadenceApp.swift (Main Entry Point)
**Purpose**: App initialization and SwiftData configuration  
**Key Components**:
- `@main` app struct
- ModelContainer setup for SwiftData
- Default data initialization (Work/Personal sets)
- Creates default activities on first launch

**Dependencies**: SwiftUI, SwiftData, Models

---

### Models/Models.swift (Data Layer)
**Purpose**: Define all data models and relationships  

**Models**:
1. **Activity**: Individual trackable activities
   - Properties: id, name, color, setID, sortOrder
   - Belongs to an ActivitySet

2. **ActivitySet**: Groups of activities (Work, Personal, etc.)
   - Properties: id, name, isActive
   - Has many Activities

3. **TimeBlock**: A single period of activity
   - Properties: startTime, endTime, isPaused, pauseDuration, switchCount
   - Tracks one activity session with pause tracking

**Extensions**:
- `TimeInterval.formattedDuration`: Format seconds as "2h 15m"
- `TimeInterval.detailedFormattedDuration`: Format as "2h 15m 30s"

**Dependencies**: Foundation, SwiftData

---

### Managers/TimeTrackingManager.swift (Business Logic)
**Purpose**: Core state machine for time tracking  

**Responsibilities**:
- Start/stop activities
- Pause/resume current activity
- Calculate durations
- Query today's time blocks
- Aggregate statistics
- Session recovery after app restart

**Key Methods**:
- `startActivity(_:)`: Switch to new activity
- `pauseCurrentActivity()`: Pause without ending
- `resumeCurrentActivity()`: Resume from pause
- `stopCurrentActivity()`: End without starting new
- `getTodaysTimeBlocks()`: Fetch all blocks for today
- `getTodaysStats()`: Aggregate statistics

**State**:
- `currentTimeBlock`: Currently active time block (if any)
- `activeSet`: Currently selected activity set
- Timer for UI updates (1 second interval)

**Dependencies**: Foundation, SwiftData, Combine

---

### Views/ContentView.swift (Navigation)
**Purpose**: Main tab navigation container  

**Tabs**:
1. Track (timer icon) → TrackingView
2. Timeline (list icon) → TimelineView
3. Stats (chart icon) → StatsView
4. Settings (gear icon) → SettingsView

**Initialization**:
- Creates TimeTrackingManager
- Injects modelContext
- Manages tab selection state

**Dependencies**: SwiftUI, SwiftData, All other views

---

### Views/TrackingView.swift (Main Interface)
**Purpose**: Primary tracking interface where users start/stop activities  

**Components**:
1. **CurrentActivityCard**: Shows active activity and timer
   - Real-time duration display (updates every second)
   - Pause/Resume/Stop buttons
   - Status indicators (active/paused)

2. **ActivitySetPicker**: Switch between activity sets
   - Segmented control showing all sets
   - Updates active set in database

3. **ActivityButton Grid**: 2-column grid of activities
   - Color-coded circles
   - Shows which is currently active
   - Single tap to switch

**State Management**:
- `@Query` for activities and sets (reactive)
- `@Bindable` for manager updates
- Local timer for current time updates

**User Interactions**:
- Tap activity → starts tracking
- Tap pause → pauses current
- Tap resume → resumes from pause
- Tap stop → ends activity

**Dependencies**: SwiftUI, SwiftData, TimeTrackingManager

---

### Views/TimelineView.swift (History)
**Purpose**: Show chronological list of today's activities  

**Components**:
1. **TimeBlockRow**: Individual timeline entry
   - Start/end times
   - Duration display
   - Visual timeline connector
   - Pause duration (if any)
   - Switch count (fragmentation indicator)
   - Active/paused status for current

**Features**:
- Auto-refresh every 5 seconds
- Manual refresh button
- Shows "now" for active activity
- Empty state when no activities tracked

**Data Display**:
- Chronological order (oldest first)
- Visual connection lines between blocks
- Color-coded activity indicators
- Duration in compact format

**Dependencies**: SwiftUI, SwiftData, TimeTrackingManager

---

### Views/StatsView.swift (Analytics)
**Purpose**: Display charts and statistics for today  

**Components**:
1. **StatCard**: Summary metric cards
   - Total time tracked
   - Number of activities
   - Total switches (fragmentation)
   - Average duration per activity

2. **Activity Breakdown Chart**: Horizontal bar chart
   - Shows duration per activity
   - Sorted by duration (longest first)
   - Color-coded by activity
   - Duration labels on bars

3. **Timeline Chart**: Horizontal day visualization
   - Full day (midnight to midnight)
   - Color blocks for each activity
   - Proportional to actual duration
   - Visual day overview

4. **Activity Detail List**: Detailed breakdown
   - Activity name and color
   - Duration in detailed format
   - Percentage of total time
   - Sorted by duration

**Features**:
- Auto-refresh every 10 seconds
- Manual refresh button
- Empty state when no data
- Responsive layout

**Dependencies**: SwiftUI, Charts, TimeTrackingManager

---

### Views/SettingsView.swift (Configuration)
**Purpose**: Manage activities, sets, and app settings  

**Sections**:
1. **Activity Sets**:
   - List all sets
   - Shows which is active
   - Count of activities per set
   - Add new set
   - Delete sets (with safeguards)
   - Tap to activate set

2. **Activities** (for active set):
   - List all activities in current set
   - Tap to edit
   - Swipe to delete
   - Drag to reorder
   - Add new activity

3. **About**:
   - App version

**Sub-Views**:
- **AddActivitySetView**: Sheet for creating new set
- **AddActivityView**: Sheet for creating new activity
- **ActivityEditView**: Edit existing activity

**Features**:
- Color picker (20 preset colors)
- Activity reordering via drag
- Set switching
- Data validation

**Dependencies**: SwiftUI, SwiftData

---

## 🔗 Data Flow

### Starting an Activity
```
User taps activity button in TrackingView
  ↓
TrackingView calls manager.startActivity(activity)
  ↓
TimeTrackingManager creates new TimeBlock
  ↓
TimeBlock inserted into SwiftData
  ↓
@Query automatically updates all views
  ↓
TrackingView shows new active activity
TimelineView adds new entry
StatsView updates charts
```

### Data Persistence
```
User action (start/pause/stop)
  ↓
Manager updates TimeBlock properties
  ↓
modelContext.save() called immediately
  ↓
Data written to SQLite via SwiftData
  ↓
Survives app restart
```

### UI Updates
```
Timer fires every 1 second
  ↓
manager.objectWillChange.send()
  ↓
SwiftUI re-renders dependent views
  ↓
Duration displays update
```

---

## 🎨 UI Component Hierarchy

```
ContentView (TabView)
│
├─ TrackingView
│  ├─ CurrentActivityCard
│  │  ├─ Activity name & color
│  │  ├─ Timer display (real-time)
│  │  ├─ Pause/Resume button
│  │  ├─ Stop button
│  │  └─ Status indicator
│  ├─ ActivitySetPicker (if multiple sets)
│  └─ LazyVGrid
│     └─ ActivityButton (for each activity)
│
├─ TimelineView
│  └─ ScrollView
│     └─ TimeBlockRow (for each block)
│        ├─ Time stamps
│        ├─ Visual connector
│        ├─ Activity name & color
│        ├─ Duration
│        ├─ Pause info (if paused)
│        └─ Switch count (if any)
│
├─ StatsView
│  └─ ScrollView
│     ├─ StatCard × 4 (metrics)
│     ├─ Chart (Activity Breakdown)
│     ├─ TimelineChart (day visualization)
│     └─ ActivityDetailRow (for each activity)
│
└─ SettingsView
   └─ List
      ├─ Section: Activity Sets
      │  ├─ Set rows (tap to activate)
      │  └─ Add button
      ├─ Section: Activities
      │  ├─ Activity rows (tap to edit)
      │  └─ Add button
      └─ Section: About
```

---

## 🔄 Key SwiftUI Patterns Used

### @Query for Reactive Data
```swift
@Query private var activities: [Activity]
```
- Automatically fetches from SwiftData
- Re-runs when data changes
- No manual refresh needed

### @Observable for State
```swift
@Observable class TimeTrackingManager
```
- Replaces old @ObservedObject
- Cleaner syntax
- Better performance

### @Environment for Injection
```swift
@Environment(\.modelContext) private var modelContext
```
- Dependency injection
- Access SwiftData anywhere
- No manual passing

### @Bindable for Two-Way Binding
```swift
@Bindable var activity: Activity
TextField("Name", text: $activity.name)
```
- Direct property binding
- Automatic save to SwiftData
- No manual onChange handlers

---

## 🧪 Testing Entry Points

### Unit Test Targets
- `TimeTrackingManager`: State transitions
- `Models`: Duration calculations
- Helper extensions: Formatting

### UI Test Targets
- `TrackingView`: Activity switching flow
- `TimelineView`: Data display
- `StatsView`: Chart rendering
- `SettingsView`: CRUD operations

---

## 📦 Dependencies

### System Frameworks
- **SwiftUI**: UI framework
- **SwiftData**: Data persistence
- **Charts**: Data visualization
- **Foundation**: Core utilities
- **Combine**: Reactive programming (minimal use)

### No Third-Party Libraries
- Everything uses Apple frameworks
- No package dependencies
- No CocoaPods or SPM packages
- Easier maintenance

---

## 🚀 Build Configuration

### Minimum Requirements
- iOS 17.0+ (for SwiftData & @Observable)
- Xcode 15.0+
- Swift 5.9+

### Build Settings
- Interface: SwiftUI
- Lifecycle: SwiftUI App
- Storage: None (manual SwiftData)
- Language: Swift

### Info.plist Key Settings
- UIApplicationSceneManifest: Multiple scenes supported
- UILaunchScreen: Custom launch screen
- UISupportedInterfaceOrientations: Portrait + Landscape

---

## 🎯 Design Decisions Explained

### Why SwiftData over Core Data?
- Simpler API (no NSManagedObject)
- Better SwiftUI integration
- Automatic schema migration
- Modern Swift features (@Model)

### Why @Observable over ObservableObject?
- Less boilerplate
- Better performance
- Cleaner syntax
- iOS 17+ standard

### Why Manual Tracking?
- User control over data
- No privacy concerns
- No background battery drain
- Teaches mindfulness

### Why No Background Tracking?
- iOS limitations (app suspension)
- Battery concerns
- Requires Background Modes (complex)
- Manual is more honest

### Why Today-Only Stats in MVP?
- Simpler implementation
- Faster queries
- Less overwhelm
- Weekly/monthly coming in v1.2

---

## 🔒 Data Privacy

### What Data is Stored
- Activity names (user-defined)
- Activity colors
- Time blocks with timestamps
- Pause durations
- Switch counts

### What Data is NOT Stored
- No location data
- No app usage tracking
- No screen time monitoring
- No network requests
- No analytics

### Where Data Lives
- Local SQLite database (SwiftData)
- Stored in app sandbox
- Not synced to cloud (MVP)
- Deleted if app is deleted

---

## 🛠️ Extending the App

### Adding a New View
1. Create new file in Views/
2. Import SwiftUI, SwiftData
3. Add to ContentView TabView
4. Access manager via injection

### Adding a New Model
1. Add to Models/Models.swift
2. Mark with @Model
3. Add to Schema in CadenceApp.swift
4. Query with @Query in views

### Adding a New Feature
1. Check if state needed in manager
2. Add method to TimeTrackingManager
3. Update relevant views
4. Test data persistence

---

This file structure provides a solid foundation for the Cadence MVP while remaining extensible for future features.
