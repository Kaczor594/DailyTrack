# Claude Code Handoff — DailyTrack

> Last updated: 2026-03-17
> Repo: https://github.com/Kaczor594/DailyTrack.git
> Branch: main

## Project Summary

DailyTrack is a SwiftUI daily task tracker for iOS and macOS. Users define tasks with numeric benchmarks (e.g., "4 hours of study") or checkboxes, track daily progress, and view analytics (streaks, heatmaps, trend charts). Data is stored locally via SwiftData/SQLite and synced across devices through a Cloudflare Worker + D1 backend. The app is localized in English and German.

## Current State

**Working:**
- Core daily tracking (numeric input, checkboxes, cumulative tasks)
- **Cumulative period timelines** (weekly/monthly/yearly) — cumulative tasks can now be scoped to a period window with derived daily targets contributing to the daily score
- Weighted daily score calculation with progress ring
- History view with calendar heatmap, streak tracking, and trend charts
- Task configuration via in-app settings and JSON import/export
- iOS/macOS widget extension with task toggle intents (small, medium, large sizes)
- Large widget: today's score ring + 5-day history bar chart
- macOS native widget support
- Cloudflare Worker sync backend (push/pull/reconcile with last-write-wins conflict resolution)
- App Group container for widget data sharing
- Reconcile step in sync flow cleans up stale server-side tasks (skipped on first sync)
- **Reinstall-safe sync**: three-branch sync logic prevents zero-value entries from overwriting server data after a fresh install or provisioning expiry
- **Defensive `cumulativePeriod` handling**: field is `String?` — pull merge only overwrites when the server sends a value, preventing older Workers from resetting the local period to "none"

**Public repo created and pushed:**
- Open-source copy lives at `../DailyTrack-public/` with fresh git history, placeholder credentials, and generic seed data.
- Pushed to GitHub at https://github.com/Kaczor594/DailyTrackApp.git
- README expanded with complete Cloudflare Worker deployment guide, Apple development configuration steps, sync protocol docs, troubleshooting section, and security notes.
- No secrets or personal credentials in public repo. Personal identifiers (`com.kaczor594`) remain in bundle IDs/entitlements as users must replace them anyway (documented in README).

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
│   │   ├── TaskDefinition.swift         # @Model: task schema (name, benchmark, unit, weight, cumulativePeriod, etc.)
│   │   ├── DailyEntry.swift             # @Model: daily progress entry (value, date, notes)
│   │   └── TaskProgress.swift           # View struct combining task + entry for UI (scoringRatio, periodProgressText)
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

