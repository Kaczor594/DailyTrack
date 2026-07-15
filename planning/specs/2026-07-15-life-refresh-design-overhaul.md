---
created: 2026-07-15
modified: [2026-07-15]
sessions: [2026-07-15]
commits: []
back_refs:
  - CLAUDE_HANDOFF.md#next-steps
  - https://claude.ai/design/p/e686602b-8427-4a34-b26d-b75aa54cb714 (Isaac Kaczor Design System — colors_and_type.css is source of truth; README there is stale blue/Inter direction)
forward_refs: []
status: draft
---

# Life Refresh + Design-System Overhaul

## Problem

Isaac signed with Guy Carpenter (starts 2026-08-01) and stopped job hunting; he must bill ≈$3,500 of municipal analytics work by July 31 ($40/h → 87.5 h total; 9.5 h worked, not yet logged in the app). DailyTrack's tracked tasks still reflect the old life (Bewerben, low-weight municipal). Six handoff next-steps are also open (Worker deploy, sync error UI, pull-to-refresh, monthly/yearly anchors, SeedData staleness, public repo), and the app uses ad-hoc system styling instead of Isaac's personal design system.

## Solution

Eight independently landable phases: (1) server-side D1 life update — time-sensitive, zero app code; (2) SeedData refresh; (3) sync UX; (4) design-system plumbing (bundled Fraunces/Geist/Geist Mono TTFs, Theme.xcassets light+dark, unified `Theme.scoreColor`); (5) app restyle; (6) widget restyle; (7) monthly/yearly period anchors; (8) public repo + docs. When done: tasks match the new life with July earnings tracked as a monthly cumulative 87.5 h target, all handoff items closed, app + widget fully on the paper/stone/moss design language in both modes.

User decisions (2026-07-15): bundle real TTFs; remove Bewerben; municipal→monthly 87.5 h; add GC-prep task; rebalance weights; backfill 9.5 h; apply via direct D1 SQL.

## Verified sync mechanics (Phase 1 correctness)

- Pull query: `WHERE synced_at > since` (`cloudflare-worker/src/index.ts:73-78`) → every SQL-touched row needs fresh `synced_at`; fresh `updated_at` also required to win last-write-wins merge (`SyncManager.swift:272`).
- New server tasks skipped when `createdAt < since` (`SyncManager.swift:309`) → new rows need `created_at` = now.
- Server-deleted task → client soft-deletes + cascades to entries (`SyncManager.swift:256-262`); deletion wins both directions.
- All SQL timestamps via `strftime('%Y-%m-%dT%H:%M:%fZ','now')` (JS-compatible millisecond format, lexicographic compare).
- Deterministic entry IDs `<taskId>-<yyyy-MM-dd>` → backfill upserts via `ON CONFLICT(id)`.

## Files

**Existing (touched):**
- `cloudflare-worker/` — deploy only (code already has `ensurePeriodAnchorColumn`)
- `DailyTrack/DailyTrack/Database/SeedData.swift` — new task reality
- `DailyTrack/DailyTrack/Views/DailyView.swift` — banner, refreshable, restyle
- `DailyTrack/DailyTrack/Views/HistoryView.swift` — restyle
- `DailyTrack/DailyTrack/Views/SettingsView.swift` — restyle + month/year anchor pickers
- `DailyTrack/DailyTrack/Shared/PeriodWindow.swift` — anchored month/year branches
- `DailyTrack/DailyTrackWidget/DailyTrackWidget.swift` — restyle, shared scoreColor, period value fix
- `DailyTrack/DailyTrack/DailyTrackApp.swift` — font registration call
- `DailyTrack/DailyTrack.xcodeproj/project.pbxproj` — widget-membership exception set `F251A5C82F32D14D00C7D823`
- `DailyTrack/DailyTrack/Assets.xcassets/AccentColor.colorset`, `DailyTrack/DailyTrackWidget/Assets.xcassets/{AccentColor,WidgetBackground}.colorset` — fill with moss/bg
- `DailyTrack/DailyTrack/Localization/Localizable.xcstrings` — new strings + DE
- `../DailyTrack-public/` — Phase 8 port (separate working copy; NEVER copy private SeedData or cross-push)
- `CLAUDE_HANDOFF.md`, `CLAUDE.md` — docs refresh

