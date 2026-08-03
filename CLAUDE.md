# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Workout Notes is a **local-first Flutter app** (Android + iOS + web + desktop) for logging workouts, routines, goals, body measurements, sleep, and alarms. All data lives on-device: workouts in SQLite (`sqflite`), AI provider tokens in `flutter_secure_storage`, settings in SQLite + `shared_preferences`. There is no backend. The optional AI Coach talks to a user-configured OpenAI-compatible endpoint.

Heavier modules (sleep monitoring, alarms) have real **Android-native (Kotlin) counterparts** that run while the Flutter engine is closed, bridged over MethodChannel/EventChannel.

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

Localization: edit `lib/l10n/app_en.arb` and `app_pt.arb` **in parallel** (same keys in both), then run `flutter gen-l10n`. The generated `app_localizations*.dart` files are committed.

CI (`.github/workflows/release-android.yml`) runs `flutter analyze` + `flutter test`, then builds and releases a signed APK on pushes to `main` touching `lib/`, `android/`, `pubspec*`, etc.

## Architecture

### State management
Deliberately lightweight — no Riverpod/Bloc. Per-screen `setState` for local state; **`ChangeNotifier` singletons** for cross-cutting services. Singletons follow the pattern `ClassName.instance` (static final) or a static field on `WorkoutNotesApp` (e.g. `WorkoutNotesApp.themeNotifier`, `.aiSettings`). Screens consume them via `ListenableBuilder`/`addListener`. Don't introduce a state-management library unless this pattern clearly fails.

### Database & repositories
`DatabaseHelper` (`lib/database/database_helper.dart`) is a **singleton** — always `DatabaseHelper.instance.database`, never `new DatabaseHelper()`. Current schema version is `_dbVersion = 27`. It holds `late final` lazy repository instances (`.settingsRepo`, `.workoutRepo`, `.sleepMonitorRepo`, `.traditionalAlarmRepo`, etc.).

Each domain has a repository in `lib/repositories/` extending `BaseRepository` (which exposes `db`). Repositories own all SQL — screens query repos, never raw SQL directly (except through repo methods). Tables use UUID v4 client-generated PKs and `ON DELETE CASCADE` FKs.

**Schema changes:** bump `_dbVersion`, add to `_onCreate` (new installs) *and* `_onUpgrade` (existing installs). Upgrades are additive `CREATE TABLE IF NOT EXISTS` / `ALTER TABLE` statements wrapped in try/catch for idempotency. Code reading newer tables often guards with a `PRAGMA table_info` / `sqlite_master` existence check (see `_tableExists` in `sleep_monitor_repository.dart`) because older devices may have older schemas. Always parameterize queries (`?` placeholders) — never concatenate input into SQL.

### Sleep monitoring (Android-native)
The sleep monitor is a **Kotlin foreground service** (`android/.../sleep/SleepMonitoringService.kt`) that records mic audio into segments while the app is closed. Dart talks to it through `SleepMonitorService` (`lib/services/sleep_monitor_service.dart`), a `ChangeNotifier` facade over a MethodChannel (`workout_notes/sleep_monitor/methods`) + EventChannel (`.../events`). Native bridge: `SleepMonitorBridge.kt`.

The important architectural rule: **the EventChannel is only a live UI signal; durable data flows through the native spool.** The native service appends segments to a JSON spool (`SleepSessionSpool.kt`). When the app opens, `SleepMonitorService.recoverPendingSessions()` lists pending spools (`listPendingSessions`), imports each via `SleepMonitorRepository.importNativeSpool(...)` (atomic SQLite transaction, idempotent per session, merges into the daily `sleep_entries` row without creating duplicates), then `deleteSpool`. A failed SQLite commit leaves the spool intact for retry. Keep this one-way spool→Dart flow intact.

On import, the repository runs inference (`SleepInferenceService`) and acoustic staging to fill `estimated_sleep_minutes`, onset/wake, stage minutes, and confidence, and writes `sleep_stage_epochs`. Staging works two ways: if the spool carries model-labelled `stage_epochs` (validated acoustic model), `SleepStageAnalysisService` summarizes them directly; otherwise, for `audio-features-v2` nights, the heuristic `SleepStageEngine` (`lib/services/sleep_stage_engine.dart`) labels 30s windows (awake/sleeping/deep) from spectral + actigraphy features with a Viterbi smoother and the same summarizer consumes its epochs. The native side (`SpectralAnalyzer`, `BreathingAnalyzer`, `MotionAggregator`) only extracts privacy-preserving per-window aggregates — it never labels. `tool/validate_sleep_stages.dart` compares the hypnogram against a manual diary (`--template` for the diary shape).