- **SwiftData** models (`TaskDefinition`, `DailyEntry`) with `@Model` macro. Stored in App Group container for widget access. `cumulativePeriod` field added as `String?` (optional) — SwiftData lightweight migration requires new columns to be nullable; a non-optional `String` with a Swift-level default causes a runtime crash (`"Validation error missing attribute values on mandatory destination attribute"`).
- **MVVM pattern**: `DailyViewModel`, `HistoryViewModel`, `SettingsViewModel` drive the three tab views.
- **Period window logic**: `periodWindow(for:on:)` helper (duplicated in DailyViewModel, HistoryViewModel, and widget provider) uses `Calendar.dateInterval(of:for:)` to get locale-aware period boundaries. Returns `(startDateStr, endDateStr, periodDays)`. Score calculation uses `entry.value / (benchmark / periodDays)` as the ratio for period-cumulative tasks.
- **Sync flow**: `SyncManager` is injected as an `@Observable` environment object. On app launch, an initial sync runs. User edits trigger `debouncedSync` (2s delay). Sync order depends on context: **first-ever sync** (epoch timestamp) is pull-only; **first sync of session** (`!hasCompletedInitialSync`) does pull → push → reconcile; **subsequent syncs** do push → pull → reconcile. Conflict resolution is last-write-wins based on `updatedAt` ISO8601 timestamps. Soft-delete pattern: `deleted` flag rather than actual deletion. `hasCompletedInitialSync` (session-scoped) flag gates UI entry creation to prevent zero-value entries from overwriting server data before the first pull completes.
- **Defensive decoding**: `CodableTaskDefinition.cumulativePeriod` is `String?`. The decoder uses `try?` without a default, so missing/null server fields decode to `nil`. The pull merge only overwrites the local `cumulativePeriod` when the server sent a non-nil value. The push path sends `?? "none"` so the server always gets a concrete value.
- **Reconcile**: After push and pull, the app sends its list of active task IDs to `POST /reconcile`. The server marks any task not in that list as deleted. **Skipped on first sync** (when `lastSyncTimestamp` is the epoch default) because a fresh device doesn't have the full task set yet — reconciling would incorrectly delete server-only tasks.
- **Cloudflare Worker** exposes `POST /sync` (upsert), `GET /sync?since=` (pull changes), and `POST /reconcile` (mark stale tasks as deleted). Auth via Bearer token.
- **Widget** uses App Group shared container to read task data via SwiftData (read-only ModelConfiguration). Timeline refreshes at midnight or every 30 minutes. Three sizes supported: small (score ring only), medium (score ring + 4 task rows), large (today's score ring + 5-day history bar chart). App Intents allow toggling checkbox tasks directly from the widget.

## Recent Changes

```
f783251 Add cumulative period timelines (weekly/monthly/yearly) for cumulative tasks
17113c1 Update handoff doc with public repo setup session notes
1c55a9d Update handoff doc with String? migration fix and public copy status
70e5fe6 Update handoff doc with cumulative period timelines feature
2af25cc Update handoff doc with reconcile sync fix and D1 recovery notes
3e01ec6 Redesign large widget and fix macOS widget support
4d130ef Fix synced entry values not displaying in task row text fields and add handoff doc
2283ca5 Fix sync issues, add app icon, and fix score calculation
7942119 Add node_modules to .gitignore
a9f508f Add iOS widget extension and Cloudflare sync
5a7a15b Add Xcode project, fix macOS build issues, and improve UI
fcaecca Restructure to standard Xcode project layout
d692820 Initial commit: DailyTrack SwiftUI app
```

**Session 2026-03-17 (continued):**
- Fixed `cumulativePeriod` being reset to "none" on every pull cycle
  - Root cause: `CodableTaskDefinition` decoded `cumulativePeriod` with `?? "none"` default, so servers that don't return the field would produce "none" and overwrite the local "week"/"month"/"year" value during pull merge.
  - Fix: Made `cumulativePeriod` a `String?` in both `TaskDefinition` and `CodableTaskDefinition`. Decoder uses `try?` without a default. Pull merge only overwrites when the server sends a non-nil value. Push path uses `?? "none"` to always send a concrete value to the server.
  - Files changed: `TaskDefinition.swift`, `SyncManager.swift`

**Session 2026-03-17:**
- Fixed sync bug where reinstalling the app (e.g. after 7-day free provisioning expiry) would overwrite server data with zero-value entries
- Root cause: `DailyViewModel.loadData()` eagerly creates `DailyEntry(value: 0)` for every task on `onAppear` — these get fresh `updatedAt` timestamps. The sync then pushes them before pulling, and they win last-write-wins against the real data on the server.
- Fix has two parts:
  1. **Entry creation gating**: `SyncManager.hasCompletedInitialSync` (session-scoped, starts `false` when sync is enabled) prevents `DailyViewModel.loadData()` from creating new entries until the first sync of the session completes. `DailyView` observes this flag and reloads with entry creation enabled after sync.
  2. **Sync order**: Three-branch sync logic — true first sync (epoch timestamp) is pull-only; first sync of session (`!hasCompletedInitialSync`) does pull → push → reconcile; subsequent syncs do push → pull → reconcile.
- Files changed: `SyncManager.swift`, `DailyViewModel.swift`, `DailyView.swift`

**Session 2026-03-10:**
- Committed the cumulative period timelines feature (12 files, `f783251`) — previously sitting uncommitted since 2026-03-06
- No code changes needed; working tree is clean

**Session 2026-03-06:**
- Created public repo at https://github.com/Kaczor594/DailyTrackApp.git and pushed
- Expanded public README with complete setup/deployment guide
- Audited public repo for personal information — no secrets or credentials exposed

## Known Issues

- **macOS widget debugging**: The WidgetKit Simulator (`WidgetKit_Simulator.WidgetDocument.Error error 5`) does not work for debugging widgets on Mac. Use the main app scheme instead and add the widget via Notification Center.
- **CoreData recovery log on fresh install**: Fresh installs show `CoreData: error: During recovery, parent directory path reported as missing` followed by `Recovery attempt... was successful!` — this is harmless; CoreData auto-creates the missing App Group directory.
- Public repo README architecture section shows `Sources/` prefix in the tree but the actual Xcode project doesn't use that intermediate directory.

## Next Steps

- [x] Commit the cumulative period timelines feature (12 modified files) in the private repo
- [x] Fix reinstall sync bug (push-before-pull + eager entry creation)
- [x] Fix `cumulativePeriod` reset bug (defensive optional decoding + conditional pull merge)
- [ ] Test reinstall sync fix: let app expire on phone → rebuild from Xcode → verify it pulls server data without overwriting today's entries
- [ ] Deploy updated Cloudflare Worker (`cd cloudflare-worker && npx wrangler deploy`) to apply `ensureCumulativePeriodColumn` migration
- [ ] Test: edit a task → toggle Cumulative → select "Weekly" → set benchmark to 10 → verify badge shows ~70% for 1 entry, cumulative badge shows "1/10 this week"
- [ ] Test: navigate to a different week → verify cumulative total resets to that week's entries
- [ ] Extract `periodWindow(for:on:)` into a shared utility (currently duplicated in DailyViewModel, HistoryViewModel, and widget provider)
- [ ] Add error UI for sync failures (currently only sets `lastError` string, not surfaced to user)
- [ ] Consider adding pull-to-refresh gesture on DailyView to trigger manual sync
