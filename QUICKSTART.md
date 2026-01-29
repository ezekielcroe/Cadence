# Cadence - Quick Start Guide

## 🚀 Get Running in 5 Minutes

### Step 1: Create Xcode Project
1. Open Xcode
2. File → New → Project
3. Choose "iOS App"
4. Settings:
   - **Product Name**: Cadence
   - **Interface**: SwiftUI
   - **Storage**: None (we handle SwiftData manually)
   - **Language**: Swift
   - **Include Tests**: Optional

### Step 2: Set Minimum iOS Version
1. Select project in navigator
2. Go to "General" tab
3. Set **Minimum Deployments** to **iOS 17.0**

### Step 3: Add Source Files
Copy all `.swift` files into your project in this structure:

```
Cadence/
├─ CadenceApp.swift              (Replace the default one)
├─ Models/
│  └─ Models.swift
├─ Managers/
│  └─ TimeTrackingManager.swift
└─ Views/
   ├─ ContentView.swift          (Replace the default one)
   ├─ TrackingView.swift
   ├─ TimelineView.swift
   ├─ StatsView.swift
   └─ SettingsView.swift
```

**To add files:**
- Right-click on project folder → New Group (name it "Models", "Managers", "Views")
- Right-click on group → New File → Swift File
- Paste the code from each file

### Step 4: Build & Run
1. Select iPhone simulator (any model)
2. Press `Cmd + R` or click ▶️ Play button
3. App will launch with default activities!

---

## 🎯 What You'll See

### On First Launch
- Two activity sets created: "Work" and "Personal"
- Work set is active by default
- 5 default activities per set with different colors

### Main Screen (Tracking)
- Top: "No Active Activity" card
- Middle: Activity set picker (Work/Personal)
- Bottom: Grid of activity buttons

### Try This Flow
1. Tap "Deep Work" → Timer starts
2. Wait 10 seconds
3. Tap "Email" → Deep Work ends, Email starts
4. Tap "Pause" → Timer pauses
5. Tap "Resume" → Timer continues
6. Tap "Stop" → Activity ends
7. Go to "Timeline" tab → See your activities!
8. Go to "Stats" tab → See charts!

---

## 🐛 Troubleshooting

### Build Errors?

**Error: "Cannot find type 'Activity' in scope"**
→ Make sure all files are added to the target (check box in File Inspector)

**Error: "Module 'SwiftData' not found"**
→ Update to iOS 17.0+ deployment target

**Error: "'@Query' is only available in iOS 17.0"**
→ Update to iOS 17.0+ deployment target

**Error: "'@Observable' is only available in iOS 17.0"**
→ Update to iOS 17.0+ deployment target

### Runtime Issues?

**App crashes on launch**
→ Check Console for SwiftData errors
→ Delete app from simulator and reinstall

**Activities not showing**
→ Check Settings tab → Make sure set is selected
→ Try adding a new activity manually

**Timer not updating**
→ This is normal in simulator when app is paused
→ Run on device for real-time updates

---

## 📱 Testing Checklist

After building, test these flows:

- [ ] Start activity → Timer runs
- [ ] Switch activity → Seamless transition
- [ ] Pause/Resume → Timer stops/starts
- [ ] Stop → Activity ends cleanly
- [ ] Timeline shows entries
- [ ] Stats display correctly
- [ ] Add new activity works
- [ ] Edit activity works
- [ ] Delete activity works
- [ ] Switch activity sets works
- [ ] App restart preserves data

---

## 🎨 Customization Tips

### Change Default Colors
Edit `CadenceApp.swift` → `setupDefaultData()`:
```swift
let defaultWorkActivities = [
    ("Deep Work", "#YOUR_HEX_COLOR"),
    // ...
]
```

### Add More Default Activities
Edit `CadenceApp.swift` → `setupDefaultData()`:
```swift
let defaultWorkActivities = [
    ("Deep Work", "#4CAF50"),
    ("Meetings", "#2196F3"),
    ("Your New Activity", "#FF00FF"), // Add here
]
```

### Change Tab Icons
Edit `ContentView.swift` → `TabView`:
```swift
.tabItem {
    Label("Track", systemImage: "your.sf.symbol")
}
```

---

## 🔧 Advanced Configuration

### Enable Dark Mode
Already supported! iOS handles it automatically.

### Change Accent Color
1. Assets.xcassets → AccentColor
2. Choose your brand color

### Add App Icon
1. Assets.xcassets → AppIcon
2. Drag 1024x1024 icon
3. Xcode generates all sizes

### Custom Launch Screen
Edit `Info.plist` → UILaunchScreen

---

## 📚 Next Steps

### Learn the Codebase
1. Start with `Models.swift` → Understand data structure
2. Read `TimeTrackingManager.swift` → Core state machine
3. Explore `TrackingView.swift` → UI implementation

### Add Features
Pick from the roadmap in README.md:
- Retroactive editing
- Weekly stats
- CSV export
- Dark mode customization

### Deploy to TestFlight
1. Enroll in Apple Developer Program ($99/year)
2. Archive app in Xcode
3. Upload to App Store Connect
4. Create TestFlight build
5. Share with testers

---

## 🆘 Need Help?

### Documentation
- [SwiftUI Docs](https://developer.apple.com/documentation/swiftui/)
- [SwiftData Docs](https://developer.apple.com/documentation/swiftdata/)
- [Swift Charts Docs](https://developer.apple.com/documentation/charts/)

### Common Questions

**Q: Can I use iOS 16?**
A: No, SwiftData requires iOS 17+

**Q: Can I use UIKit instead of SwiftUI?**
A: Yes, but you'll need to rewrite all views

**Q: Does this work on iPad?**
A: Yes! Same code works on iPad automatically

**Q: Can I use Core Data instead of SwiftData?**
A: Yes, but SwiftData is much simpler for new projects

**Q: How do I export my data?**
A: CSV export is coming in v1.2 (see roadmap)

---

## 🎉 You're Ready!

You now have a fully functional time-tracking app. Start using it to track your own activities and see patterns emerge.

**Next:** Customize activities for your actual workflow, then use it daily for a week to see real insights.

Happy tracking! ⏱️
