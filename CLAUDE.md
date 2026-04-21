# DailyTrack — Project Instructions

## Git Workflow
- Single git repo, main branch is `main`, tracks `origin` (github.com/Kaczor594/DailyTrack.git).
- Never use `git add -A` or `git add .`. Stage files explicitly.
- Never stage: `.DS_Store`, `.xcuserstate`, Xcode user data under `xcuserdata/`, build outputs, `.env` / credential files.
- Public mirror lives in a sibling directory `../DailyTrack-public/` pointed at a different remote. It is a separate working copy, not a submodule. Never push this repo's commits to the public remote or vice versa.

## Tooling
- **iOS/macOS app**: Xcode 15+ (targets iOS 17 / macOS 14). Open `DailyTrack/DailyTrack.xcodeproj` and Cmd+R. No external Swift dependencies. Project uses `PBXFileSystemSynchronizedRootGroup` — files in `DailyTrack/` auto-join the main app target; files also needed by the widget target must be added to the exception set at the top of `project.pbxproj` (look for the block listing `Models/TaskDefinition.swift`, `Models/DailyEntry.swift`, `Shared/AppGroupContainer.swift`).
- **Cloudflare Worker**: `cd cloudflare-worker && npm install`. Dev server: `npm run dev`. Deploy: `npm run deploy`. D1 migrations: `npm run db:migrate:remote`. Sync token is a Cloudflare secret, not in `wrangler.toml`.
- **D1 time-travel recovery**: `npx wrangler d1 time-travel info dailytrack-sync --timestamp "YYYY-MM-DDTHH:MM:SSZ" --json` then `npx wrangler d1 time-travel restore dailytrack-sync --bookmark "<id>"`.

## SourceKit / LSP Warning
Claude Code's SourceKit integration misreports "Cannot find type X" on valid pre-existing code in this repo (e.g., `TaskDefinition`, `DailyEntry`, `AppGroupContainer`). This is caused by `PBXFileSystemSynchronizedRootGroup` not being reconciled the way Xcode's indexer does. Treat LSP diagnostics as unreliable here — rely on actual Xcode builds to verify changes. Only trust LSP errors when they flag a specific new Swift syntax issue independent of symbol resolution (e.g., SwiftUI optional-bound Picker tags needing `nil as Int?`).

## Key Files
- `DailyTrack/DailyTrack/DailyTrackApp.swift` — entry point, ModelContainer, initial sync.
- `DailyTrack/DailyTrack/Models/TaskDefinition.swift` — `@Model` task schema + `CodableTaskDefinition` for JSON/sync. Shared with widget target. New `@Model` fields MUST be optional for SwiftData lightweight migration.
- `DailyTrack/DailyTrack/Models/DailyEntry.swift` — `@Model` daily entry. Shared with widget target.
- `DailyTrack/DailyTrack/Sync/SyncManager.swift` — push/pull/reconcile against Cloudflare Worker. Last-write-wins conflict resolution; first-sync is server-wins regardless of timestamps. Pull merge uses defensive-overwrite pattern for optional fields (only overwrite when server sends a value).
- `DailyTrack/DailyTrack/Shared/PeriodWindow.swift` — single `periodWindow(for:on:)` free function used by both main app and widget. Shared with widget target.
- `DailyTrack/DailyTrack/Shared/AppGroupContainer.swift` — App Group container URL for widget data sharing.
- `DailyTrack/DailyTrack/Database/SeedData.swift` — first-launch seed tasks with deterministic `seed-*` IDs.
- `DailyTrack/DailyTrackWidget/DailyTrackWidget.swift` — widget views, timeline provider, score computation.
- `cloudflare-worker/src/index.ts` — Worker with auto-migrations (`ensureSyncedAtColumn`, `ensureCumulativePeriodColumn`, `ensurePeriodAnchorColumn`). Auth via Bearer token.
- `cloudflare-worker/schema.sql` — D1 schema source of truth.
- `CLAUDE_HANDOFF.md` — session history, current state, known issues, next steps.

## Conventions
- Adding a new task field: update `TaskDefinition`, `CodableTaskDefinition` (property, `CodingKeys`, decoder, `init(from task:)`), `SyncManager` (push payload + pull merge + new-task insert), Worker (`ensure*Column` migration + INSERT/ON CONFLICT columns), `schema.sql`, `SettingsView` editor UI.
- Prefer `try?` when decoding optional fields from the Worker so older Workers that omit the field decode as nil rather than throwing.
- Never let a nil server value overwrite a local non-nil value — guard with `if let`.
