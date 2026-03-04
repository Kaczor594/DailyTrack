# Claude Code Handoff — DailyTrack

> Last updated: 2026-03-04
> Repo: https://github.com/Kaczor594/DailyTrack.git
> Branch: main

## Project Summary

DailyTrack is a SwiftUI daily task tracker for iOS and macOS. Users define tasks with numeric benchmarks (e.g., "4 hours of study") or checkboxes, track daily progress, and view analytics (streaks, heatmaps, trend charts). Data is stored locally via SwiftData/SQLite and synced across devices through a Cloudflare Worker + D1 backend. The app is localized in English and German.

## Current State

**Working:**
- Core daily tracking (numeric input, checkboxes, cumulative tasks)
- Weighted daily score calculation with progress ring
- History view with calendar heatmap, streak tracking, and trend charts
- Task configuration via in-app settings and JSON import/export
- iOS/macOS widget extension with task toggle intents (small, medium, large sizes)
- Cloudflare Worker sync backend (push/pull with last-write-wins conflict resolution)
- App Group container for widget data sharing
- Sync text field display bug fixed and committed (4d130ef)

**Uncommitted changes (2 files):**
- **Large widget redesign** (`DailyTrackWidget.swift`): Replaced the task list layout (which overflowed on phones with many tasks) with a focused progress view — large score ring for today's progress on top, 5-day history bar chart on the bottom. Added `RecentDayScore` model, `computeRecentScores()` in timeline provider, and `DayScoreBar` view. Small and medium widgets unchanged.
- **macOS widget sandbox fix** (`DailyTrackWidgetExtension.entitlements`): Added `com.apple.security.app-sandbox` entitlement, which is required for widget extensions to load on macOS. Without this, the widget only appeared via iPhone mirroring ("Von iPhone") and never as a native Mac widget.

## Environment Setup

**iOS/macOS App:**
- Xcode 15+ required (targets iOS 17 / macOS 14)
- Open `DailyTrack/DailyTrack.xcodeproj` and build (Cmd+R)
- No external Swift dependencies — uses SwiftData, Swift Charts, and SQLite3 C API
- App Group identifier configured in `AppGroupContainer.swift` for widget data sharing
- Widget extension is embedded in the main app target via "Embed Foundation Extensions" build phase
- Both the main app and widget target support iOS, macOS, and visionOS (see `SUPPORTED_PLATFORMS` in build settings)

**Cloudflare Worker Backend:**
```bash
cd cloudflare-worker
npm install
npm run dev          # local dev server
npm run deploy       # deploy to Cloudflare
npm run db:migrate:remote  # apply schema to remote D1
```
- Requires Cloudflare account + Wrangler CLI authenticated
- D1 database binding configured in `wrangler.toml`
- Sync API requires a Bearer token (configured in app Settings)

## File Structure

```
DailyTrack/
├── DailyTrack/DailyTrack/
│   ├── DailyTrackApp.swift              # Entry point, ModelContainer setup, initial sync
│   ├── Models/
│   │   ├── TaskDefinition.swift         # @Model: task schema (name, benchmark, unit, weight, etc.)
│   │   ├── DailyEntry.swift             # @Model: daily progress entry (value, date, notes)
│   │   └── TaskProgress.swift           # View struct combining task + entry for UI
│   ├── ViewModels/
│   │   ├── DailyViewModel.swift         # Daily view logic, score calculation, streak computation
│   │   ├── HistoryViewModel.swift       # Analytics: heatmap data, trends, streaks
│   │   └── SettingsViewModel.swift      # Task CRUD, JSON import/export
│   ├── Views/
│   │   ├── DailyView.swift              # Primary view: task rows, score ring, date navigation
│   │   ├── HistoryView.swift            # Charts, calendar heatmap, streak display
│   │   └── SettingsView.swift           # Task editor, sync config, JSON import/export
│   ├── Database/
│   │   └── SeedData.swift               # First-launch seed data
│   ├── Shared/
│   │   └── AppGroupContainer.swift      # App Group container utilities
│   ├── Sync/
│   │   └── SyncManager.swift            # Bidirectional sync (push/pull) with Cloudflare D1
│   └── Localization/
│       └── Localizable.xcstrings        # EN + DE string catalog
├── DailyTrack/DailyTrack.entitlements   # Main app entitlements (sandbox, network, app groups)
├── DailyTrackWidgetExtension.entitlements # Widget entitlements (sandbox, app groups)
├── DailyTrackWidget/                    # iOS/macOS widget extension
│   ├── DailyTrackWidget.swift           # Widget views, timeline provider, score computation
│   ├── DailyTrackWidget.entitlements    # Widget UI entitlements
│   ├── ToggleTaskIntent.swift           # AppIntent for toggling checkbox tasks from widget
│   └── Info.plist
├── cloudflare-worker/
│   ├── src/index.ts                     # Worker: /sync POST (push), /sync GET (pull), /reconcile
│   ├── schema.sql                       # D1 schema: tasks + daily_entries tables
│   ├── wrangler.toml                    # Worker config + D1 binding
│   └── package.json
└── README.md
```