**New:**
- `DailyTrack/DailyTrack/Theme/Theme.swift` — colors, fonts, radii, scoreColor/heatmapColor (shared w/ widget)
- `DailyTrack/DailyTrack/Theme/FontRegistration.swift` — CTFontManager registration (shared w/ widget)
- `DailyTrack/DailyTrack/Theme/Theme.xcassets` — ~26 light/dark colorsets (shared w/ widget)
- `DailyTrack/DailyTrack/Fonts/` — 7 static TTFs (Fraunces Medium/SemiBold; Geist Regular/Medium/SemiBold; GeistMono Regular/Medium) + 3 OFL licenses
- `DailyTrack/DailyTrack/Views/SyncErrorBanner.swift` (optional split-out)

## Phase 1 — Deploy Worker + D1 life update

Time-sensitive; zero app-code changes. Prerequisite: `npx wrangler whoami` succeeds (user runs `npx wrangler login` if not).

- [ ] `cd cloudflare-worker && npm run deploy`
- [ ] Verify `period_anchor` in `pragma_table_info('tasks')`; if absent run `ALTER TABLE tasks ADD COLUMN period_anchor INTEGER`
- [ ] Snapshot: `SELECT id, name, benchmark, unit, weight, is_cumulative, cumulative_period, sort_order, is_active, deleted, updated_at FROM tasks ORDER BY sort_order` → record output under Notes; adjust assumptions if server differs from seed expectations
- [ ] Soft-delete `seed-bewerben` (tasks + its daily_entries), fresh `updated_at`/`synced_at`
- [ ] `seed-municipal-analytics` → `is_cumulative=1, cumulative_period='month', benchmark=87.5, unit='hours', weight=3.0`
- [ ] INSERT `seed-gc-vorbereitung` — 'GC Vorbereitung', benchmark 1.0, unit 'hours', weight 2.0, is_cumulative 0, cumulative_period 'none', is_checkbox 0, sort_order 3, is_active 1, deleted 0, fresh created/updated/synced (omit `period_anchor` from column list)
- [ ] `seed-putzen`, `seed-schach-lesen` → weight 0.5
- [ ] Backfill `daily_entries` id `seed-municipal-analytics-2026-07-10`, value 9.5, notes 'Catch-up: hours worked 1–15 Jul', `ON CONFLICT(id) DO UPDATE SET value=9.5, deleted=0, notes=excluded.notes, updated_at=excluded.updated_at, synced_at=excluded.synced_at`

Final weights (daily-score share): Municipal 3.0 (37.5%), GC Vorbereitung 2.0 (25%), Nebenprojekt 1.0, Training 1.0, Putzen 0.5, Schach/Lesen 0.5. Aktuarwissenschaft stays 1.0 (lifetime-cumulative → score-exempt).

**Validation (gate — do not start Phase 2 until these pass):**
- `npx wrangler d1 execute dailytrack-sync --remote --json --command "SELECT id, name, benchmark, unit, weight, is_cumulative, cumulative_period, sort_order, deleted FROM tasks ORDER BY sort_order"` → `seed-bewerben` deleted=1; `seed-municipal-analytics` benchmark=87.5, weight=3, is_cumulative=1, cumulative_period='month'; `seed-gc-vorbereitung` present, weight=2, sort_order=3; putzen/schach-lesen weight=0.5
- `npx wrangler d1 execute dailytrack-sync --remote --json --command "SELECT id, date, value, deleted FROM daily_entries WHERE task_id='seed-municipal-analytics' AND date>='2026-07-01'"` → row `seed-municipal-analytics-2026-07-10` value=9.5 deleted=0
- Manual: device Sync Now → GC Vorbereitung visible, Bewerben gone, municipal shows month progress 9.5/87.5

## Phase 2 — SeedData.swift matches new reality

- [ ] Remove `seed-bewerben` block + all `("Bewerben", n)` tuples from `historicalData`
- [ ] Municipal: benchmark 87.5, unit hours, weight 3.0, isCumulative true, cumulativePeriod "month"
- [ ] Add `seed-gc-vorbereitung` (same ID as server row), benchmark 1.0, weight 2.0, sortOrder 3
- [ ] Putzen/Schach-Lesen weight 0.5; fix Putzen `isCheckbox` staleness vs server if snapshot showed a difference
- [ ] Append `("2026-07-10", [("Municipal Analytics", 9.5)])` to historicalData (name-keyed lookup unchanged — no renames)

