# AGENTS.md — Life Notes

A comprehensive guide for LLM agents working on the Life Notes project. This document captures the project's architecture, conventions, design decisions, and common patterns to help agents produce correct, maintainable code.

---

## 1. Project Overview

**Life Notes** is a Flutter mobile application that combines a personal journal with a workout tracker. It supports Android, iOS, web, and desktop (Linux, macOS, Windows).

- **Journal module:** Write, edit, browse, and delete personal notes. Persisted via `shared_preferences` (local JSON).
- **Workout tracker module:** Exercise library, workout logging, set tracking, routines, body measurements, progress charts, calendar, rest timer, CSV export. All persisted via **SQLite** (`sqflite`).

The app uses Material 3 with dynamic theming, automatic dark mode support, and customizable accent colors.

---

## 2. Tech Stack

| Layer | Choice |
|---|---|
| Language | Dart 3.12+ |
| UI Framework | Flutter (Material 3) |
| State Management | `setState` + `ChangeNotifier` (lightweight) |
| Notes Storage | `shared_preferences` (JSON string) |
| Workout Storage | `sqflite` (SQLite) |
| Charts | `fl_chart` |
| Animations | `flutter_animate` |
| Export | `share_plus`, `csv` |
| UUID | `uuid` |
| Date/Time | `intl` (locale: `pt_BR`) |

---

## 3. Directory Structure

```
lib/
├── main.dart                          # App entry, theme, navigation shell
├── models/
│   └── note.dart                      # Note data model
├── database/
│   ├── database_helper.dart           # SQLite singleton (all workout tables)
│   ├── seed_data.dart                 # Default exercise categories & exercises
│   └── test_seed_data.dart            # Sample workout data for development
├── services/
│   ├── storage_service.dart           # Notes CRUD via shared_preferences
│   ├── export_service.dart            # CSV data export
│   └── rest_timer_service.dart        # Rest timer logic
├── screens/
│   ├── home_screen.dart               # Notes list view
│   ├── note_editor_screen.dart        # Note create/edit screen
│   └── workout/
│       ├── workout_home_screen.dart   # Workout module dashboard
│       ├── active_workout_screen.dart # Live workout session (largest file)
│       ├── workout_detail_screen.dart # Past workout review
│       ├── exercise_library_screen.dart
│       ├── exercise_form_screen.dart
│       ├── routines_screen.dart
│       ├── calendar_screen.dart
│       ├── progress_screen.dart
│       ├── body_tracker_screen.dart
│       ├── settings_screen.dart
│       ├── export_screen.dart
│       ├── quick_add_screen.dart
│       └── rest_timer_screen.dart
└── widgets/
    ├── empty_state_placeholder.dart   # Reusable empty-state widget
    └── exercise_picker_sheet.dart     # Bottom sheet for picking exercises
```

---

## 4. Architecture & Design Decisions

### 4.1 State Management

The project intentionally avoids heavy state management libraries (Riverpod, Bloc, etc.). It uses:

- **`setState`** — For local, per-screen state.
- **`ChangeNotifier`** — For app-wide concerns like accent color changes (`ThemeNotifier` in `main.dart`).
- **Direct database reads** — Most screens query SQLite directly and rebuild with `setState`.

**Rule:** Do not introduce a state management library unless the pattern clearly proves insufficient.

### 4.2 Database Architecture

**Notes** are stored in `shared_preferences` as a single JSON string (`life_notes` key). The `Note` model is self-contained with `toJson`/`fromJson`.

**Workout data** uses SQLite via `sqflite` with the following relational schema:

```
exercise_categories (1) ──→ (N) exercises (1) ──→ (N) exercise_entries (1) ──→ (N) sets
                                │
routines (1) ──→ (N) routine_days (1) ──→ (N) routine_exercises (1) ──→ (N) predefined_sets
                                │
workouts (1) ──→ (N) exercise_entries (1) ──→ (N) sets
                                │
body_measurements (standalone)
app_settings (key-value)
```

Key points:
- `DatabaseHelper` is a **singleton** accessed via `DatabaseHelper.instance`.
- All tables use UUID v4 primary keys generated client-side.
- Foreign keys use `ON DELETE CASCADE`.
- The database is created and seeded in `_onCreate`. Upgrades are handled in `_onUpgrade` with incremental `ALTER TABLE` statements wrapped in try-catch for idempotency.

### 4.3 Theme System

