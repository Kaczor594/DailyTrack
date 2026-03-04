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
- iOS widget extension with task toggle intents
- Cloudflare Worker sync backend (push/pull with last-write-wins conflict resolution)
- App Group container for widget data sharing

**Just fixed (uncommitted):**
- Bug where synced entry values didn't display in text fields on mobile after pulling from server. The overall daily score percentage updated correctly, but individual `TaskRowView` text fields showed "0" because the `@State inputText` was only set in `.onAppear` and not re-synced when the underlying model changed. Fix: added `.onChange(of: progress.entry.value)` to `TaskRowView`.

## Environment Setup

**iOS/macOS App:**
- Xcode 15+ required (targets iOS 17 / macOS 14)
- Open `DailyTrack/DailyTrack.xcodeproj` and build (Cmd+R)
- No external Swift dependencies — uses SwiftData, Swift Charts, and SQLite3 C API
- App Group identifier configured in `AppGroupContainer.swift` for widget data sharing

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
├── DailyTrackWidget/                    # iOS widget extension
│   ├── DailyTrackWidget.swift
│   └── ToggleTaskIntent.swift
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
- **Widget** uses App Group shared container to read task data and App Intents to toggle checkbox tasks.

## Recent Changes

```
2283ca5 Fix sync issues, add app icon, and fix score calculation
7942119 Add node_modules to .gitignore
a9f508f Add iOS widget extension and Cloudflare sync
5a7a15b Add Xcode project, fix macOS build issues, and improve UI
fcaecca Restructure to standard Xcode project layout
d692820 Initial commit: DailyTrack SwiftUI app
```

**Uncommitted:** `DailyView.swift` — fix for synced entry values not displaying in task row text fields (see "Current State" above).

## Known Issues

- **Sync text field display bug** (fix uncommitted): After pulling synced data, `TaskRowView` text fields showed "0" because `@State inputText` only initialized in `.onAppear`. Fixed by adding `.onChange(of: progress.entry.value)`.
- The `reconcile` endpoint exists in the worker but is not called from the iOS app's sync flow (the method exists in `SyncManager` but is never invoked).
- README architecture section is slightly out of date (references `DatabaseManager.swift` which was replaced by SwiftData).

## Next Steps

- [ ] Commit and verify the sync text field fix on a real device
- [ ] Wire up the `reconcile` call in the sync flow to clean up stale server-side tasks
- [ ] Update README to reflect current SwiftData architecture and Cloudflare sync
- [ ] Add error UI for sync failures (currently only sets `lastError` string, not surfaced to user)
- [ ] Consider adding pull-to-refresh gesture on DailyView to trigger manual sync
