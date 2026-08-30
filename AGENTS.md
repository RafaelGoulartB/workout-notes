# AGENTS.md — Workout Notes

Use this file as a practical guide when changing the project. Prefer the code
near the feature you are editing when this document and the implementation
disagree.

## Project overview

Workout Notes is a local-first Flutter app for strength training, running,
sleep, nutrition, body measurements, goals, periodization, and progress.

Android is the most complete target. Background run tracking, sleep monitoring,
alarms, barcode scanning, and voice coaching depend on native Android services.
Keep shared Flutter code portable unless a feature is explicitly
platform-specific.

The main areas are:

- workout logging, exercises, routines, timers, history, goals, and charts;
- GPS running and stationary-bike sessions, plans, intervals, and coaching;
- sleep tracking and alarms;
- nutrition diary, foods, saved meals, and targets;
- periodization plans and check-ins;
- an optional AI Coach connected to user-configured providers.

The UI uses Material 3, light/dark themes, and a configurable accent color.

## Architecture

The project deliberately uses lightweight state management:

- `setState` for state owned by one screen or widget;
- `ChangeNotifier` for shared settings, coordinators, and long-lived services;
- repositories for SQLite access and domain queries.

Do not add Riverpod, Bloc, or another state-management package without a clear
need that the current patterns cannot handle.

Important directories:

```text
lib/
├── database/       Database creation, migrations, and seed data
├── dev_tools/      Debug-only helpers and test data
├── l10n/           ARB sources and generated AppLocalizations
├── models/         Typed domain models
├── navigation/     Cross-feature navigation helpers
├── periodization/  Reusable plan logic without widget state
├── repositories/   SQLite access grouped by domain
├── screens/        Screens grouped by feature
├── services/       Timers, notifications, exports, tracking, and AI logic
├── state/          Shared ChangeNotifier coordinators
├── utils/          Formatting, calculations, and other pure helpers
└── widgets/        Reusable UI components

android/app/src/main/kotlin/.../run, sleep   Native foreground services and bridges
android/app/src/test/                         Kotlin unit tests (./gradlew test)
test/support/                                 Shared test DB setup (ai_test_db.dart)
tool/                                         Standalone Dart scripts (sleep validation, run plan catalog)
```

Keep business logic out of large widgets when it can live in a controller,
repository, service, or pure helper. Follow the split already used by the
feature instead of introducing a new architecture.

## Code conventions

- Follow `analysis_options.yaml` and the surrounding Dart style.
- Use `const` constructors and `final` values when they fit.
- Prefer named parameters for APIs with several arguments.
- Use `package:workout_notes/...` imports across top-level `lib/` directories.
- Do not use a `BuildContext` after an async gap without checking `mounted` or
  `context.mounted`.
- Keep visible text out of widgets. Add it to both `lib/l10n/app_en.arb` and
  `lib/l10n/app_pt.arb`.
- Do not edit generated `app_localizations*.dart` files. Run
  `flutter gen-l10n` after changing ARBs.
- Store database date values in the format already used by that domain. Format
  dates shown to the user with the active locale.
- Use parameterized SQLite queries. Never insert user input into SQL strings.
- Show useful UI feedback when an action can fail or cannot be completed.

Avoid unrelated cleanup in a focused change. Preserve existing user changes in
the working tree.

## Database and repositories

`DatabaseHelper.instance` owns the SQLite connection and exposes the domain
repositories. New data access should normally go in the relevant repository.
Some delegation methods remain on `DatabaseHelper` for compatibility; do not
expand that compatibility layer without a reason.

The database source of truth is split across:

- `lib/database/database_helper.dart` for the database version and connection;
- `lib/database/database_schema.dart` for creation and migration coordination;
- `lib/database/database_*_schema.dart` for specialized schemas;
- `lib/database/migrations/` for incremental upgrades;
- `lib/database/database_seed.dart` and `lib/database/seed_data.dart` for seed
  data.

When changing the schema:

1. Update fresh database creation.
2. Add an incremental migration for existing databases.
3. Increase `_dbVersion` in `database_helper.dart`.
4. Keep foreign keys and indexes consistent.
5. Add a `test/database_migration_vNN_test.dart` covering both a fresh
   database and the upgrade path.
6. Mirror the table in `test/support/ai_test_db.dart` if AI tools read it.

Migrations are additive `CREATE TABLE IF NOT EXISTS` / `ALTER TABLE` blocks
wrapped in try/catch so they are idempotent. For a destructive change, create a
replacement table, copy the data, validate the result, and only then replace
the old table. Code that reads newer tables should guard with an existence
check (see `_tableExists` in `export_import_repository.dart`) because older
devices may still be on an older schema.

Tables use client-generated UUID v4 primary keys and `ON DELETE CASCADE`
foreign keys.

Tests that need SQLite should use `sqflite_common_ffi` with an in-memory
database installed via `DatabaseHelper.overrideDatabase` (set in `setUp`,
cleared in `tearDown`); do not open the application database from tests.

## Navigation, theme, and settings

`lib/screens/main_shell.dart` owns the main `NavigationBar` and lazily builds
its tab contents in an `IndexedStack`. Section visibility is managed by
`SectionsNotifier`. Preserve tab state when changing the shell.

Screen-to-screen flows normally use `Navigator` and `MaterialPageRoute`.
Shared or cross-feature flows may use helpers under `lib/navigation/`.

