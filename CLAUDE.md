# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) and other coding agents working in this repository. It is the single source of truth for project conventions; `AGENTS.md` only points here. When this file and the code disagree, trust the code.

## Overview

Workout Notes is a **local-first, Android-only Flutter app** for logging workouts, runs, routines, goals, body measurements, sleep, nutrition, alarms and medication reminders. There are no iOS, web or desktop targets; the `defaultTargetPlatform == android` guards remain only because the Dart tests run on the desktop VM. All data lives on-device: workouts in SQLite (`sqflite`), AI provider tokens in `flutter_secure_storage`, settings in SQLite + `shared_preferences`. There is no backend. The optional AI Coach talks to a user-configured OpenAI-compatible endpoint.

Heavier modules (run tracking and voice, sleep monitoring, alarms, medication reminders, barcode scanning) have real **Android-native (Kotlin) counterparts** that keep running while the Flutter engine is closed, bridged over MethodChannel/EventChannel.

## Commands

```bash
flutter pub get                        # Install dependencies
flutter gen-l10n                       # Regenerate AppLocalizations from ARB files (required after editing ARB)
flutter analyze                        # Static analysis (lints: flutter_lints)
flutter test                           # Run all Dart tests
flutter test test/<file>_test.dart     # Run a single test file
flutter test test/<file>_test.dart --name "pattern"   # Run matching tests
flutter run                            # Run on connected device/emulator
flutter build apk --release            # Build signed Android APK
```

Android-native (Kotlin) unit tests live in `android/app/src/test/`:

```bash
cd android && ./gradlew test            # Run all Kotlin tests
cd android && ./gradlew test --tests "*SleepSessionSpoolTest"   # Single class
```

Standalone scripts live in `tool/` (outside `test/`, so `flutter test` never runs them):

```bash
flutter test tool/benchmark/long_term_storage_study.dart   # manual ~45 min storage/backup benchmark
flutter test tool/generate_run_plan_catalog.dart           # writes docs/run-plan-catalog.html
dart run tool/replay_sleep.dart diagnostic.json [labels.json]   # replay an exported sleep diagnostic
```

## CI

- `.github/workflows/validate.yml` (PRs and pushes touching `lib/`, `test/`, `tool/`, `android/`, `pubspec*`, `l10n.yaml`, `analysis_options.yaml`, workflows): `flutter gen-l10n`, `flutter analyze`, `flutter test`, and `./gradlew :app:testDebugUnitTest` with a pinned Flutter version.
- `.github/workflows/release-android.yml` (pushes to `main` touching app code): `flutter analyze` + `flutter test`, then builds and publishes a signed APK. A failing test blocks the release.
- The generated `lib/l10n/app_localizations*.dart` files are **not committed** (gitignored); `flutter pub get` / `flutter gen-l10n` regenerate them.

## Architecture

### Layout

```text
lib/
├── database/       Schema creation, migrations (database/migrations/), seed data
├── dev_tools/      Debug-only helpers (run simulator, generated test data)
├── l10n/           ARB sources (generated AppLocalizations is gitignored)
├── models/         Typed domain models
├── periodization/  Plan logic without widget state (shared by editor and wizard)
├── repositories/   All SQL, grouped by domain
├── screens/        Screens grouped by feature (run/, strength/, workout/ ...)
├── services/       Timers, notifications, exports, tracking, AI logic
├── state/          Shared ChangeNotifier coordinators (AI chat, AI settings, sections)
├── utils/          Pure helpers (formatting, calculations)
└── widgets/        Reusable UI; shared UI components live in lib/widgets/ui/ (App*)
android/app/src/main/kotlin/.../{run,sleep,medication,...}   Native services and bridges
android/app/src/test/                                        Kotlin unit tests
test/support/                                                Shared test DB and fixtures
tool/                                                        Standalone scripts and benchmarks
```

Keep business logic out of large widgets when it can live in a controller, repository, service or pure helper, and follow the split the feature already uses (for example the active workout is `active_workout_screen.dart` + `active_workout_controller.dart` + `active_workout_routine_actions.dart`).

### State management
Deliberately lightweight — no Riverpod/Bloc. Per-screen `setState` for local state; **`ChangeNotifier` singletons** for cross-cutting services. Singletons follow the pattern `ClassName.instance` (static final) or a static field on `WorkoutNotesApp` (e.g. `WorkoutNotesApp.themeNotifier`, `.aiSettings`, `.sections`). Screens consume them via `ListenableBuilder`/`addListener`. Don't introduce a state-management library unless this pattern clearly fails.

