# 🏋️ Workout Feature — Life Notes

> **Status:** Planning Phase  
> **Target:** First major feature after core Life Notes app  
> **Inspiration:** FitNotes (fitnotesapp.com)  
> **Goal:** Build a complete workout tracking system as one module inside the Life Notes app.

---

## 1. Core Philosophy

Life Notes is a **multi-feature life tracking app**. Workout tracking is one module alongside journaling, body tracking, habits, etc. Each module shares the same:
- Design system (Material 3 theming)
- Storage layer (local-first, extensible)
- Navigation structure

---

## 2. FitNotes Features — Adapted for Life Notes

Below is the full feature list extracted from FitNotes, mapped to our implementation plan.

### 2.1 Workout Session Management

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 1 | Start a workout (on-the-fly) | P0 | Add exercises from library, no routine needed |
| 2 | Start a workout (from routine) | P0 | Pre-populated from a saved routine |
| 3 | Exercise list by category (muscle group) | P0 | Categories like Chest, Back, Legs, etc. |
| 4 | Add custom exercises | P0 | Name, category, type (weight/reps, distance/time) |
| 5 | Search exercises | P0 | Text search across exercise names |
| 6 | Exercise favorites (star) | P1 | Quick-access favorite list |
| 7 | Record sets (weight × reps) | P0 | Core logging |
| 8 | Record sets (distance × time) | P0 | For cardio exercises |
| 9 | Record sets (weight only, reps only, time only, etc.) | P2 | Advanced types |
| 10 | Set auto-population from last workout | P1 | Pre-fill weight/reps from previous session |
| 11 | Edit / delete sets | P0 | Tap to edit, swipe to delete |
| 12 | Re-order sets | P1 | Drag to reorder |
| 13 | Re-order exercises in workout | P1 | Drag to reorder |
| 14 | Set comments | P1 | Per-set notes (e.g. "spotter helped") |
| 15 | Mark sets complete (checkbox) | P1 | Track progress through pre-planned workout |
| 16 | Auto-jump to next exercise | P2 | When all sets complete |
| 17 | Supersets / circuits | P2 | Group exercises, auto-advance between them |
| 18 | Rest timer | P1 | Countdown between sets with sound/vibrate |

### 2.2 Routine Management

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 1 | Create routine | P0 | Name + notes |
| 2 | Add days/sections to routine | P0 | e.g. "Push Day", "Pull Day", "Legs Day" |
| 3 | Add exercises to routine days | P0 | Select from exercise library |
| 4 | Predefined sets per exercise | P0 | Weight/reps with "copy previous" support |
| 5 | Log a routine workout | P0 | "Log All" from a routine day |
| 6 | Edit routine (add/remove exercises) | P0 | |
| 7 | Copy routine | P1 | Duplicate an existing routine |
| 8 | Delete routine | P0 | |
| 9 | Re-order days in routine | P1 | |
| 10 | Re-order exercises in routine day | P1 | |
| 11 | Supersets within routines | P2 | Group exercises with colour coding |
| 12 | View routine overview | P1 | See all days and exercises at a glance |

### 2.3 Progress Tracking & Analytics

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 1 | Training history per exercise | P0 | List of all past sets for an exercise |
| 2 | Progress graphs | P0 | Line charts for 1RM, volume, max weight, etc. |
| 3 | Estimated 1RM calculation | P0 | Using Epley or Brzycki formula |
| 4 | Actual personal records | P0 | Best weight lifted for each rep count |
| 5 | PR notifications | P1 | Highlight when a new PR is achieved |
| 6 | Statistics (volume, reps, sets) | P1 | By workout, week, month, year |
| 7 | Goals per exercise | P2 | Target weight for a given rep count |
| 8 | Trend line on graphs | P2 | See direction of progress |
| 9 | Share graph snapshot | P2 | Export to share progress |
| 10 | Exercise overview | P1 | Combined history + graph + records + stats |

### 2.4 Calendar & History Navigation

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 1 | Month view calendar | P0 | See which days had workouts |
| 2 | Muscle group colour dots | P1 | Coloured dots under dates show trained groups |
| 3 | List view calendar | P0 | Scrollable list of all past workouts |
| 4 | Tap a date to view workout | P0 | See full workout details |
| 5 | Copy previous workout | P1 | Base today's workout on a past one |
| 6 | Filter by category/exercise | P1 | Find specific workouts |
| 7 | Workout timer | P1 | Track session duration (auto + manual) |
| 8 | Workout comments | P1 | Notes about the session |
| 9 | Share workout (text summary) | P2 | Generate readable workout summary |

