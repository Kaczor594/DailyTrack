---
created: 2026-07-15
modified: [2026-07-15]
sessions: [2026-07-15]
commits: [bce0b18, 52eec55, 4383777, b566bd3, c2631ef, 84e4621]
back_refs:
  - CLAUDE_HANDOFF.md#next-steps
  - https://claude.ai/design/p/e686602b-8427-4a34-b26d-b75aa54cb714 (Isaac Kaczor Design System — colors_and_type.css is source of truth; README there is stale blue/Inter direction)
forward_refs: []
status: in-progress
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

- [x] `cd cloudflare-worker && npm run deploy` → version 5bace853, https://dailytrack-api.isaac-kaczor.workers.dev
- [x] Verify `period_anchor` in `pragma_table_info('tasks')` → present (auto-migration ran)
- [x] Snapshot taken 2026-07-15 (see Amendments — live state diverged heavily from seed; plan adjusted per user)
- [x] Soft-delete `seed-bewerben` (tasks + its daily_entries), fresh `updated_at`/`synced_at`
- [x] `seed-municipal-analytics` → `is_cumulative=1, cumulative_period='month', benchmark=87.5` (weight stays 4, unit stays 'Stunden' — amended)
- [x] INSERT `seed-gc-vorbereitung` — 'GC Vorbereitung', benchmark 1.0, unit 'Stunden', weight 2.0, sort_order 17 (amended)
- [x] ~~`seed-putzen`, `seed-schach-lesen` → weight 0.5~~ dropped per amendment (minimal touch; schach-lesen already deleted)
- [x] Backfill `daily_entries` id `seed-municipal-analytics-2026-07-10`, value 9.5, notes 'Catch-up: hours worked 1-15 Jul'

Final weights: Municipal 4.0 (unchanged, top work priority), GC Vorbereitung 2.0 (new), all other user-set weights untouched (Putzen 5, Claude Nutzung 5, rest 0.5–1).

**Validation (gate — do not start Phase 2 until these pass):**
- [x] `npx wrangler d1 execute dailytrack-sync --remote --json --command "SELECT ..."` → PASSED 2026-07-15: `seed-bewerben` deleted=1; `seed-municipal-analytics` benchmark=87.5, weight=4, is_cumulative=1, cumulative_period='month'; `seed-gc-vorbereitung` present, weight=2, sort_order=17
- [x] entries SELECT → PASSED: row `seed-municipal-analytics-2026-07-10` value=9.5 deleted=0
- [ ] Manual: device Sync Now → GC Vorbereitung visible, Bewerben gone, municipal shows month progress 9.5/87.5 (user to confirm on iPhone/Mac)

## Phase 2 — SeedData.swift matches new reality

- [x] Remove `seed-bewerben` block + all `("Bewerben", n)` tuples from `historicalData`
- [x] Municipal: benchmark 87.5, weight 4.0 (amended), isCumulative true, cumulativePeriod "month"
- [x] Add `seed-gc-vorbereitung` (same ID as server row), benchmark 1.0, weight 2.0, sortOrder 17 (amended)
- [x] ~~Putzen/Schach-Lesen weight 0.5~~ dropped per amendment (minimal touch)
- [x] Append `("2026-07-10", [("Municipal Analytics", 9.5)])` to historicalData (name-keyed lookup unchanged — no renames)