All `SleepMonitorService` methods guard with `!kIsWeb && defaultTargetPlatform == TargetPlatform.android` and return safe defaults (e.g. `supported: false`) on other platforms / `MissingPluginException`. Preserve that pattern — tests run on desktop where the channels don't exist.

### Traditional alarms
`TraditionalAlarmService` (`lib/services/traditional_alarm_service.dart`) persists alarm definitions in SQLite (`TraditionalAlarmRepository`) and **mirrors the runnable snapshot to Android** (native side owns ringing/repeat while app is closed). `reconcile()` on startup pulls native schedules (`states`) back into the DB, then schedules DB alarms that lack a native snapshot. SQLite is the source of truth; native scheduling is best-effort (`_scheduleBestEffort`) so a transient channel failure never blocks the editor — `reconcile` fixes it next launch. Global snooze defaults are stored as `app_settings` rows (`alarm_global_max_snoozes`, `alarm_global_snooze_enabled`).

### AI Coach
`AiChatService` (singleton `ChangeNotifier`, `lib/state/ai_chat_service.dart`) orchestrates multi-turn chat with an OpenAI-compatible provider. `AiToolRegistry` exposes **13 read-only tools** (hand-written JSON schemas in `_schemaFor`). Key deliberate decisions — don't undo without a feature request:
- **No mutation tools.** The AI can only read; routine changes go through proposal/approve (`AiRoutineMutationService`), never direct writes.
- **No streaming** — single POST, phase banner (`sending` → `executingReads` → `idle`).
- **No token/cost tracking** — `usage` from the API response is discarded.
- **`TextSanitizer.sanitize`** strips only `<think>…</think>` blocks and `$N`/`${N}` citation placeholders; it must NOT touch `[1]`, zero-width chars, whitespace, or legitimate `$` (e.g. `R$ 100`).

Interrupted-turn recovery: if an assistant message has `tool_calls` without matching `tool` responses, a synthetic `{ok:false, code:'interrupted'}` response is appended on thread open.

### Localization
All user-visible strings go in `lib/l10n/app_en.arb` + `app_pt.arb` (both, matching keys, `ai*`/`sleep*`/`alarm*` prefixes by module). Run `flutter gen-l10n` after edits. Locale config is in `l10n.yaml` (output class `AppLocalizations`, locales `en` + `pt`). Date formatting uses `pt_BR`; standard date-string idiom is `DateTime.toIso8601String().substring(0, 10)` → `yyyy-MM-dd`.

## Testing

- **Dart tests** in `test/` use `flutter_test` + `sqflite_common_ffi` for in-memory SQLite. Install a test DB via `DatabaseHelper.overrideDatabase = db` (set in `setUp`, cleared to `null` in `tearDown`). See `test/traditional_alarm_repository_test.dart` for the canonical setup, and `test/support/ai_test_db.dart` (`installAiTestDb`/`uninstallAiTestDb`) for a prebuilt schema.
- **Service/singleton overrides:** services expose `overrideForTest(...)` hooks (e.g. `AiChatService.overrideForTest`, `DatabaseHelper.overrideDatabase`) — inject fakes there; don't mock private `_state`.
- **Widget tests for native features** must tolerate a missing platform channel (`MissingPluginException` fallbacks in the service) — the sleep/alarm widget tests set this up explicitly.
- **Kotlin tests** in `android/app/src/test/` run with `./gradlew test`.

## Gotchas

- Always `DatabaseHelper.instance.database`; never construct `DatabaseHelper()` directly.
- Check `mounted` before `setState` after any `await` in a widget.
- Use `package:workout_notes/...` imports across top-level `lib/` directories, not relative paths.
- `sleep_entries` is the canonical sleep record; a monitor session is linked via `sleep_entry_id`. Import logic intentionally keeps a shorter test/recovery session from overwriting a longer night already recorded for the same local date.
- `AGENTS.md` at the repo root is a detailed companion guide but **predates several modules** (sleep monitoring, alarms, the repositories/ layer). Treat it as supplementary; trust the code and this file for current architecture.