### 2.5 Body Tracker

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 1 | Track body weight | P0 | Daily weight logging |
| 2 | Track body fat % | P1 | |
| 3 | Custom measurements | P1 | Waist, chest, arms, etc. |
| 4 | Measurement with goals | P1 | "Increase", "Decrease", "Target Value" |
| 5 | History view | P1 | All past measurements |
| 6 | Progress graphs for measurements | P1 | Line chart with goal line |
| 7 | Measurement comments | P2 | Per-entry notes |

### 2.6 Workout Tools

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 1 | 1RM Calculator | P1 | Given weight × reps, estimate 1RM |
| 2 | Set Calculator | P2 | % of 1RM → working weight |
| 3 | Plate Calculator | P2 | Which plates to load on barbell |
| 4 | Rest timer (dedicated screen) | P1 | |

### 2.7 Exercise Library

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 1 | Built-in exercises by category | P0 | Pre-populated on first launch |
| 2 | Add custom exercises | P0 | Name, category, type, notes |
| 3 | Edit exercises | P0 | |
| 4 | Delete exercises | P0 | With confirmation (irreversible) |
| 5 | Exercise notes | P1 | Tips, form cues, equipment |
| 6 | Default rest time per exercise | P2 | |
| 7 | Default weight increment per exercise | P2 | |
| 8 | Custom categories (muscle groups) | P0 | Add/edit/delete/reorder |
| 9 | Category colours | P1 | Colours for calendar dots and lists |
| 10 | Favorites | P1 | Star exercises for quick access |

### 2.8 Settings & Data

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| 1 | Light / Dark / System theme | P0 | Follow app-wide setting |
| 2 | Unit system (kg / lbs) | P0 | |
| 3 | Default weight increment | P1 | |
| 4 | Keep screen on during workout | P1 | |
| 5 | Auto-start rest timer | P2 | |
| 6 | Backup / restore data | P1 | Export/import JSON |
| 7 | Spreadsheet export (CSV) | P2 | For external analysis |
| 8 | Delete workout history | P2 | By date range or exercise |

---

## 3. Triennium Training Plan (First Major Feature)

> The user's primary goal: **plan, save, and monitor a 3-year (triennium) training cycle**

### 3.1 Concept

A **triennium** is a 3-year structured training plan often used in strength sports (powerlifting, weightlifting). It typically involves:

- **Year 1 — Accumulation / Hypertrophy:** Higher volume, moderate intensity
- **Year 2 — Intensification:** Lower volume, higher intensity
- **Year 3 — Peak / Competition Prep:** Very low volume, very high intensity

### 3.2 Required Features for Triennium Support

#### Phase 1 — Core Logging (Week 1-2)
- [ ] Exercise library with categories
- [ ] Create custom exercises
- [ ] Start a workout, log sets (weight × reps)
- [ ] Edit / delete sets
- [ ] View today's workout

#### Phase 2 — Routines & Planning (Week 3-4)
- [ ] Create routines with days/sections
- [ ] Predefined sets (with copy-previous)
- [ ] Log a routine workout
- [ ] Edit/copy/delete routines
- [ ] Mark sets complete

#### Phase 3 — History & Progress (Week 5-6)
- [ ] Calendar with month + list views
- [ ] Training history per exercise
- [ ] Personal records (estimated 1RM + actual)
- [ ] Progress graphs (1RM, volume, max weight)
- [ ] Statistics (by week/month/year)

#### Phase 4 — Advanced Tools (Week 7-8)
- [ ] Rest timer
- [ ] 1RM Calculator
- [ ] Supersets
- [ ] Body tracker integration
- [ ] Backup / restore
- [ ] CSV export

#### Phase 5 — Triennium-Specific Features (Week 9-10)
- [ ] Multi-year planning view (Year 1, 2, 3)
- [ ] Phase templates (accumulation, intensification, peak)
- [ ] Auto-progression suggestions (e.g. +2.5 kg / week)
- [ ] Deload week reminders
- [ ] Training max (TM) calculation based on 1RM %
- [ ] Periodization visualization (volume × intensity curve over 3 years)
- [ ] Cycle completion tracking (weeks completed vs planned)

