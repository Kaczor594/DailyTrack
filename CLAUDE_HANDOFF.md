# Claude Code Handoff — DailyTrack

> Last updated: 2026-03-05
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
- Large widget: today's score ring + 5-day history bar chart (committed in 3e01ec6)
- macOS native widget support (sandbox entitlement fix committed in 3e01ec6)
- Cloudflare Worker sync backend (push/pull/reconcile with last-write-wins conflict resolution)
- App Group container for widget data sharing
- Reconcile step in sync flow cleans up stale server-side tasks (skipped on first sync)

**Uncommitted changes (1 file):**
- **Reconcile wired into sync flow** (`SyncManager.swift`): Added `reconcile()` call to the `sync()` method. Order is push → pull → reconcile. Reconcile is skipped on first sync (`lastSyncTimestamp == "1970-01-01T00:00:00Z"`) to prevent a fresh install from wiping server-side tasks the device hasn't pulled yet.

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
- D1 database: `dailytrack-sync` (ID: `9670dd0c-ab14-4bdc-aa8f-b674da782f63`)
- Sync API requires a Bearer token (configured in app Settings)

**D1 Time Travel (data recovery):**
```bash
cd cloudflare-worker
# Get bookmark for a specific time
npx wrangler d1 time-travel info dailytrack-sync --timestamp "2026-03-04T21:00:00Z" --json
# Restore to that bookmark
npx wrangler d1 time-travel restore dailytrack-sync --bookmark "<bookmark_id>"
# Query current server data
npx wrangler d1 execute dailytrack-sync --remote --command "SELECT id, name, deleted FROM tasks WHERE deleted = 0"
```

**Resetting sync on a device:**
```bash
defaults write com.kaczor.DailyTrack lastSyncTimestamp "1970-01-01T00:00:00Z"
```

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
│   │   └── SyncManager.swift            # Bidirectional sync (push/pull/reconcile) with Cloudflare D1
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
- **Sync flow**: `SyncManager` is injected as an `@Observable` environment object. On app launch, an initial sync runs. User edits trigger `debouncedSync` (2s delay). Sync order: push → pull → reconcile. Conflict resolution is last-write-wins based on `updatedAt` ISO8601 timestamps. Soft-delete pattern: `deleted` flag rather than actual deletion.
- **Reconcile**: After push and pull, the app sends its list of active task IDs to `POST /reconcile`. The server marks any task not in that list as deleted. **Skipped on first sync** (when `lastSyncTimestamp` is the epoch default) because a fresh device doesn't have the full task set yet — reconciling would incorrectly delete server-only tasks.
- **Cloudflare Worker** exposes `POST /sync` (upsert), `GET /sync?since=` (pull changes), and `POST /reconcile` (mark stale tasks as deleted). Auth via Bearer token.
- **Widget** uses App Group shared container to read task data via SwiftData (read-only ModelConfiguration). Timeline refreshes at midnight or every 30 minutes. Three sizes supported: small (score ring only), medium (score ring + 4 task rows), large (today's score ring + 5-day history bar chart). App Intents allow toggling checkbox tasks directly from the widget.

## Recent Changes

```
3e01ec6 Redesign large widget and fix macOS widget support
4d130ef Fix synced entry values not displaying in task row text fields and add handoff doc
2283ca5 Fix sync issues, add app icon, and fix score calculation
7942119 Add node_modules to .gitignore
a9f508f Add iOS widget extension and Cloudflare sync
5a7a15b Add Xcode project, fix macOS build issues, and improve UI
fcaecca Restructure to standard Xcode project layout
d692820 Initial commit: DailyTrack SwiftUI app
```

**Uncommitted:**
- `SyncManager.swift` — Wired `reconcile()` into the sync flow (push → pull → reconcile). Skips reconcile on first sync to prevent fresh installs from wiping server data.

**Server-side (this session):**
- Used D1 Time Travel to restore database after stale iPhone data corrupted the server. Restored to a 1.5-hour-old bookmark and manually soft-deleted the "WeWork vor 10 Uhr" task.

## Known Issues

- README architecture section is slightly out of date (references `DatabaseManager.swift` which was replaced by SwiftData).
- **macOS widget debugging**: The WidgetKit Simulator (`WidgetKit_Simulator.WidgetDocument.Error error 5`) does not work for debugging widgets on Mac. Use the main app scheme instead and add the widget via Notification Center.
- **CoreData recovery log on fresh install**: Fresh installs show `CoreData: error: During recovery, parent directory path reported as missing` followed by `Recovery attempt... was successful!` — this is harmless; CoreData auto-creates the missing App Group directory.

## Next Steps

- [ ] Commit the reconcile sync fix (`SyncManager.swift`)
- [ ] Update README to reflect current SwiftData architecture and Cloudflare sync
- [ ] Add error UI for sync failures (currently only sets `lastError` string, not surfaced to user)
- [ ] Consider adding pull-to-refresh gesture on DailyView to trigger manual sync