- Accent color is persisted in `shared_preferences` as `accent_color` (int).
- `ThemeNotifier` is a static `ChangeNotifier` on `LifeNotesApp.themeNotifier`.
- Both light and dark themes are built from the same seed color using `ColorScheme.fromSeed`.
- Theme mode follows the system (`ThemeMode.system`).

### 4.4 Navigation

- A `MainShell` widget holds an `IndexedStack` with two tabs: `HomeScreen` (notes) and `WorkoutHomeScreen`.
- Bottom `NavigationBar` (Material 3 style) switches between them.
- Screen-to-screen navigation uses `Navigator.push` with `MaterialPageRoute`.

### 4.5 Locale

- The app uses **`pt_BR`** for date formatting (Brazilian Portuguese).
- `initializeDateFormatting('pt_BR', null)` is called before `runApp`.

---

## 5. Coding Conventions

### 5.1 General Dart/Flutter

- **Use `const` constructors** wherever possible.
- **Use `final`** for variables that are only assigned once.
- **Prefer named parameters** with `required` where appropriate.
- **Import style:** Prefer `package:` imports over relative imports within `lib/`.
- **Do not use `BuildContext` across async gaps** — always check `mounted` before calling `setState` after `await`.

### 5.2 File Organization

- One class per file, named after the class (snake_case filename).
- Screens live in `screens/`, grouped by module.
- Reusable widgets live in `widgets/`.
- Database-related code goes in `database/`, services in `services/`, models in `models/`.

### 5.3 Naming

- **Files:** `snake_case.dart`
- **Classes:** `PascalCase`
- **Functions/variables:** `camelCase`
- **Private members:** prefix with `_`
- **Database columns:** `snake_case`
- **Database tables:** `snake_case`, plural

### 5.4 Database Access Pattern

```dart
final db = await DatabaseHelper.instance.database;
final results = await db.query('table_name', where: 'col = ?', whereArgs: [value]);
```

Always use parameterized queries (`?` placeholders) to prevent SQL injection. Never concatenate user input into SQL strings.

### 5.5 Error Handling

- Database operations use try-catch sparingly; most failures propagate as unhandled exceptions.
- `_onUpgrade` wraps `ALTER TABLE` in try-catch to handle cases where columns already exist.
- When adding new UI flows, provide user feedback via `SnackBar` or `ScaffoldMessenger`.

---

## 6. Key Data Models

### Note

```dart
class Note {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  // preview getter, copyWith, toJson/fromJson, ==, hashCode, toString
}
```

### SQLite Tables (Workout Module)

| Table | Key Columns |
|---|---|
| `exercise_categories` | `id`, `name`, `color` (int), `order_index`, `energy_system` |
| `exercises` | `id`, `name`, `category_id` (FK), `type`, `notes`, `equipment`, `is_favorite`, `default_rest_time`, `weight_increment` |
| `workouts` | `id`, `date`, `start_time`, `end_time`, `duration_seconds`, `comment`, `feeling_rating`, `is_from_routine`, `routine_id` |
| `exercise_entries` | `id`, `workout_id` (FK), `exercise_id` (FK), `order_index`, `superset_group_id`, `notes`, `rest_time_seconds` |
| `sets` | `id`, `exercise_entry_id` (FK), `weight`, `reps`, `distance`, `time_seconds`, `is_complete`, `is_warmup`, `rpe`, `comment`, `order_index` |
| `routines` | `id`, `name`, `notes`, `created_at` |
| `routine_days` | `id`, `routine_id` (FK), `name`, `order_index` |
| `routine_exercises` | `id`, `routine_day_id` (FK), `exercise_id` (FK), `order_index`, `superset_group_id`, `rest_time_seconds` |
| `predefined_sets` | `id`, `routine_exercise_id` (FK), `weight`, `reps`, `distance`, `time_seconds`, `is_warmup`, `order_index` |
| `body_measurements` | `id`, `type`, `value`, `unit`, `date`, `comment`, `created_at` |
| `app_settings` | `key` (PK), `value` |

---

## 7. Testing Strategy

- Tests are in `test/` directory.
- Currently only `widget_test.dart` exists (skeleton).
- When adding tests:
  - Use `flutter_test` for widget tests.
  - Use `sqflite_common_ffi` for database unit tests (in-memory SQLite).
  - Use `SharedPreferences.setMockInitialValues` for notes storage tests.
- Coverage priority: database operations > screen rendering > service logic.

---

## 8. Common Operations Guide

### 8.1 Adding a New Feature (Workout Module)

