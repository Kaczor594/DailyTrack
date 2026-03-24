# Claude Code Handoff — DailyTrack

> Last updated: 2026-03-24
> Repo: https://github.com/Kaczor594/DailyTrack.git
> Branch: main

## Project Summary

DailyTrack is a SwiftUI daily task tracker for iOS and macOS. Users define tasks with numeric benchmarks (e.g., "4 hours of study") or checkboxes, track daily progress, and view analytics (streaks, heatmaps, trend charts). Data is stored locally via SwiftData/SQLite and synced across devices through a Cloudflare Worker + D1 backend. The app is localized in English and German.

## Current State

**Working:**
- Core daily tracking (numeric input, checkboxes, cumulative tasks)
- **Cumulative period timelines** (weekly/monthly/yearly) — cumulative tasks can be scoped to a period window with derived daily targets contributing to the daily score
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
- **First-sync server-wins**: on first sync (epoch timestamp), server data unconditionally overwrites local seed data regardless of timestamps, preventing stale seed definitions from winning due to fresh `createdAt`/`updatedAt` values
- **Defensive `cumulativePeriod` handling**: field is `String?` — pull merge only overwrites when the server sends a value, preventing older Workers from resetting the local period to "none"
- **Keyboard dismiss button** on sync settings fields (iOS) — "Done" toolbar button above keyboard for API URL and Sync Token text fields

**Public repo:**
- Open-source copy at `../DailyTrack-public/`, pushed to https://github.com/Kaczor594/DailyTrackApp.git
- README with complete Cloudflare Worker deployment guide, Apple dev config, sync protocol docs

## Environment Setup

**iOS/macOS App:**
- Xcode 15+ required (targets iOS 17 / macOS 14)
- Open `DailyTrack/DailyTrack.xcodeproj` and build (Cmd+R)
- No external Swift dependencies — uses SwiftData, Swift Charts, and SQLite3 C API
- App Group identifier configured in `AppGroupContainer.swift` for widget data sharing
- Widget extension is embedded in the main app target via "Embed Foundation Extensions" build phase
- First deploy to a new iPhone will show "Copying shared cache symbols" dialog — this is normal and only happens once per iOS version

**Cloudflare Worker Backend:**
```bash
cd cloudflare-worker
npm install
npm run dev          # local dev server
npm run deploy       # deploy to Cloudflare
npm run db:migrate:remote  # apply schema to remote D1
```
- D1 database: `dailytrack-sync` (ID: `9670dd0c-ab14-4bdc-aa8f-b674da782f63`)
- Sync API requires a Bearer token (configured as Cloudflare secret, not in wrangler.toml)