Navigation uses plain `Navigator` + `MaterialPageRoute`. `lib/screens/main_shell.dart` owns the bottom `NavigationBar` and builds tab contents lazily in an `IndexedStack` (preserve tab state); `SectionsNotifier` controls which sections are visible. Theme, accent colour and locale are initialised in `lib/main.dart`; do not create a second source of truth for a setting.

### Shared helpers
Use these instead of re-implementing them:
- `lib/utils/date_utils.dart`: `dayOf`, `addDays`, `mondayOf`, `sundayOf`, `isSameDay`, `monthKey` and `dateKey` (`yyyy-MM-dd`). They are DST-safe (they add days through the `DateTime(y, m, d + n)` constructor, never a 24 h `Duration`). Use `dateKey(date)` for stored date strings, not `toIso8601String().substring(0, 10)`.
- `lib/utils/duration_format.dart` (`DurationFormat`: `minSec`, `mmss`, `hms`, `clock`, `hhmm`, `twoDigits`, ...) and `RunFormatters` (`lib/utils/run_formatters.dart`, locale-aware decimals, pace and distance; it delegates its clock formats to `DurationFormat`). Never hand-roll `padLeft(2, '0')` durations.
- Shared UI components in `lib/widgets/ui/` (`App*` widgets); reuse them before creating another card, divider, banner, empty state or confirm dialog.
- Visible text never goes in widgets — see Localization.

### Database & repositories
`DatabaseHelper` (`lib/database/database_helper.dart`) is a **singleton** — always `DatabaseHelper.instance.database`, never `new DatabaseHelper()`. Current schema version is `_dbVersion = 57`. It holds `late final` lazy repository instances (`.settingsRepo`, `.workoutRepo`, `.runRepo`, `.sleepMonitorRepo`, `.traditionalAlarmRepo`, etc.) and **no compatibility delegators**: call `DatabaseHelper.instance.xxxRepo.method(...)` (or accept an injectable repository in the constructor and default to that instance) — never construct `XxxRepository()` ad hoc in app code.

Each domain has a repository in `lib/repositories/` extending `BaseRepository` (which exposes `db`). Repositories own all SQL — screens query repos, never raw SQL directly. Tables use UUID v4 client-generated PKs and `ON DELETE CASCADE` FKs. Always parameterize queries (`?` placeholders) — never concatenate input into SQL. Date columns hold `yyyy-MM-dd`; **run timestamps are stored as local wall-clock ISO strings without an offset** (v57 rewrote old UTC `...Z` values via `DatabaseMigrations.normalizeRunTimestamps`), so day attribution can rely on `yyyy-MM-dd` prefixes.

**Schema changes:** bump `_dbVersion`, add to `DatabaseSchema.onCreate` (`lib/database/database_schema.dart` and the `database_*_schema.dart` files, new installs) *and* add a `step(N)` block to `DatabaseMigrations.upgrade` in `lib/database/migrations/database_migrations.dart` (existing installs). **v37 is the migration floor** (`DatabaseMigrations.floorVersion`): a database older than that is dropped and recreated, and no code for earlier versions is kept. Migration statements run through `DatabaseMigrations.tryExecute`, which swallows only "duplicate column" / "already exists" errors so upgrades are idempotent and any other failure aborts the upgrade; use additive `CREATE TABLE IF NOT EXISTS` / `ALTER TABLE`, and for destructive changes create a replacement table, copy, validate, then swap. Repositories may assume every table and column of the current schema exists — do not add `sqlite_master` / `PRAGMA table_info` guards. Extend `test/database_migrations_test.dart` (it upgrades the captured v37 schema in `test/support/schema_v37_fixture.dart` and compares the result with a fresh install).

### Sleep monitoring (Android-native)
The sleep monitor is a **Kotlin foreground service** (`android/.../sleep/SleepMonitoringService.kt`) that records mic audio into segments while the app is closed. Dart talks to it through `SleepMonitorService` (`lib/services/sleep_monitor_service.dart`), a `ChangeNotifier` facade over a MethodChannel (`workout_notes/sleep_monitor/methods`) + EventChannel (`.../events`). Native bridge: `SleepMonitorBridge.kt`.

The important architectural rule: **the EventChannel is only a live UI signal; durable data flows through the native spool.** The native service appends segments to a JSON spool (`SleepSessionSpool.kt`). When the app opens, `SleepMonitorService.recoverPendingSessions()` lists pending spools (`listPendingSessions`), imports each via `SleepMonitorRepository.importNativeSpool(...)` (atomic SQLite transaction, idempotent per session, merges into the daily `sleep_entries` row without creating duplicates), then `deleteSpool`. A failed SQLite commit leaves the spool intact for retry. Keep this one-way spool→Dart flow intact.

