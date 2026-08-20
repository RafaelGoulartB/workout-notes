# Plan: Run Detail — Pace Chart + Strava-inspired UI

## Context

`RunDetailScreen` today shows map + date + wrapped `_StatChip` cards + notes. It does **not** show pace-over-distance, splits, or a Strava-like hierarchy.

Goal (scoped):
1. Keep everything on **`RunDetailScreen`** (no separate Analysis screen).
2. Derive the pace series from **saved GPS track points** (no new persistence).
3. Keep the **map**, replace chip cards with a **clean 2-column metrics grid**, then add **Pace** (chart + stats) and **Parciais** (splits with bars).

Inspiration from attached Strava refs: overview metrics grid, area pace chart (inverted Y, avg dashed line, touch tooltip), splits table with relative horizontal bars.

## Affected Files

- `lib/utils/run_pace_analytics.dart` (**new**): pure functions — haversine cumulative distance, rolling pace samples, km splits, best/avg helpers.
- `lib/widgets/run/run_pace_chart.dart` (**new**): `fl_chart` area chart + touch tooltip + avg line.
- `lib/widgets/run/run_splits_list.dart` (**new**): km / pace / bar rows (elevation column omitted — no reliable elev gain yet).
- `lib/screens/run/run_detail_screen.dart`: restructure layout; wire analytics from `_points` + `activity`.
- `lib/utils/run_formatters.dart`: small helpers if needed (e.g. distance axis labels).
- `lib/l10n/app_en.arb` + `lib/l10n/app_pt.arb`: new `runDetail*` keys (Pace section, splits, best pace, chart empty).
- `test/run_pace_analytics_test.dart` (**new**): unit tests for series + splits from synthetic points.
- (Optional polish) reuse formatting already in `RunFormatters`; no schema / repo changes.

## Implementation Checklist

### Phase 1: Pace analytics (pure Dart)

- [x] Add `RunPaceSample { distanceMeters, paceSecPerKm }` (and maybe `RunPaceSummary`).
- [x] Implement cumulative distance along track via haversine (match Kotlin `RunGeoMath` formula).
- [x] Build pace series:
  - Prefer rolling window by distance (e.g. ~50–100 m) using Δt / Δd → sec/km.
  - Clamp outliers (very fast/slow GPS noise) so the chart Y range stays readable.
  - Downsample for long runs (cap ~150–200 points) for chart performance.
- [x] Build km splits from the same cumulative path (full km + final partial), aligned with live `RunSplit` shape.
- [x] Helpers: `bestPaceSecPerKm` (fastest completed km), series empty when &lt; ~2 points or distance ≈ 0.

### Phase 2: UI widgets

- [x] `RunPaceChart`:
  - Area under line filled with `primary` (theme-aware, works in dark mode).
  - **Inverted Y** (faster pace at top).
  - Horizontal dashed average-pace line.
  - X = distance (km), Y = pace (m:ss).
  - Touch tooltip: pace + distance at scrub point (`fl_chart` `LineTouchData`).
  - Empty/insufficient data → short localized placeholder (no crash).
- [x] `RunSplitsList`:
  - Header: KM | Ritmo (+ optional Tempo if space).
  - Bar length ∝ relative speed vs slowest/best split (longer = faster), like Strava.
  - Partial last km labeled distinctly (reuse `runRecordSplitPartial` or new detail key).
- [x] Metrics grid widget (inline or small private widget): label above value, 2 columns, **no cards**/borders — Strava overview style.

### Phase 3: `RunDetailScreen` layout

Order (scroll):
1. Map (keep current height/behavior; keep bounds safety).
2. Date/time (muted).
3. Title already in AppBar — optional large title in body only if notes/title deserve it; prefer AppBar as today.
4. **Key metrics grid** (2×N): Distância, Pace médio, Tempo em movimento, Tempo total, Calorias; drop card chips.
5. Notes (if any).
6. Section **Pace**: chart + list rows below (Avg Pace, Moving Time, Elapsed Time, Fastest Split / Melhor ritmo).
7. Section **Parciais**: splits list.
8. Hide Pace/Parciais sections when analytics empty (very short / no points).

### Phase 4: Localization

- [x] Add keys in **both** ARBs, e.g.:
  - `runDetailPaceSection`, `runDetailSplitsSection`
  - `runDetailBestPace` / `runDetailFastestSplit`
  - `runDetailPaceChartEmpty`
  - Reuse existing `runDetailAvgPace`, times, calories, and record split labels where they fit.
- [x] Run `flutter gen-l10n`.

### Phase 5: Validation

- [x] Unit tests: synthetic straight-line points → expected cumulative km, pace samples monotonic in distance, splits at 1000 m boundaries, partial remainder.
- [ ] Manual: open Debug Run detail → chart scrubs, avg line visible, splits match live sheet roughly, dark theme readable.
- [x] `flutter analyze` on touched files; `flutter test test/run_pace_analytics_test.dart`.

## Risks & Technical Debt

- **GPS noise** can make instant pace jagged; rolling window + clamp is required or the chart looks broken.
- Track points may lack usable `speed`; derive pace from Δdistance/Δtime only (ignore sparse `speed` unless validated later).
- **Elevation** exists on points but gain/loss not computed — omit Elev column for now (avoids fake “0 m” like debug Strava walks).
- Live recording already has splits in memory; detail recomputes from points — small numeric drift vs in-run sheet is acceptable; document in test tolerances.
- Do not add a second Analysis route or persist pace series in this pass.

## Decisions locked

| # | Choice |
|---|--------|
| 1 | A — only `RunDetailScreen` |
| 2 | A — derive series from track points |
| 3 | A — map + clean grid + Pace + Parciais |