**D1 Time Travel (data recovery):**
```bash
cd cloudflare-worker
npx wrangler d1 time-travel info dailytrack-sync --timestamp "2026-03-04T21:00:00Z" --json
npx wrangler d1 time-travel restore dailytrack-sync --bookmark "<bookmark_id>"
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
│   │   └── SeedData.swift               # First-launch seed data (deterministic IDs: seed-*)
│   ├── Shared/
│   │   └── AppGroupContainer.swift      # App Group container utilities
│   ├── Sync/
│   │   └── SyncManager.swift            # Bidirectional sync (push/pull/reconcile) with Cloudflare D1
│   └── Localization/
│       └── Localizable.xcstrings        # EN + DE string catalog
├── DailyTrackWidget/                    # iOS/macOS widget extension
│   ├── DailyTrackWidget.swift           # Widget views, timeline provider, score computation
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

- **SwiftData** models (`TaskDefinition`, `DailyEntry`) with `@Model` macro. Stored in App Group container for widget access. `cumulativePeriod` field is `String?` (optional) — SwiftData lightweight migration requires new columns to be nullable.
- **MVVM pattern**: `DailyViewModel`, `HistoryViewModel`, `SettingsViewModel` drive the three tab views.
- **Period window logic**: `periodWindow(for:on:)` helper (duplicated in DailyViewModel, HistoryViewModel, and widget provider) uses `Calendar.dateInterval(of:for:)` to get locale-aware period boundaries.
- **Sync flow**: `SyncManager` is injected as an `@Observable` environment object. On app launch, an initial sync runs. User edits trigger `debouncedSync` (2s delay). Sync order depends on context:
  - **First-ever sync** (epoch timestamp): pull-only. Server data always wins over local seed data regardless of timestamps.
  - **First sync of session** (`!hasCompletedInitialSync`): pull → push → reconcile.
  - **Subsequent syncs**: push → pull → reconcile.
- **Conflict resolution**: last-write-wins based on `updatedAt` ISO8601 timestamps, except on first sync where server unconditionally wins.
- **Defensive decoding**: `CodableTaskDefinition.cumulativePeriod` is `String?`. Decoder uses `try?` without a default. Pull merge only overwrites when server sends non-nil. Push path sends `?? "none"`.
- **Reconcile**: After push and pull, app sends active task IDs to `POST /reconcile`. Server marks unlisted tasks as deleted. Skipped on first sync.
- **Cloudflare Worker** exposes `POST /sync` (upsert), `GET /sync?since=` (pull changes), and `POST /reconcile`. Auth via Bearer token. Auto-migrations: `ensureSyncedAtColumn` and `ensureCumulativePeriodColumn`.
- **Widget** reads from App Group shared container (read-only ModelConfiguration). Timeline refreshes at midnight or every 30 minutes. Three sizes. App Intents allow toggling checkbox tasks.

## Recent Changes

**Session 2026-03-24 (this session):**
- Deployed Cloudflare Worker — `cumulative_period` column was missing from D1 because the Worker had never been redeployed after the feature was added. Ran migration manually (`ALTER TABLE tasks ADD COLUMN cumulative_period TEXT NOT NULL DEFAULT 'none'`) and deployed Worker.
- Fixed first-sync pull logic in `SyncManager.swift` — on first sync, server data now unconditionally overwrites local data (seed data has artificially fresh timestamps that were winning last-write-wins). Applied to both task and entry merge loops.
- Updated server data: set `cumulative_period = 'week'` for "Bewerben" task (was defaulting to "none" because column didn't exist).
- Added keyboard dismiss button to sync settings in `SettingsView.swift` — `@FocusState` + toolbar "Done" button above keyboard for API URL and Sync Token fields on iOS. Also added `.submitLabel(.done)` to both fields.

**Uncommitted changes (2 files, +24 lines):**
- `SyncManager.swift`: `isFirstSync` flag passed into merge logic; `serverWins = isFirstSync || remoteTask.updatedAt > local.updatedAt` replaces bare timestamp comparison
- `SettingsView.swift`: `@FocusState` property, `.focused()` modifiers on text fields, keyboard toolbar with Done button

## Known Issues

- **macOS widget debugging**: WidgetKit Simulator doesn't work for Mac debugging. Use main app scheme and add widget via Notification Center.
- **CoreData recovery log on fresh install**: Harmless `CoreData: error: During recovery, parent directory path reported as missing` followed by `Recovery attempt... was successful!`.
- **Seed data still has stale values**: `SeedData.swift` has `isCheckbox: true` for Putzen and no cumulative settings for Bewerben. These are wrong relative to the current server state. Not a bug anymore (first-sync server-wins fixes it), but the seed file is misleading. Consider updating it to match reality.
- **`periodWindow(for:on:)` duplicated** in DailyViewModel, HistoryViewModel, and widget provider. Should be extracted to a shared utility.
- Public repo README architecture section shows `Sources/` prefix in the tree but the actual Xcode project doesn't use that intermediate directory.

## Next Steps

- [ ] Test reinstall sync fix on phone: delete app → rebuild from Xcode → verify Putzen is x/1 and Bewerben has weekly cumulative
- [ ] Update `SeedData.swift` to match current task definitions (Putzen as x/1, Bewerben as weekly cumulative with benchmark 12)
- [ ] Extract `periodWindow(for:on:)` into a shared utility (currently duplicated in 3 places)
- [ ] Add error UI for sync failures (`lastError` is set but not surfaced to user beyond a red caption in Settings)
- [ ] Consider pull-to-refresh gesture on DailyView to trigger manual sync
- [ ] Update public repo with latest changes