**Validation (gate):**
- `cd DailyTrack && xcodebuild -scheme DailyTrack -destination 'platform=macOS' build 2>&1 | tail -3` → `** BUILD SUCCEEDED **`
- `cd DailyTrack && xcodebuild -scheme DailyTrack -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

## Phase 3 — Sync error banner + pull-to-refresh

- [ ] Dismissible banner at top of DailyView VStack when `syncManager.lastError != nil`: warning icon, error caption, Retry button (`Task { await syncManager.sync(context:) }`), xmark dismiss (`lastError = nil`)
- [ ] `.refreshable { await syncManager.sync(context: modelContext); viewModel.loadData(context: modelContext) }` on DailyView ScrollView
- [ ] New strings ("Sync failed", "Retry") + DE translations in Localizable.xcstrings; keep existing Settings error caption

**Validation (gate):**
- Both xcodebuild commands (as Phase 2) → `** BUILD SUCCEEDED **`
- Manual: garbage API URL → pull-to-refresh → banner appears; dismiss works; correct URL + Retry → banner clears

## Phase 4 — Theme foundation (plumbing only)

- [ ] Download 7 static TTFs + OFL licenses into `DailyTrack/DailyTrack/Fonts/` (Fraunces: undercasetype/Fraunces release or google/fonts static; Geist/GeistMono: vercel/geist-font releases)
- [ ] Verify PostScript names via CoreText one-liner; hardcode verified names in Theme.swift
- [ ] `Theme.xcassets`: colorsets light/dark — ThemeBackground #F8F5EE/#15140F, ThemeSurface #F2EEE4/#211F1A, ThemePanel #E8E2D2/#322F27, ThemeDivider #D8CFB8/#454339, ThemeInk #0E0D09/#FDFCF8, ThemeInkSecondary #5E5C52/#A8A59A, ThemeInkTertiary #807D72/#807D72, ThemeBrand #3E5A32/#8FA474, ThemeBrandSubtle #E6EBDD/#1F301A, ThemeTerra #B96F3E/#D29972, ThemeTerraSubtle #F4E4D7/#6D3E20, ThemePositive #5F784A/#8FA474, ThemeNegative #A63826/#C4573C (dark tint is derived, not in token file — Isaac sign-off), ThemeWarning #92552D/#D29972, ThemeInfo #3E5F74/#7A98A9, ChartMoss/Terra/Sky/Dust/Stone/Sage, HeatmapZero #CDCAC0/#454339 + HeatmapL1–L4 moss ramp (inverted in dark so intensity rises with score)
- [ ] `Theme.swift`: Color accessors, `chartSeries`, unified `scoreColor(ratio:)` (0→ink-tertiary; <0.4→negative; <0.7→terra; <0.9→dust; ≥0.9→brand), `heatmapColor(score:)` + label-contrast helper, radii (card 8/control 4/bar 2), font helpers display/body/mono
- [ ] `FontRegistration.swift`: `CTFontManagerRegisterFontsForURL(_, .process, nil)` over bundled TTFs; call from `DailyTrackApp.init()` + new `DailyTrackWidgetBundle.init()`
- [ ] pbxproj: add Theme/Theme.swift, Theme/FontRegistration.swift, Theme/Theme.xcassets, Fonts/*.ttf to exception set `F251A5C82F32D14D00C7D823`
- [ ] Fill AccentColor (app + widget) with #3E5A32/#8FA474; WidgetBackground #F8F5EE/#15140F

**Validation (gate):**
- Both xcodebuild commands → `** BUILD SUCCEEDED **`
- `ls .../DerivedData/DailyTrack-*/Build/Products/Debug/DailyTrack.app/Contents/Resources/*.ttf | wc -l` → 7; same inside `Contents/PlugIns/DailyTrackWidgetExtension.appex/Contents/Resources/` → 7
- Manual: Mac app runs, accent is moss, no font-fallback console warnings

## Phase 5 — App restyle (light + dark)

- [ ] DailyView: ring track ThemeDivider, fill scoreColor, % in Fraunces; cards ThemeSurface + 8pt radius + 1px hairline (drop `.regularMaterial`); delete local `scoreColor` + `badgeColor`; flame→Terra, period badges→Brand/Info; numerals mono; bg ThemeBackground; banner (Phase 3) → Negative/TerraSubtle styling
- [ ] HistoryView: StatCards (flame Terra, trophy Dust, avg Sky, days Brand); trend chart moss line, moss 0.25→0.03 area, mono axis labels; heatmap → `Theme.heatmapColor` (delete `colorForScore`); breakdown → `Theme.scoreColor` (delete `colorForRatio`)
- [ ] SettingsView: themed list bg, badges BrandSubtle/Info at 4pt, checkmark Positive, error Negative, headers Geist

**Validation (gate):**
- Both xcodebuild commands → `** BUILD SUCCEEDED **`
- `grep -rn "Color\.red\|Color\.orange\|Color\.green\|\.foregroundStyle(\.blue)\|\.foregroundStyle(\.orange)\|\.foregroundStyle(\.red)\|\.foregroundStyle(\.green)\|\.foregroundStyle(\.purple)" DailyTrack/DailyTrack/Views/` → no output (exit 1)
- Manual: light + dark pass on all three tabs (Mac)

## Phase 6 — Widget restyle

- [ ] Delete 3 local color helpers (`scoreColor` :308, `progressColor` :384, `barColor` :467) → `Theme.scoreColor` (fixes 0.3/0.7 vs 0.4/0.7/0.9 threshold drift)
- [ ] `containerBackground(Theme.background, for: .widget)` (3 places); ring track Divider; % Fraunces; names Geist; values mono; checkbox done Positive / pending InkTertiary; flame Terra; bars ThemePanel track + scoreColor fill radius 3
- [ ] Fix period-task value display: show derived daily target instead of `Int(value)/Int(benchmark)` when task `hasPeriod` (small WidgetTaskItem addition)

**Validation (gate):**
- `xcodebuild -scheme DailyTrackWidgetExtension -destination 'platform=macOS' build 2>&1 | tail -3` → `** BUILD SUCCEEDED **` + both app builds
- Manual: small/medium/large via Notification Center (WidgetKit Simulator broken on Mac), light + dark

## Phase 7 — Monthly/yearly anchors in task editor

Encoding in existing `periodAnchor: Int?` (no model/schema/Worker changes): month → day-of-month 1–28 (nil = 1st); year → `month*100+day` (801 = Aug 1 GC work-year; nil = Jan 1).

- [ ] PeriodWindow.swift: anchored month branch (most recent anchor-day ≤ date, clamp to month length) + year branch (mm/dd decode, validate, previous-year fallback); widget inherits (shared file)
- [ ] TaskEditorSheet: "Month starts on" picker (nil default + 2–28); "Year starts in" (Jan–Dec) + "On day" (1–28) pickers with nil default; extend anchor-clear-on-period-change logic; `nil as Int?` Picker-tag gotcha
- [ ] New strings + DE translations

**Validation (gate):**
- Both xcodebuild commands → `** BUILD SUCCEEDED **`
- Manual: monthly anchor 15 on a July date ≥15 → window Jul 15–Aug 14, derived daily target updates; yearly 801 → Aug 1–Jul 31 window
- `npx wrangler d1 execute dailytrack-sync --remote --json --command "SELECT id, cumulative_period, period_anchor FROM tasks WHERE period_anchor IS NOT NULL"` → test task's anchor round-trips

## Phase 8 — Public repo + docs

- [ ] Port to `../DailyTrack-public/`: Shared/PeriodWindow.swift (missing there), Models, Sync, ViewModels, Views, widget, Theme/ + Fonts/ (+OFL — required for redistribution), pbxproj exception additions, worker src/index.ts + schema.sql
- [ ] NEVER copy private SeedData.swift (public one sanitized) or blindly copy Localizable.xcstrings (port only new UI strings); fix README `Sources/` path issue
- [ ] Commit + push in public working copy to its own origin only
- [ ] Private repo: refresh CLAUDE_HANDOFF.md (new state, D1 change log, theme architecture) + CLAUDE.md Key Files (Theme.swift)

**Validation (gate):**
- `cd ../DailyTrack-public && git remote get-url origin` → `…Kaczor594/DailyTrackApp.git`
- `grep -c "seed-reading" ../DailyTrack-public/DailyTrack/DailyTrack/Database/SeedData.swift` → ≥1 (sanitized seed intact)
- Public-copy `xcodebuild -scheme DailyTrack -destination 'platform=macOS' build` → `** BUILD SUCCEEDED **`

## Final validation

- All phase gates green
- Fresh build to Mac + Sync Now → GC Vorbereitung present, Bewerben gone, municipal month progress 9.5/87.5 + entries added since
- iPhone sync round-trip confirms the same; light+dark visual pass on all tabs + 3 widget sizes

## Notes

- **Revisit ~2026-08-01**: municipal monthly target drops when the GC job starts; GC Vorbereitung retires or repurposes ("Einarbeitung"). Weights rebalance again.
- On 2026-07-10 the day score will exceed 100% for municipal (9.5 vs ≈2.82 derived daily) — expected; ring caps at 100%.
- Rollback for Phase 1: D1 time-travel (commands in CLAUDE.md); snapshot timestamp recorded below when taken.
- Cross-cutting: validation via real xcodebuild only (LSP unreliable here); no new @Model fields anywhere → zero SwiftData migration risk; stage files explicitly; never .DS_Store/xcuserdata.

## Amendments

(none yet)