Staging is done by **`SleepWakeEngine` only** (`lib/services/sleep_wake_engine.dart`). It runs on import for bedside `audio-features-v3` / `audio-features-v4` nights (`SleepWakeEngine.supports`), labels windows awake / sleeping / deep from the audio aggregates, and `SleepStageAnalysisService` summarizes the epochs into onset/wake, stage minutes, awakenings and efficiency, which are stored on `sleep_monitor_sessions` (there is no per-epoch table). Older recordings keep the `legacy_unavailable` status and get no staging. The live UI uses the same engine through the causal `SleepWakeCursor`. The native side (`SpectralAnalyzer`, `BreathingAnalyzer`, `AudioSignalProcessor`) only extracts privacy-preserving per-window aggregates — it never labels. `tool/replay_sleep.dart` replays an exported diagnostic through the engine.

All `SleepMonitorService` methods guard with `defaultTargetPlatform == TargetPlatform.android` and return safe defaults (e.g. `supported: false`) on other platforms / `MissingPluginException`. Preserve that pattern — tests run on desktop where the channels don't exist. The same applies to every other native facade (`RunTrackingService`, `TraditionalAlarmService`, `RunNativeVoiceService`, ...); the `EventChannel` is a live signal only and SQLite is the source of truth.

### Run tracking and voice
`RunTrackingService` (Dart facade) and the Kotlin `RunTrackingService`/`RunTrackingBridge` record GPS runs in a foreground service; indoor sessions (stationary bike, treadmill) use the Dart-only `IndoorTrackingService` timer. The native side persists points and checkpoints to a run spool; after stopping, Dart reads the completed spool for the review screen and only imports it into SQLite when the user saves (same one-way spool flow as sleep). **All run-spool disk I/O (appends, checkpoints, reads, deletes) goes through `RunSpoolExecutor`**, a single-thread executor shared process-wide, so GPS callbacks and channel calls never block on file I/O and reads observe earlier writes.

Voice coaching is **native-only**: the `RunVoiceController` inside the tracking foreground service speaks the cues (there is no Dart TTS and no `flutter_tts`). Dart's `RunNativeVoiceService` (`lib/services/run_native_voice_service.dart`) pushes settings, goal and plan and requests one-shot announcements (the settings screen's test cue), and `RunSessionCoach` holds the session set-up (voice settings, goal, planned workout, interval toggle) for the record screen.

### Traditional alarms
`TraditionalAlarmService` (`lib/services/traditional_alarm_service.dart`) persists alarm definitions in SQLite (`TraditionalAlarmRepository`) and **mirrors the runnable snapshot to Android** (native side owns ringing/repeat while app is closed). `reconcile()` on startup pulls native schedules (`states`) back into the DB, then schedules DB alarms that lack a native snapshot. SQLite is the source of truth; native scheduling is best-effort (`_scheduleBestEffort`) so a transient channel failure never blocks the editor — `reconcile` fixes it next launch. Global snooze defaults are stored as `app_settings` rows (`alarm_global_max_snoozes`, `alarm_global_snooze_enabled`).

### Medication reminders
Medications live in SQLite (`medications`, with the confirmed/skipped log in `medication_doses`, v55) and are edited in the "Medications" tab of `TraditionalAlarmsScreen`. `MedicationReminderService` mirrors **one native slot per medication time** (`<medicationId>@HHmm`) to Android over `workout_notes/medication/methods`. The native side (`android/.../medication/`) owns the runtime while the app is closed: at the dose time `MedicationReminderReceiver` posts a notification whose tap opens `MedicationConfirmActivity` ("taken" / "skip"); if nothing is confirmed within the medication's `escalation_minutes`, an alarm-clock escalation starts `MedicationAlarmService` (sound + vibration + full-screen confirmation) until the dose is answered. Pure rules (next occurrence, dose keys `yyyy-MM-ddTHH:mm` built identically on both sides, when to escalate) are in `MedicationReminderPolicy`. Confirmations made natively go to a spool that `reconcile()` imports into `medication_doses` and then acks — the same one-way flow as the sleep spool; confirmations made in the app call `confirm` natively so the reminder/alarm for that dose is silenced. `reconcile()` also schedules every enabled slot and cancels native slots that no longer exist. Boot/update restore runs through `SleepAlarmBootReceiver`.