**Validation (gate):**
- [x] `cd DailyTrack && xcodebuild -scheme DailyTrack -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3` → `** BUILD SUCCEEDED **` (note: `CODE_SIGNING_ALLOWED=NO` required for headless builds — no Mac App Development provisioning profile outside Xcode)
- [x] `cd DailyTrack && xcodebuild -scheme DailyTrack -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

## Phase 3 — Sync error banner + pull-to-refresh

- [x] Dismissible banner (`SyncErrorBanner` in DailyView.swift) at top of DailyView VStack when `syncManager.lastError != nil`: warning icon, error caption, Retry button, xmark dismiss
- [x] `.refreshable { await syncManager.sync(context: modelContext); viewModel.loadData(context: modelContext) }` on DailyView ScrollView
- [x] New strings ("Sync failed" → "Sync fehlgeschlagen", "Retry" → "Erneut versuchen") in Localizable.xcstrings; Settings error caption kept

**Validation (gate):**
- [x] Both xcodebuild commands (as Phase 2) → `** BUILD SUCCEEDED **` (2026-07-15)
- [ ] Manual: garbage API URL → pull-to-refresh → banner appears; dismiss works; correct URL + Retry → banner clears (user to confirm)

## Phase 4 — Theme foundation (plumbing only)

- [x] Download 7 static TTFs + OFL licenses into `DailyTrack/DailyTrack/Fonts/` (Fraunces 1.000 release has no Medium cut → used Fraunces72pt-Regular + SemiBold, matching the token file's weight-400 display convention; 2 OFL files — vercel/geist-font ships one license covering Geist + Geist Mono)
- [x] Verify PostScript names via CoreText: Fraunces72pt-Regular, Fraunces72pt-SemiBold, Geist-Regular/-Medium/-SemiBold, GeistMono-Regular/-Medium — hardcoded in Theme.swift
- [x] `Theme.xcassets`: colorsets light/dark — ThemeBackground #F8F5EE/#15140F, ThemeSurface #F2EEE4/#211F1A, ThemePanel #E8E2D2/#322F27, ThemeDivider #D8CFB8/#454339, ThemeInk #0E0D09/#FDFCF8, ThemeInkSecondary #5E5C52/#A8A59A, ThemeInkTertiary #807D72/#807D72, ThemeBrand #3E5A32/#8FA474, ThemeBrandSubtle #E6EBDD/#1F301A, ThemeTerra #B96F3E/#D29972, ThemeTerraSubtle #F4E4D7/#6D3E20, ThemePositive #5F784A/#8FA474, ThemeNegative #A63826/#C4573C (dark tint is derived, not in token file — Isaac sign-off), ThemeWarning #92552D/#D29972, ThemeInfo #3E5F74/#7A98A9, ChartMoss/Terra/Sky/Dust/Stone/Sage, HeatmapZero #CDCAC0/#454339 + HeatmapL1–L4 moss ramp (inverted in dark so intensity rises with score)
- [x] `Theme.swift`: Color accessors, `chartSeries`, unified `scoreColor(ratio:)` (0→ink-tertiary; <0.4→negative; <0.7→terra; <0.9→dust; ≥0.9→brand), `heatmapColor(score:)` + label-contrast helper, radii (card 8/control 4/bar 2), font helpers display/body/mono
- [x] `FontRegistration.swift`: `CTFontManagerRegisterFontsForURL(_, .process, nil)` over bundled TTFs; called from `DailyTrackApp.init()` + new `DailyTrackWidgetBundle.init()`
- [x] pbxproj: added Theme/Theme.swift, Theme/FontRegistration.swift, Theme/Theme.xcassets, Fonts/*.ttf to exception set `F251A5C82F32D14D00C7D823`
- [x] Filled AccentColor (app + widget) with #3E5A32/#8FA474; WidgetBackground #F8F5EE/#15140F

**Validation (gate):**
- [x] Both xcodebuild commands → `** BUILD SUCCEEDED **` (2026-07-15)
- [x] 7 TTFs in DailyTrack.app/Contents/Resources AND in DailyTrackWidgetExtension.appex/Contents/Resources; ThemeBrand present in both compiled Assets.car
- [ ] Manual: Mac app runs, accent is moss, no font-fallback console warnings (user check; fonts verified via CoreText pre-bundle)

## Phase 5 — App restyle (light + dark)

- [x] DailyView: ring track ThemeDivider, fill scoreColor, % in Fraunces; cards ThemeSurface + 8pt radius + 1px hairline (drop `.regularMaterial`); deleted local `scoreColor` + `badgeColor`; flame→Terra, period badges→Brand/Info; numerals mono; bg ThemeBackground; banner → Negative/TerraSubtle
- [x] HistoryView: StatCards (flame Terra, trophy Dust, avg Sky, days Brand); trend chart moss line + 0.25→0.03 area, mono axis labels; heatmap → `Theme.heatmapColor` (deleted `colorForScore`); breakdown → `Theme.scoreColor` (deleted `colorForRatio`)
- [x] SettingsView: themed list bg + `.listRowBackground(Theme.surface)` on all sections, badges BrandSubtle/Info at 4pt, checkmark Positive, error Negative, headers Geist

**Validation (gate):**
- [x] Both xcodebuild commands → `** BUILD SUCCEEDED **` (2026-07-15)
- [x] leftover-color-literal grep over Views/ → no output (exit 1)
- [ ] Manual: light + dark pass on all three tabs (user check — not run headless to avoid touching live App Group data with an unsigned build)

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

**2026-07-15 (later) — weight-principle pass.** Isaac's rule: task weight ≈ hours/day (weekly-cumulative ≈ hours/week); saved to global memory. Applied via D1 + SeedData after Phases 1–3 landed: GC Vorbereitung benchmark 1→2 h/day (weight stays 2); Municipal weight 4→5 (mirrors real ≈4.9 h/day July crunch; app's derived daily target stays ≈2.8 since the monthly window spans all of July); 7 routine checkboxes (Staubsaugen, Schach, Geschirr Spülen, Küche Putzen, Aufräumen, Personal Grooming, Nachtzeit-Routine) 1.0→0.5. Training, DAV Studieren, Kochen, Nebenprojekt, Wäsche stay 1.0.

**2026-07-15 — Phase 1 adjusted to live server state.** Snapshot showed heavy user customization since seed: 17 active tasks; Municipal already weight 4 (daily 4 Stunden, non-cumulative); Bewerben now weekly-cumulative 12/week; Putzen weekly-cumulative weight 5; Claude Nutzung weekly 100 weight 5 anchor Wed; DAV Studieren checkbox exists; seed-schach-lesen/-nebenprojekt/-aktuarwissenschaft already deleted (replaced by user's own tasks). July municipal entries: none (backfill 9.5 confirmed correct). User chose (AskUserQuestion): **minimal touch** — Municipal keeps weight 4 (only becomes monthly 87.5 Stunden), GC Vorbereitung added at weight 2 sort_order 17, no other weight changes (Putzen/Claude Nutzung deliberate); "demote putzen/schach-lesen" tasks dropped. Units stay German ("Stunden"). GC task confirmed as new task, not a Bewerben repurpose.