## Architecture

- **SwiftData** models (`TaskDefinition`, `DailyEntry`) with `@Model` macro. Stored in App Group container for widget access.
- **MVVM pattern**: `DailyViewModel`, `HistoryViewModel`, `SettingsViewModel` drive the three tab views.
- **Sync flow**: `SyncManager` is injected as an `@Observable` environment object. On app launch, an initial sync runs. User edits trigger `debouncedSync` (2s delay). Sync pushes entries/tasks modified since `lastSyncTimestamp`, then pulls remote changes. Conflict resolution is last-write-wins based on `updatedAt` ISO8601 timestamps. Soft-delete pattern: `deleted` flag rather than actual deletion.
- **Cloudflare Worker** exposes `POST /sync` (upsert), `GET /sync?since=` (pull changes), and `POST /reconcile` (mark stale tasks as deleted). Auth via Bearer token.
- **Widget** uses App Group shared container to read task data via SwiftData (read-only ModelConfiguration). Timeline refreshes at midnight or every 30 minutes. Three sizes supported: small (score ring only), medium (score ring + 4 task rows), large (today's score ring + 5-day history bar chart). App Intents allow toggling checkbox tasks directly from the widget.

## Recent Changes

```
4d130ef Fix synced entry values not displaying in task row text fields and add handoff doc
2283ca5 Fix sync issues, add app icon, and fix score calculation
7942119 Add node_modules to .gitignore
a9f508f Add iOS widget extension and Cloudflare sync
5a7a15b Add Xcode project, fix macOS build issues, and improve UI
fcaecca Restructure to standard Xcode project layout
d692820 Initial commit: DailyTrack SwiftUI app
```

**Uncommitted:**
- `DailyTrackWidget.swift` — Large widget redesigned from task list to today's progress ring + 5-day history bar chart. Added `RecentDayScore` model, `computeRecentScores()` method, `DayScoreBar` view.
- `DailyTrackWidgetExtension.entitlements` — Added `com.apple.security.app-sandbox` for native macOS widget support.

## Known Issues

- The `reconcile` endpoint exists in the worker but is not called from the iOS app's sync flow (the method exists in `SyncManager` but is never invoked).
- README architecture section is slightly out of date (references `DatabaseManager.swift` which was replaced by SwiftData).
- **macOS widget debugging**: The WidgetKit Simulator (`WidgetKit_Simulator.WidgetDocument.Error error 5`) does not work for debugging widgets on Mac. Use the main app scheme instead and add the widget via Notification Center.
- **macOS widget not yet verified**: The sandbox entitlement fix has been applied but the native Mac widget has not yet been confirmed working — needs a rebuild and test on Mac.

## Next Steps

- [ ] Build, test, and verify the large widget redesign on iPhone and Mac
- [ ] Commit the widget redesign and sandbox fix
- [ ] Wire up the `reconcile` call in the sync flow to clean up stale server-side tasks
- [ ] Update README to reflect current SwiftData architecture and Cloudflare sync
- [ ] Add error UI for sync failures (currently only sets `lastError` string, not surfaced to user)
- [ ] Consider adding pull-to-refresh gesture on DailyView to trigger manual sync