### Running plans
`RunPlanComposer` (`lib/services/run_plan_composer.dart`) turns a catalog template (`RunPlanTemplates`) plus the wizard's `RunPlanBuildConfig` into weeks of sessions; session names/notes come from `RunPlanText` in the plan's language. Plans store their `template_key` and `config_json` (v52) so they can be **re-planned**: `RunPlanCoach` reviews the previous week (km run vs planned, RPE, test/interval results, GPS best efforts), `RunPlanAdaptationEngine` (pure) proposes hold / step back / rebuild and a pace change, and applying it re-composes the remaining weeks via `RunPlanBuildConfig.remainingWeeks` + `RunPlanRepository.replaceWeeksFrom` (history weeks are never rewritten). Proposals are never auto-applied — one apply/dismiss per plan week, logged in `run_plan_adaptations`. Goal plans end after their last week (`RunPlan.isFinishedOn`); only one-week/maintenance plans wrap. Moves go through `RunWeekBalance` (no two runs a day, no hard days back to back); runner strength days come from `RunStrengthPlanner` and the `RunnerStrengthRoutine` routine.

### Planning (periodization)
`lib/periodization/` holds the reusable plan logic (independent of `BuildContext` and widget state). The Progress tab (`PeriodizationHomeScreen`) is the planning home: body weight, then the active plan's **Today** card (the day's calorie/protein goal, next routine day, planned run), **This week** (template week with done days + weekly review) and the phase cards. A plan is an ordered list of **back-to-back phases measured in weeks** (`PeriodizationRepository.createChainedPlan` / `replanPlan`; plans start on a Monday). Moving/resizing a phase shifts its `phase_targets` with it; removing one cascades. `PhaseKind` (stored in `template_key`) gives each phase its colour, icon and nutrition defaults (`seedTargetForKind`).

Targets stay in `phase_targets` (one version per changed week, JSON columns). New fields are additive JSON keys: `training_json.strength_days`, `training_json.week_label`, `run.run_days`, `nutrition_json.rest_day`. The **template week** (`PhaseWeekPlan`, pure) marks strength days + run days (a linked running plan brings its own weekdays via `RunPlanWeekResolver`) as training days; rest days use the rest-day nutrition. `EffectiveNutritionGoalService` and adherence metrics resolve training vs rest per date through `getDayPlan`/`dayPlanFor`. The phase editor (`PhaseEditorController`) edits phase-level targets plus per-week `WeekAdjustment`s (label, training/rest kcal) and saves one target per week from the current week on via `savePhaseSetup` — lived weeks are history and never rewritten.

### AI Coach
`AiChatService` (singleton `ChangeNotifier`, `lib/state/ai_chat_service.dart`, with `part` files `ai_chat_wire.dart`, `ai_chat_persistence.dart`, `ai_chat_threads.dart`) orchestrates multi-turn chat with an OpenAI-compatible provider. Provider calls are in `lib/services/ai_service.dart`, injected local context in `ai_context_service.dart`, provider settings in `lib/state/ai_settings_notifier.dart`, presentation in `lib/widgets/ai/`.

`AiToolRegistry` (`lib/services/ai_tool_registry.dart`) is a **table of `AiToolSpec`s** (name, JSON schema, label, handler) assembled from one list per domain — `ai_tool_specs_{workouts,runs,goals,sleep,nutrition,wellness,proposals}.dart` — exposing **39 read-only tools** plus two proposal tools (`ai_tool_registry_test.dart` asserts 39 and 41). Query-to-tool hints (static regexes) are in `ai_tool_hints.dart`, shared math in `ai_tool_math.dart`. When adding or changing a tool, update its spec (schema, handler, label) and the tests together, and keep the count in this file in sync. Key deliberate decisions — don't undo without a feature request:
- **No mutation tools.** The AI can only read; routine and manual-food changes go through proposal/approve (`AiRoutineMutationService`), never direct writes. Revalidate proposal state before applying it in a transaction, and keep provider credentials out of SQLite, logs, prompts and backups.
- **Stable full catalog every round.** The whole tool schema is sent on every request; `toolNamesForQuery` only produces a *hint* line in the dynamic system block, never a filter. Do not reintroduce per-round pruning or a discovery meta-tool — they cost round trips, block cross-domain and paginated re-calls, and break prompt caching.
- **Cache-friendly wire layout** (`_buildWireMessages`): message 1 is the static prefix (user prompt + `_dataGroundingPolicy` + `_routineMutationPolicy`, identical across turns); message 2 is the single dynamic block (`<workout_data>` with day-granular metadata, rolling thread summary, tool hints). Keep anything per-turn out of message 1.
- **Turn loop is budget-bound**, not count-bound: tools stay available until `kMaxTurnInputTokens` (estimated or reported `prompt_tokens`) or `kMaxToolRounds` is hit, then one final call without tools. Grounded turns send `tool_choice: 'required'` (AiService falls back to `auto` per model on 4xx); a model that still answers without tools is accepted, never failed.
- **Tool results are truncated on the wire only** (`kMaxToolResultChars`, `_wireToolContent`) with a marker asking the model to narrow the query; the persisted message keeps the full payload for the UI. Malformed `arguments` JSON is reported back to the model as `invalid_arguments_json` instead of being silently emptied.
- **Rolling thread summary** (`_ensureThreadSummary`, table `ai_chat_thread_summaries`): when compaction drops old turns, one extra provider call folds them into a per-thread summary injected into the dynamic block. Failures degrade to the previous summary.
- **No streaming** — single POST, phase banner (`sending` → `executingReads` → `idle`).
- **No token/cost tracking or display** — `prompt_tokens` is used only in memory to calibrate the chars-per-token estimate (`_tokenScale`); nothing about usage is persisted or shown.
- **`TextSanitizer.sanitize`** strips only `<think>…</think>` blocks and `$N`/`${N}` citation placeholders; it must NOT touch `[1]`, zero-width chars, whitespace, or legitimate `$` (e.g. `R$ 100`). Do not broaden it without a concrete failing case and a test.