---

## 4. Technical Architecture

### 4.1 Data Models

```
Exercise
├── id: String
├── name: String
├── categoryId: String (muscle group)
├── type: ExerciseType (weightReps | distanceTime | weightOnly | ...)
├── notes: String
├── isFavourite: bool
├── defaultRestTime: int (seconds)
└── weightIncrement: double

Workout
├── id: String
├── date: DateTime
├── startTime: DateTime?
├── endTime: DateTime?
├── comment: String?
├── exercises: List<ExerciseEntry>
└── isFromRoutine: bool

ExerciseEntry
├── exerciseId: String
├── orderIndex: int
├── supersetGroupId: String?
└── sets: List<Set>

Set
├── id: String
├── weight: double?
├── reps: int?
├── distance: double?
├── time: Duration?
├── isComplete: bool
├── comment: String?
└── orderIndex: int

Routine
├── id: String
├── name: String
├── notes: String
├── days: List<RoutineDay>
└── createdAt: DateTime

RoutineDay
├── id: String
├── name: String
├── orderIndex: int
└── exercises: List<RoutineExercise>

RoutineExercise
├── exerciseId: String
├── orderIndex: int
├── supersetGroupId: String?
└── predefinedSets: List<PredefinedSet>

PredefinedSet
├── id: String
├── weight: double? (null = copy previous)
├── reps: int?
├── distance: double?
├── time: Duration?
└── orderIndex: int

BodyMeasurement
├── id: String
├── measurementId: String (weight, bodyFat, waist, ...)
├── value: double
├── date: DateTime
└── comment: String?

MeasurementConfig
├── id: String
├── name: String
├── unit: String
├── goal: GoalType (increase | decrease | specificValue)
├── targetValue: double?
└── isEnabled: bool
```

### 4.2 Storage Layer

- **Current:** SharedPreferences (JSON serialization) — works for MVP
- **Near future:** Isar / Hive / Drift (SQLite) — for relational queries (history, stats, graphs)
- **Long term:** Consider syncing via a backend (optional)

### 4.3 Navigation Structure

```
Life Notes App
├── 📝 Notes (existing)
├── 🏋️ Workout (new)
│   ├── Home / Today's Workout
│   ├── Calendar (month + list views)
│   ├── Exercise Library
│   ├── Routines
│   ├── Progress (graphs, records, stats)
│   ├── Body Tracker
│   └── Workout Tools (1RM calc, plate calc, rest timer)
├── ⚙️ Settings (app-wide)
└── 📅 Dashboard (future)
```

### 4.4 Package Dependencies

```yaml
dependencies:
  # Current
  flutter_riverpod: ^2.6.1      # State management
  go_router: ^14.8.1            # Navigation
  isar: ^3.1.0+1                # Local database (or drift)
  isar_flutter_libs: ^3.1.0+1   # Isar native libs
  fl_chart: ^0.70.2             # Progress graphs
  intl: ^0.20.2                 # Already added
  uuid: ^4.5.1                  # Already added

dev_dependencies:
  isar_generator: ^3.1.0+1
  build_runner: ^2.4.14
```

---

## 5. Development Phases Summary

| Phase | Features | Est. Time |
|-------|----------|-----------|
| **P1 — Core** | Exercise library, workout logging, set CRUD | 2 weeks |
| **P2 — Routines** | Routine CRUD, predefined sets, log from routine | 2 weeks |
| **P3 — History** | Calendar, training history, PRs, graphs, stats | 2 weeks |
| **P4 — Tools** | Rest timer, 1RM calc, superscripts, body tracker, backup | 2 weeks |
| **P5 — Triennium** | Periodization planner, auto-progression, deload, 3-year view | 2 weeks |
| **P6 — Polish** | CSV export, sharing, settings, favorites, search improvements | 1 week |

**Total estimated time to complete all workout features: ~11 weeks**

---

## 6. Next Steps

1. ✅ Set up project structure (done — life_notes created)
2. Add state management (Riverpod or similar)
3. Build exercise library (models + CRUD)
4. Build workout session screen (training view)
5. Build routine system
6. Build calendar & history
7. Build progress graphs & analytics
8. Build triennium periodization planner

---

*Last updated: 2026-06-04*
