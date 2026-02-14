# Cadence: Intentional Time Tracking for iOS

**Cadence** is not just a stopwatch; it is an architectural approach to mindfulness. Built for power users who value **data sovereignty**, **context**, and **intentionality**, Cadence treats the "gaps" in your day as first-class citizens, forcing a conscious engagement with how time is actually spent.

!([https://img.shields.io/badge/Swift-6.0-orange?style=flat-square](https://www.google.com/search?q=https://img.shields.io/badge/Swift-6.0-orange%3Fstyle%3Dflat-square))

## 🌟 Core Philosophy

Most time trackers focus on *efficiency* (logging billable hours). Cadence focuses on *effectiveness* (logging life).

1. **The Gap Theory:** Time you don't track isn't "free"—it's unaccounted for. Cadence visualizes these gaps, encouraging you to either resolve them or accept them, eliminating "time leaks."
2. **First-Class Remarks:** A time entry without context is just a number. Cadence allows for "Interstitial Journalling"—attaching rich, taggable remarks to blocks to capture *why* you did something, not just *what* you did.
3. **Intentional Bookends:** The "Day Note" system enforces a morning Intention and an evening Reflection, framing your raw data within a narrative structure.

## 🏗 Technical Architecture

Cadence is built using **SwiftUI** and **SwiftData**, following a modern **Feature-Modular Architecture** designed for scalability and concurrency safety.

### Key Components

* **Data Layer (SwiftData):** Robust, localized persistence. Models (`Activity`, `TimeBlock`, `Remark`) are decoupled to support complex refactoring (splitting/merging blocks) without data loss.
* **Service Layer (`/Services`):** Stateless logic handlers.
* `GapCalculator`: Pure function algorithms to detect and quantify missing time.
* `ReportGenerator`: Actor-based reporting engine that offloads heavy statistical analysis to background threads to prevent UI hangs.


* **State Management (`/Managers`):**
* `TimeTrackingManager`: The "Brain" ensuring data integrity during live tracking, handling background transitions, and preventing "bulldozer" overwrites.


* **Data Sovereignty:**
* `CSVExporter`: Stream-based export for analyzing raw data in Excel/Python.
* `ArchiveService`: Full JSON backup/restore capabilities with versioning.



## 🚀 Features

* **Contextual Sets:** Auto-switching Activity Sets (e.g., "Work" to "Personal") based on time-of-day rules.
* **Fragmentation Index:** A calculated metric measuring your focus quality based on context-switching frequency.
* **Retroactive Correction:** Robust background handling that saves battery while ensuring timer accuracy even if the app is terminated.
* **Privacy First:** 100% Local. No analytics, no cloud collection. Your data is yours.

## 🛠 Installation & Requirements

**Requirements:**

* Xcode 16.0+
* iOS 17.0+

**Setup:**

1. Clone the repository.
2. Open `Cadence.xcodeproj`.
3. Ensure the Signing Team is set to your developer account.
4. Build and Run (Cmd+R).

## 📂 Project Structuretext

Cadence/
├── App/                # Entry point and configuration
├── Core/               # Data Models (SwiftData) & DTOs
├── Services/           # Stateless logic (Reporting, Export, Gaps)
├── Managers/           # Stateful singletons (Tracking, Settings)
├── Features/           # UI grouped by domain
│   ├── Tracking/       # Live timer views
│   ├── Journal/        # Timeline and Remarks
│   ├── Records/        # History and Editing
│   └── Reports/        # Charts and Analysis
└── Utilities/          # Extensions and Helpers

```

## 🔒 License & Usage

© 2026. All Rights Reserved.

This source code is provided for portfolio/evaluation purposes only. Redistribution, modification, or commercial use of this codebase is strictly prohibited without a valid license.

```

```