Interrupted-turn recovery: if an assistant message has `tool_calls` without matching `tool` responses, a synthetic `{ok:false, code:'interrupted'}` response is appended on thread open.

### Localization
All user-visible strings go in `lib/l10n/app_en.arb` + `app_pt.arb` (both, identical key sets, `ai*`/`sleep*`/`alarm*` prefixes by module); the app supports English and Brazilian Portuguese and every visible change must work in both. Run `flutter gen-l10n` after edits; never edit the generated `app_localizations*.dart`. Remove keys from both files when the last reference goes away. Locale config is in `l10n.yaml` (output class `AppLocalizations`, locales `en` + `pt`). Format dates shown to the user with the active locale (`pt_BR` for Portuguese).

## Testing

- **Dart tests** in `test/` use `flutter_test` + `sqflite_common_ffi` for in-memory SQLite. For anything that touches SQLite, use `test/support/test_db.dart` (`installTestDb()` / `uninstallTestDb()`, or `openTestDb()`): it opens an in-memory database with the **real schema** and installs it through `DatabaseHelper.overrideDatabase`. Do not hand-write `CREATE TABLE` statements in tests or open the application database. `test/support/ai_test_db.dart` (`installAiTestDb`/`uninstallAiTestDb`) is the same for AI tests; see also the other fixtures in `test/support/`.
- **Service/singleton overrides:** services expose `overrideForTest(...)` hooks (e.g. `AiChatService.overrideForTest`, `DatabaseHelper.overrideDatabase`) — inject fakes there; don't mock private `_state`. Use `SharedPreferences.setMockInitialValues` for preference-dependent tests.
- **Widget tests for native features** must tolerate a missing platform channel (`MissingPluginException` fallbacks in the service) — the sleep/alarm widget tests set this up explicitly.
- **Kotlin tests** in `android/app/src/test/` run with `./gradlew test`.
- Keep tests close to the behaviour changed: repository/migration tests for persistence, unit tests for services and calculations, widget tests for rendering and interaction, localization tests for visible strings. Run the smallest relevant test first, then the whole suite when the change warrants it, and do not claim validation that was not run.

## Gotchas

- Always `DatabaseHelper.instance.database` / `.xxxRepo`; never construct `DatabaseHelper()` or a repository directly.
- Check `mounted` (or `context.mounted`) before `setState`/using `BuildContext` after any `await`; show useful UI feedback when an action can fail.
- Use `package:workout_notes/...` imports across top-level `lib/` directories, not relative paths.
- Prefer `const` constructors, `final` values and named parameters for APIs with several arguments; avoid unrelated cleanup in a focused change and preserve existing user changes in the working tree.
- `sleep_entries` is the canonical sleep record; a monitor session is linked via `sleep_entry_id`. Import logic intentionally keeps a shorter test/recovery session from overwriting a longer night already recorded for the same local date.
- Before finishing: implementation follows the feature's existing boundary, both ARB files updated, tests added or updated, schema changes verified for fresh creation *and* migration, `flutter analyze` and the relevant tests pass, and the diff has no unrelated edits, secrets or debug code.
