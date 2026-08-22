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

## Risks & Technical Debt

- VDOT paces are estimates — UI copy must say targets, not prescriptions
- 3-day PB plans cannot carry full dual-quality load; alternation is the tradeoff
- Prefer extracting volume ladders into composer inputs over duplicating the 11 templates