1. Define any new SQLite table in `_onCreate` in `database_helper.dart`.
2. Add `ALTER TABLE` migration in `_onUpgrade` and bump `_dbVersion`.
3. Add CRUD methods to `DatabaseHelper`.
4. Create the screen under `screens/workout/`.
5. Wire it into navigation from the appropriate parent screen.

### 8.2 Adding a New Screen

1. Create the file in the appropriate `screens/` subdirectory.
2. Use `StatefulWidget` unless the screen is purely presentational.
3. Query data in `initState` or `didChangeDependencies` and store in local state.
4. Rebuild via `setState` after async database operations.

### 8.3 Changing the Database Schema

1. Increment `_dbVersion` in `DatabaseHelper`.
2. Add migration logic to `_onUpgrade` — prefer `ALTER TABLE` for additive changes.
3. If the change is destructive (e.g., column removal), write a migration that creates a new table, copies data, drops the old, and renames.
4. Test on a device with existing data before merging.

### 8.4 Adding a New Chart

`progress_screen.dart` and `workout_home_screen.dart` use `fl_chart`. Patterns to follow:

- Use `BarChart` or `LineChart` from `fl_chart`.
- Query aggregated data via `DatabaseHelper` (e.g., `getMonthlyVolume`, `getWeeklyVolume`).
- Use `flutter_animate` for chart entry animations.

### 8.5 Adding a New Setting

1. Add a default in `_seedData` (app_settings table).
2. Add a getter/setter in `DatabaseHelper` (`getSetting`/`setSetting`).
3. Add the UI control in `settings_screen.dart`.

---

## 9. Important Gotchas & Rules

1. **Database instance:** Always use `DatabaseHelper.instance.database`. Do **not** create a new `DatabaseHelper()`.
2. **setState after async:** Always check `mounted` before calling `setState` in an async callback.
3. **Locale:** The app uses `pt_BR`. Date strings are in `yyyy-MM-dd` format. `DateTime.toIso8601String().substring(0, 10)` is the standard way to get a date string.
4. **Theme changes:** When reading/changing accent color, use `LifeNotesApp.themeNotifier` and persist to `SharedPreferences`.
5. **Workout timer:** The timer in `active_workout_screen.dart` is managed client-side; `startWorkoutTimer`/`stopWorkoutTimer`/`resetWorkoutTimer` in `DatabaseHelper` handle persistence.
6. **File sizes:** `active_workout_screen.dart` (~1.6K lines) is the largest file. Consider splitting if new functionality is added.
7. **Empty states:** Use `EmptyStatePlaceholder` widget for consistent empty-state UI across screens.
8. **Don't use relative imports across top-level directories.** Use `package:life_notes/...` imports.
9. **Seed data** lives in `seed_data.dart` — categorized by `energy_system` (aerobic/anaerobic). The `test_seed_data.dart` file generates sample workouts for development testing.

---

## 10. Build & Run

```bash
flutter pub get
flutter run                    # Run on connected device
flutter test                   # Run tests
flutter build apk --release    # Android release
flutter build ios --release    # iOS release
flutter analyze                # Static analysis
```

---

## 11. Dependencies (pubspec.yaml)

| Package | Version | Purpose |
|---|---|---|
| `flutter` | SDK | Framework |
| `cupertino_icons` | ^1.0.8 | iOS icons |
| `uuid` | ^4.5.1 | UUID generation |
| `intl` | ^0.20.2 | Date formatting |
| `shared_preferences` | ^2.3.4 | Notes & settings storage |
| `sqflite` | ^2.4.2 | Workout database |
| `path` | ^1.9.1 | Path utilities for DB |
| `path_provider` | ^2.1.5 | File system paths |
| `fl_chart` | ^0.70.2 | Progress charts |
| `flutter_animate` | ^4.5.2 | Animations |
| `share_plus` | ^10.1.4 | File sharing/export |
| `csv` | ^6.0.0 | CSV generation |

---

## 12. Decision Log

| Decision | Rationale |
|---|---|
| SharedPreferences for notes, SQLite for workouts | Notes are simple key-value data; workouts need relational queries (JOINs, aggregates, history). |
| `setState` over state management libs | The app's complexity doesn't warrant the overhead. Each screen is relatively self-contained. |
| UUID v4 as primary keys | Offline-first friendly; no auto-increment conflicts. |
| `pt_BR` locale | The primary user is Brazilian Portuguese speaking. |
| Material 3 with seed colors | Provides a polished, adaptive look with minimal theming code. |
| Single `DatabaseHelper` singleton | Avoids multiple connections and ensures migrations run once. |
