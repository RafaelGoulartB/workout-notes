# Plan: Run Achievements (Strava-like PRs)

## Context & Goal

Add an all-time personal-records system for GPS runs, similar to Strava:

- Rank **gold / silver / bronze** (1st / 2nd / 3rd best) per category.
- Categories: longest distance, longest moving time, best average pace, best km split, and best efforts (1K / 3K / 5K / 10K / half / marathon when the run covers that distance).
- Surface medals on **history list cards**, a section on **run detail**, and a dedicated **Achievements / PRs** block on **run stats** (option B).

No backend. Ranking is recomputed from local SQLite `run_activities` (+ track points for effort PRs). Scope is **all-time only**.

## Design decisions

| Topic | Choice |
|---|---|
| Ranking window | All-time (status = `completed`) |
| Medal meaning | Gold = best, silver = 2nd, bronze = 3rd in that category |
| Avg pace eligibility | Only runs with `distanceMeters >= 1000` (and valid `avgPaceSecPerKm`) |
| Duration metric | Prefer `movingTimeSeconds` (fallback `durationSeconds`) |
| Best km split | Fastest **completed** 1 km split (`isPartial == false`) from GPS |
| Best efforts (1/3/5/10K, half, marathon) | Fastest contiguous GPS segment covering the target distance (sliding window on cumulative distance) |
| Persistence | **No new medal table.** Cache effort times on the activity (or a thin cache map in memory per screen load). Recompute ranks in pure Dart |
| Ties | Earlier `startedAt` wins the higher medal (deterministic) |

### Categories (launch set)

1. `longestDistance` — max `distanceMeters`
2. `longestDuration` — max moving time
3. `bestAvgPace` — min `avgPaceSecPerKm` (≥ 1 km)
4. `bestKmSplit` — min completed km-split pace
5. `bestEffort1k` / `3k` / `5k` / `10k` / `half` (21097.5 m) / `marathon` (42195 m) — only if activity distance ≥ target

A run can hold multiple medals across categories (e.g. gold distance + bronze 5K).

### Effort caching strategy (performance)

Loading GPS for every activity on every history open is too heavy.

1. Extend import / a one-shot backfill to compute and store effort fields on `run_activities`:
   - `best_split_pace_sec_per_km`
   - `best_effort_1k_sec`, `best_effort_3k_sec`, `best_effort_5k_sec`, `best_effort_10k_sec`, `best_effort_half_sec`, `best_effort_marathon_sec`
2. Bump `_dbVersion`, add columns in `_onCreate` + `_onUpgrade`.
3. On spool import (and optional “recompute efforts” when opening detail if null), fill missing columns from track points.
4. Ranking engine reads **only** activity rows — no GPS in list/stats paths.

If a column is null (old runs), that activity is simply ineligible for that effort category until backfill runs (detail open or stats refresh backfill).

## Affected Files

### New
- `lib/models/run_achievement.dart` — `RunAchievementKind`, `RunMedalTier` (gold/silver/bronze), `RunAchievementPlacement`, `RunAchievementBoard`
- `lib/utils/run_effort_analytics.dart` — sliding-window best efforts + best completed split from track points (or extend `run_pace_analytics.dart`)
- `lib/utils/run_achievement_engine.dart` — pure ranking: activities → board + per-activity medal map
- `lib/widgets/run/run_medal_badge.dart` — compact gold/silver/bronze chip(s) for list/detail
- `lib/widgets/run/run_achievements_section.dart` — PR board UI (category rows with top-3 + tap → detail)
- `test/run_effort_analytics_test.dart`
- `test/run_achievement_engine_test.dart`

### Modified
- `lib/models/run_activity.dart` — new optional effort fields + `fromMap`/`toMap`/`copyWith`
- `lib/database/database_helper.dart` (and schema/migrations helpers if split) — bump version, add columns
- `lib/repositories/run_repository.dart` — write effort fields on import; `backfillEffortMetrics(activityId)` / `backfillMissingEfforts(limit)`
- `lib/screens/run/run_history_screen.dart` — compute board; pass medals into `_RunHistoryCard`
- `lib/screens/run/run_detail_screen.dart` — ensure efforts filled; show “Achievements” medals for this run
- `lib/screens/run/run_stats_screen.dart` — dedicated Achievements section (all-time), wire taps to detail
- `lib/utils/run_progress_analytics.dart` — optional: keep existing highlights, or point them at gold of board (avoid duplicate logic drift)
- `lib/l10n/app_en.arb` + `lib/l10n/app_pt.arb` — `runAchievement*` keys; then `flutter gen-l10n`

## Implementation Checklist

### Phase 1: Data + effort math

- [x] Add effort columns to schema (`_dbVersion` bump + upgrade ALTER TRY).
- [x] Extend `RunActivity` with nullable effort fields.
- [x] Implement `RunEffortAnalytics.bestEfforts(points)`.
- [x] On `importNativeSpool`, compute and persist efforts.
- [x] Add `backfillMissingEfforts` (batch) called from stats/history load.

### Phase 2: Ranking engine

- [x] Define `RunAchievementKind` enum + display metadata.
- [x] `RunAchievementEngine.build(List<RunActivity>)` → `RunAchievementBoard`.
- [x] Unit tests: ordering, ties, ineligibility, multi-medal same run.

### Phase 3: UI widgets

- [x] `RunMedalBadge` / `RunMedalDot` / `RunMedalBadgeRow`.
- [x] `RunAchievementsSection` + detail block.
- [x] l10n EN+PT.

### Phase 4: Screen integration

- [x] History badges + backfill.
- [x] Detail achievements block.
- [x] Stats personal records section (all-time).

### Phase 5: Validation

- [x] Unit tests for effort sliding window.
- [x] Unit tests for engine top-3 + badges map.
- [x] Targeted `flutter test` + `flutter analyze` on touched files.

## UI sketch (behavioral)

**History card:** title row + medal chips (e.g. 🥇 Distância · 🥉 5K).

**Detail:** “Conquistas” — chips with full labels (“1º · Melhor 5K”).

**Stats:** section “Recordes pessoais” — each category shows top 3 rows (medal · value · date · chevron).

## Risks & Technical Debt

- **Backfill cost:** first open after upgrade may touch many GPS rows — batch with a small limit per frame/load and progress silently.
- **GPS noise on efforts:** reuse pace clamps / min step from `RunPaceAnalytics`; document that efforts are GPS-estimated.
- **Half/marathon rarity:** categories still appear but stay empty until someone covers the distance — UI should hide empty categories or show “—” locked row (prefer **hide until ≥1 eligible**).
- **Schema drift:** AGENTS.md mentions older DB patterns; follow current `database_helper` / migrations helpers already used for wellness/run tables.
- Do **not** add Riverpod/Bloc; keep `setState` + pure engine.

## Out of scope (unless requested later)

- Monthly / yearly leaderboards
- Trophy cabinet / share cards
- Achievements for non-GPS workouts
- Live PR celebration modal after finishing a run (nice follow-up: toast if new gold)