Theme and locale state are initialized in `lib/main.dart`. Accent color, theme
mode, locale, and feature preferences use the existing notifier and persistence
paths. Do not create a second source of truth for a setting.

The supported locales are English and Brazilian Portuguese. Any user-visible
change must work in both.

## Android-native services

Run tracking, sleep monitoring, alarms, run voice, and barcode scanning have
Kotlin counterparts under `android/app/src/main/kotlin/.../` that keep working
while the Flutter engine is closed. Dart talks to them through
`MethodChannel`/`EventChannel` facades in `lib/services/` (for example
`RunTrackingService`, `SleepMonitorService`, `TraditionalAlarmService`).

Rules for these facades:

- guard every call with `!kIsWeb && defaultTargetPlatform == TargetPlatform.android`
  and return safe defaults (`supported: false`) elsewhere, including on
  `MissingPluginException` — tests run on desktop where the channels do not
  exist;
- treat the `EventChannel` as a live UI signal only. Durable data flows through
  the native spool/snapshot and is imported into SQLite when the app opens
  (sleep: `SleepMonitorRepository.importNativeSpool`; alarms:
  `TraditionalAlarmService.reconcile`). SQLite is the source of truth; keep
  that one-way flow intact;
- native code extracts aggregates and drives hardware; labelling and inference
  stay in Dart.

Kotlin unit tests live in `android/app/src/test/` and run with
`cd android && ./gradlew test`.

## Feature-specific rules

### Active workout

The active workout flow is intentionally split:

- `active_workout_screen.dart` contains the UI;
- `active_workout_controller.dart` contains session logic;
- `active_workout_routine_actions.dart` contains routine-related actions.

Place new behavior in the appropriate file instead of growing the screen.

Use `EmptyStatePlaceholder` for standard empty states and reuse existing
feature widgets before creating another variant.

### Periodization

`lib/periodization/` contains reusable plan logic used by both the standalone
editor and the plan wizard. Keep this code independent of `BuildContext` and
local widget `setState`. UI belongs under `screens/` or `widgets/`.

### AI Coach

The AI Coach supports user-configured OpenAI-compatible providers. Provider
tokens live in `flutter_secure_storage`; provider settings and conversations
use the existing persistence code.

The main sources of truth are:

- `lib/services/ai_service.dart` for provider HTTP calls;
- `lib/services/ai_tool_registry.dart` and the domain tool services for tools;
- `lib/services/ai_context_service.dart` for injected local context;
- `lib/state/ai_chat_*.dart` for chat orchestration and persistence;
- `lib/state/ai_settings_notifier.dart` for provider settings;
- `lib/widgets/ai/` and the AI screens for presentation.

Preserve these safety rules:

- read tools may run directly;
- routine and manual-food changes must be proposals reviewed in the app;
- never let an AI response write domain data without explicit user approval;
- revalidate proposal state before applying it in a transaction;
- keep provider credentials out of SQLite, logs, prompts, and backups;
- do not add streaming or token/cost tracking unless the feature is requested.

Deliberate wire decisions in `ai_chat_wire.dart` — do not undo without a
feature request:

- the full tool catalog is sent every round; `toolNamesForQuery` only adds a
  hint line, never filters. Per-round pruning and discovery meta-tools were
  removed because they cost round trips and break prompt caching;
- message 1 is a static prefix identical across turns; everything per-turn
  (data snapshot, thread summary, tool hints) goes in the single dynamic block
  after it;
- tool results are truncated on the wire only; the persisted message keeps the
  full payload for the UI.

Treat the registry as the source of truth for tool names and schemas. When
adding or changing a tool, update its execution, schema, user-facing label, and
tests together. Do not copy a fixed tool count into documentation.

`TextSanitizer` removes only the known reasoning-block and citation-placeholder
artifacts. Do not broaden sanitization without a concrete failing case and a
test; broad cleanup can corrupt legitimate user content.

## Testing and validation

Keep tests close to the behavior being changed:

- repository and migration tests for persistence changes;
- unit tests for services, parsers, calculations, and resolvers;
- widget tests for rendering and interaction behavior;
- localization tests for visible strings;
- `SharedPreferences.setMockInitialValues` for preference-dependent tests.

Inject fakes through the existing `overrideForTest(...)` / `overrideDatabase`
hooks instead of reaching into private state.

Run the smallest relevant test first, then validate the wider project when the
change warrants it:

```bash
flutter gen-l10n
dart format path/to/changed_file.dart
flutter analyze
flutter test test/<file>_test.dart --name "pattern"
flutter test
```

CI (`.github/workflows/release-android.yml`) runs `flutter analyze` and
`flutter test`, then builds a signed APK on pushes to `main`. A failing test
blocks the release.

Useful build commands:

```bash
flutter pub get
flutter run
flutter build apk --release
```

Do not claim validation that was not run. If a full test or build is skipped,
state which narrower checks were completed.

## Before finishing a change

- Confirm that the implementation follows the existing feature boundary.
- Check async `BuildContext` use and user-facing error feedback.
- Add both English and Portuguese strings when UI text changes.
- Add or update tests for changed behavior.
- For schema changes, verify fresh creation and migration.
- Run formatting, analysis, and the relevant tests.
- Review the diff for unrelated edits, generated files, secrets, and debug code.
