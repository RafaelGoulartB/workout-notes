# Plan: Custom running coach plans

## Context & Root Cause

Pre-made run plans create in one tap with fixed weekdays (Tue/Thu/Fri/Sun) and no pace targets. They do not ask how many days the athlete can train, which days, finish vs PB intent, volume aggressiveness, or race/goal time — so they feel generic rather than coach-built.

**Chosen product shape:** 1C (full coach inputs including pace calibration) + 2A (fixed intelligent weeks: build / recovery / taper at create time).

## Affected Files

- `lib/services/run_pace_calculator.dart` *(new)*: race/goal time → easy / tempo / interval paces
- `lib/services/run_plan_composer.dart` *(new)*: `RunPlanBuildConfig` + compose schedule (days, intensity, week pattern, paces)
- `lib/screens/run/run_plan_customize_screen.dart` *(new)*: multi-step wizard
- `lib/services/run_plan_templates.dart`: expose blueprints; create from composed schedule with paces
- `lib/screens/run/run_plans_screen.dart`: template pick → customize screen (blank plan unchanged)
- `lib/l10n/app_en.arb` + `app_pt.arb`: wizard strings
- `test/run_pace_calculator_test.dart` *(new)*
- `test/run_plan_composer_test.dart` *(new)*

No DB migration: `target_pace_sec_per_km` and step pace min/max already exist.

## Implementation Checklist

### Phase 1: Core Logic
- [ ] `RunPaceCalculator` from recent race (distance + time) or goal race time → E / T / I sec/km
- [ ] `RunPlanBuildConfig`: sessions 3|4|5, availableDays, intent finish|pb, intensity, optional calibration
- [ ] `RunPlanComposer.compose(template, config)`:
  - Role lists: 3d = quality(alternate interval/tempo)+easy+long; 4d = I+E+T+L; 5d = + recovery
  - Map roles onto selected days (long prefers weekend; avoid adjacent quality; gap before long)
  - Scale volume/reps by intensity; recovery every 4th week; taper last 2
  - Attach paces when calibrated
- [ ] Persist paces via `addWorkout` / `addStep` on create

### Phase 2: UI / Integration
- [ ] `RunPlanCustomizeScreen`: days → intent/intensity → pace (skippable) → week-1 preview → create
- [ ] Wire picker in `run_plans_screen.dart` to open customize instead of immediate create
- [ ] ARB en+pt + `flutter gen-l10n`

### Phase 3: Template quality
- [ ] Keep catalog keys; `finish` biases easy-heavy, `pb` keeps quality emphasis
- [ ] Beginner/run-walk/maintenance: day remap + intensity only

### Phase 4: Validation
- [ ] Unit tests: day spacing, 3-day alternation, recovery/taper, pace ordering
- [ ] Create path smoke; `flutter analyze` + targeted tests

### Phase 5: Training quality pass

Review of the generated output found the paces sound (validated against Daniels'
VDOT tables to within ~10 s/km) but the composer unsound. Fixed:

- [x] **Weekday collisions** — day assignment is now per-week from a pool, so two
      quality kinds can never share a day and leave another day empty
- [x] **Race week** — was a full build week (a fartlek five days before a
      marathon). Now a short race-pace sharpener 3+ days out, easy days, race
- [x] **Race pace by goal distance** — `racePaceFor()` solves the VDOT model for
      the target distance; a 25:00 5K no longer prescribes a 5:00/km marathon
- [x] **Inverted pace ranges** — `orderedBand()` keeps the faster bound as `min`
- [x] **Volume as the primary quantity** — weekly budget drives the plan; the
      long run is a bounded share (was 47–69% of the week, now a steady ~45%);
      easy days absorb the remainder so realised volume tracks the budget
- [x] **Progression capped at ~10%/week** off the previous build week
- [x] **Taper inverted** — cuts volume, keeps intensity (was the reverse)
- [x] **Quality caps** — VO2 work ≤8% of weekly km, threshold ≤10%; rep distance
      shrinks on low-volume weeks instead of forcing an unrunnable rep count
- [x] **Rep recovery scales with rep duration** (was a flat 120 s for 1000 m)
- [x] **Hills by effort only** — no flat-ground pace on an uphill rep
- [x] **Marathon/half specificity** — goal-pace blocks and long runs finishing at
      race pace; the plans previously had no race-pace work at all
- [x] **Easy pace as a window**, threshold >20 min as cruise intervals, strides on
      one easy day per build week
- [x] `currentWeeklyKm` input anchors week 1 to the athlete's actual baseline
- [x] Run/walk capped at 4 days with spaced weekdays
- [x] `test/run_plan_composer_quality_test.dart`: 16 invariants, one per fix

## Risks & Technical Debt

- VDOT paces are estimates — UI copy must say targets, not prescriptions
- 3-day PB plans cannot carry full dual-quality load; alternation is the tradeoff
- Prefer extracting volume ladders into composer inputs over duplicating the 11 templates
