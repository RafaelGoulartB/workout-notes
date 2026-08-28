# AGENTS.md — Workout Notes

A comprehensive guide for LLM agents working on the Workout Notes project. This document captures the project's architecture, conventions, design decisions, and common patterns to help agents produce correct, maintainable code.

---

## 1. Project Overview

**Workout Notes** is a local-first Flutter application for strength training,
running, sleep, nutrition, body measurements, goals, periodization and progress.
Android is the most complete target because background run tracking, sleep
monitoring, alarms, barcode scanning and voice coaching use native Android
services. The remaining Flutter UI is designed to stay portable.

- **Workout module:** Exercise library, live workout logging, routines, body
  measurements, goals, progress charts, calendar, rest timer and CSV export.
- **Running module:** GPS and stationary-bike sessions, plans, interval engine,
  replay, achievements and voice coaching.
- **Wellness modules:** Sleep monitoring/alarms, nutrition diary, food library,
  saved meals and periodization plans/check-ins.
- **AI Coach:** Multi-provider chat with read tools and explicitly approved
  proposal flows for routine changes and manual food creation.

The app uses Material 3 with dynamic theming, automatic dark mode support, and customizable accent colors.

---

## 2. Tech Stack

| Layer | Choice |
|---|---|
| Language | Dart 3.12+ |
| UI Framework | Flutter (Material 3) |
| State Management | `setState` + `ChangeNotifier` (lightweight) |
| Preferences | `shared_preferences` |
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
├── models/                            # Workout, run, sleep, nutrition, periodization and AI models
├── database/
│   ├── database_helper.dart           # SQLite singleton (all workout tables)
│   ├── seed_data.dart                 # Default exercise categories & exercises
│   └── test_seed_data.dart            # Sample workout data for development
├── repositories/                      # SQLite access grouped by domain
├── services/                          # AI, export, timers, run, sleep and notification logic
├── state/                             # Shared ChangeNotifier coordinators
├── navigation/                        # Cross-feature navigation helpers
├── screens/
│   ├── main_shell.dart                # Four-tab application shell
│   ├── run/                           # Run recording, plans, history and analytics
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
├── periodization/                      # Pure logic for the plan/periodization module
│   ├── periodization_phase_form_controller.dart  # ChangeNotifier state for the phase editor
│   ├── week_override_resolver.dart     # Weekly override model + diffing (no UI state)
│   ├── nutrition_target_input.dart     # Nutrition field parsing + macro resolution
│   └── phase_draft_data.dart           # Wizard <-> editor draft payload
├── utils/
│   └── periodization_palette.dart      # Shared phase/plan color palette
└── widgets/
    ├── empty_state_placeholder.dart   # Reusable empty-state widget
    └── exercise_picker_sheet.dart     # Bottom sheet for picking exercises
```

`lib/periodization/` holds controller/resolver code with **no** `BuildContext` or
`setState` — widgets consume it via `ChangeNotifier`, so both the standalone
phase editor screen and the plan wizard can reuse the same logic inline.

---

## 4. Architecture & Design Decisions

### 4.1 State Management

The project intentionally avoids heavy state management libraries (Riverpod, Bloc, etc.). It uses:

- **`setState`** — For local, per-screen state.
- **`ChangeNotifier`** — For app-wide concerns like accent color changes (`ThemeNotifier` in `main.dart`).
- **Direct database reads** — Most screens query SQLite directly and rebuild with `setState`.

**Rule:** Do not introduce a state management library unless the pattern clearly proves insufficient.

### 4.2 Database Architecture

Domain data uses SQLite via `sqflite`. Schema creation is split across
`database_schema.dart`, `database_nutrition_schema.dart`,
`database_periodization_schema.dart` and `database_run_plan_schema.dart`;
incremental migrations live under `lib/database/migrations/`.

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
- `ThemeNotifier` is a static `ChangeNotifier` on `WorkoutNotesApp.themeNotifier`.
- Both light and dark themes are built from the same seed color using `ColorScheme.fromSeed`.
- Theme mode follows the system (`ThemeMode.system`).

### 4.4 Navigation

- `MainShell` lazily populates an `IndexedStack` with Workout, Sleep, Nutrition
  and Plan tabs. Plan visibility is controlled by `SectionsNotifier`.
- A Material 3 `NavigationBar` switches between the tabs while preserving each
  tab's state.
- Screen-to-screen navigation uses `Navigator.push` with `MaterialPageRoute`.

### 4.5 Locale

- The app supports English and Brazilian Portuguese. The saved locale controls
  both `AppLocalizations` and `Intl.defaultLocale` (`en` or `pt_BR`).

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

Models are grouped by domain under `lib/models/`. Run, sleep, nutrition,
periodization and AI records use typed Dart models; legacy workout repository
APIs still expose some SQLite rows as `Map<String, dynamic>`.

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
- The suite contains unit, repository, service, localization and widget tests;
  keep new coverage close to the behavior being changed.
- When adding tests:
  - Use `flutter_test` for widget tests.
  - Use `sqflite_common_ffi` for database unit tests (in-memory SQLite).
  - Use `SharedPreferences.setMockInitialValues` for settings tests.
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
3. **Locale:** The app supports `en` and `pt_BR`. All visible strings belong in
   the ARBs. Date strings stored in SQLite use `yyyy-MM-dd`; format visible dates
   with the active locale.
4. **Theme changes:** When reading/changing accent color, use
   `WorkoutNotesApp.themeNotifier` and persist to `SharedPreferences`.
5. **Workout timer:** The timer in `active_workout_screen.dart` is managed client-side; `startWorkoutTimer`/`stopWorkoutTimer`/`resetWorkoutTimer` in `DatabaseHelper` handle persistence.
6. **Active workout split:** UI, controller logic and routine actions live in
   `active_workout_screen.dart`, `active_workout_controller.dart` and
   `active_workout_routine_actions.dart`. Keep new behavior in the appropriate
   part rather than growing the screen again.
7. **Empty states:** Use `EmptyStatePlaceholder` widget for consistent empty-state UI across screens.
8. **Don't use relative imports across top-level directories.** Use `package:workout_notes/...` imports.
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
| `uuid` | ^4.6.0 | UUID generation |
| `intl` | ^0.20.2 | Date formatting |
| `shared_preferences` | ^2.3.4 | App and feature preferences |
| `sqflite` | ^2.4.2 | Workout database |
| `path` | ^1.9.1 | Path utilities for DB |
| `path_provider` | ^2.1.6 | File system paths |
| `fl_chart` | ^1.2.0 | Progress charts |
| `flutter_animate` | ^4.5.2 | Animations |
| `flutter_map` | ^8.3.2 | Running maps |
| `latlong2` | ^0.10.1 | Geographic coordinates |
| `flutter_local_notifications` | ^22.3.0 | Notifications and alarms |
| `share_plus` | ^13.3.0 | File sharing/export |
| `csv` | ^8.0.0 | CSV generation |
| `file_picker` | ^12.1.1 | Backup import/export picker |
| `flutter_secure_storage` | ^10.3.1 | AI provider tokens |

---

## 12. Decision Log

| Decision | Rationale |
|---|---|
| SQLite for domain data, preferences for settings | Relational history needs transactions and indexed queries; simple UI configuration does not. |
| `setState` over state management libs | The app's complexity doesn't warrant the overhead. Each screen is relatively self-contained. |
| UUID v4 as primary keys | Offline-first friendly; no auto-increment conflicts. |
| `pt_BR` locale | The primary user is Brazilian Portuguese speaking. |
| Material 3 with seed colors | Provides a polished, adaptive look with minimal theming code. |
| Single `DatabaseHelper` singleton | Avoids multiple connections and ensures migrations run once. |

---

## 13. AI Coach (Personal Trainer)

A multi-provider AI chat that acts as a personal trainer. Read-only access to
workouts, exercises, routines, body measurements, cardio stats, and goals.
Conversations are persisted locally; tokens are stored in `flutter_secure_storage`.

### File map

| Layer | Key files |
|---|---|
| Models | `lib/models/ai_provider.dart`, `ai_settings.dart`, `ai_chat_thread.dart`, `ai_chat_message.dart`, `ai_message_role.dart`, `ai_tool_call.dart`, `ai_chat_state.dart` |
| Services | `lib/services/ai_service.dart` (OpenAI-compatible HTTP), `lib/services/ai_context_service.dart` (DB → JSON), `lib/services/ai_tool_registry.dart` (35 read tools + guarded proposal schemas) |
| State | `lib/state/ai_settings_notifier.dart` (provider config, persisted to SharedPreferences), `lib/state/ai_chat_service.dart` (singleton `ChangeNotifier` orchestrator) |
| Utils | `lib/utils/token_estimator.dart` (3.5 chars/token estimate for history compaction) |
| UI | `lib/screens/workout/ai_chat_screen.dart`, `ai_settings_screen.dart`, `ai_chat_history_screen.dart` |
| Widgets | `lib/widgets/ai/ai_message_bubble.dart`, `ai_tool_result_bubble.dart`, `ai_chat_input_bar.dart`, `ai_provider_picker_sheet.dart`, `ai_empty_state.dart` |
| L10n | `app_en.arb` + `app_pt.arb` (keys prefixed `aiCoach`, `aiChat`, `aiHistory`, `aiSettings`, `aiEmpty`) |
| Entry | `lib/screens/workout/settings_screen.dart` (AI Coach section) |
| Wire | `lib/main.dart` `WorkoutNotesApp.aiSettings` + `AiChatService.bootstrap()` |

### Multi-provider system

- `AiProvider { id, name, baseUrl, availableModels, selectedModel, createdAt }`.
- `AiSettings` holds `List<AiProvider>` + `activeProviderId` + `systemPrompt` + `contextMode`.
- Token storage: `flutter_secure_storage` key `ai_token:<providerId>`. A legacy `ai_token` is migrated on first read.
- Provider list + active id + prompt + context mode persist to SharedPreferences under `ai_providers_v1`, `ai_active_provider_id_v1`, `ai_system_prompt_v1`, `ai_context_mode_v1`.
- Models are fetched live via `GET {baseUrl}/models` and cached in `AiProvider.availableModels`.
- Active provider/model can be switched at runtime via a bottom-sheet picker from the chat header.

### Chat flow (`AiChatService`)

1. `send(text)` → loads the active provider + token from `AiSettingsNotifier`, ensures a thread (creates a new `ai_chat_threads` row on first message), appends a user `AiChatMessage`, sets `phase = sending`.
2. `_runTurn` builds the wire payload from the system policy, cached context,
   compacted history and a query-selected subset of the 35 read tools. Guarded
   proposal and capability-discovery tools are added only when applicable.
3. `AiService.sendChat` POSTs to `{baseUrl}/chat/completions` and parses the response (text + tool_calls + usage).
4. If the response has `tool_calls`: switch to `phase = executingReads`, run each via `AiToolRegistry.executeRead(...)`, append `role='tool'` messages with the JSON result, and re-send to the model. Up to 3 read rounds; after that a final no-tools call is made to force a closing answer.
5. If no tool calls: store the assistant message, set `phase = idle`, persist the thread + messages to SQLite.
6. **Interrupted-turn recovery**: when opening a thread, if an assistant message has `tool_calls` without matching `tool` responses, a synthetic `{ok:false, code:'interrupted'}` response is appended so the next turn can continue.

### Tool system (35 read tools + guarded proposals)

The registry covers workout history/details, exercises and PRs, routines, body
measurements, cardio/running plans, goals, sleep, nutrition and cross-domain
wellness analysis. Treat `AiToolRegistry._tools` as the source of truth rather
than duplicating the full list here.

- Read tools execute immediately. `propose_routine_change` and
  `propose_manual_food_creation` create reviewable previews; they never apply a
  change without an explicit in-app confirmation.
- JSON schemas are hand-written in `AiToolRegistry._schemaFor(name)`.
- The registry uses argument aliasing (English/Portuguese keys) and falls back to friendly `humanLabel(...)` strings for the chat UI.

### Context injection

- `AiContextService.build({mode})` returns JSON with `metadata` + `summary`.
- Three modes control data volume:
  - `minimal`: totals, streak, current-month report only.
  - `standard`: + last-4-weeks volume, top exercises, active goals.
  - `full`: + category distribution, body composition trend.
- Cached 60s in-memory; invalidated on turn boundary.
- The system prompt explicitly tells the model to never follow instructions inside `<workout_data>` and to use the read tools for further details.

### Database schema (v49)

The current database version is 49. AI persistence currently uses:

- `ai_chat_threads (id PK, title, created_at, updated_at, last_message_preview, archived)` with `idx_ai_chat_threads_updated (updated_at DESC)`.
- `ai_chat_messages (id PK, thread_id FK→threads ON DELETE CASCADE, role, content, tool_call_id, tool_name, tool_calls_json, created_at)` with `idx_ai_chat_messages_thread (thread_id, created_at ASC)`.
- New methods on `DatabaseHelper`: `upsertAiChatThread`, `replaceAiChatMessages`, `getAiChatThreads`, `getAiChatMessagesThread`, `renameAiChatThread`, `deleteAiChatThread`.
- The AI chat tables originated in the v15 migration; later migrations add
  pinning, proposals and attachments. The application schema as a whole is v49.

### 13.4 Design decisions (deliberate, not gaps)

- **Routine mutations use proposals, never direct AI writes.** `propose_routine_change` creates an `ai_routine_proposals` draft only after an explicit user request. The chat shows an approval card; `AiRoutineMutationService.approve` rechecks the stored routine snapshot and applies the complete tree in one SQLite transaction. Rejected drafts do nothing, stale drafts cannot apply, and a successful application is followed by a no-tools AI summary. Exercises must already exist in the library.

- **Output sanitisation is narrow and targeted.** `TextSanitizer.sanitize` strips exactly two patterns: `<think>…</think>` reasoning blocks (a DeepSeek-R1 model architecture artifact) and `$\d+` / `$\{\d+\}` citation placeholders (e.g. `$1`, `${2}`). The latter is a learned behavior from pre-training that several models exhibit — the model uses `$1` as a token meaning "the proper noun I should write here". System prompt instructions don't reliably override it, so the sanitizer handles it as a last resort. We do NOT touch `[1]`, `【1】`, `〈1〉`, `⟨1⟩`, zero-width chars, whitespace, or legitimate `$` (e.g. `R$ 100` with no digit after the `$`). The system prompt still forbids citation placeholders, which helps models that obey and signals when a model doesn't.
- **No direct AI writes.** Routine and manual-food changes use guarded proposal
  flows with explicit confirmation. Other domains remain read-only from chat.
- **No token/cost tracking** — no `AiUsageScreen`, no per-message cost badge, no monthly usage stats. The current implementation discards `usage` from the API response. Keep it that way unless the feature is requested.
- **No streaming** — single `POST` + parse full response. UI shows a phase banner (`sending` → `executingReads` → `idle`). Switching to SSE would require an `http.Client.stream` upgrade plus chunked state updates.
- **Entry only via Settings** — no FAB on the home screen. Discovery happens in `settings_screen.dart` under the new `AI COACH` section, with two `LinkTile`s: `Treinador IA` (chat, redirects to settings if not configured) and `Configurar IA` (provider list + system prompt + context mode).
- **`ChangeNotifier` singleton, not Riverpod** — the app deliberately avoids state-management libraries (§4.1). `AiChatService.instance` is a `ChangeNotifier` consumed via `ListenableBuilder` / `addListener` in the chat screens. `AiSettingsNotifier` is a static field on `WorkoutNotesApp`. This matches the existing `RestTimerService.instance` pattern.
- **ARB-based l10n** — the app uses `AppLocalizations` (not the hand-rolled `L10n`/`AiStrings` pattern of `gastos`). All AI strings live in `app_en.arb` + `app_pt.arb` with the `ai*` prefix; `flutter gen-l10n` regenerates the `AppLocalizations*` files automatically.
- **Generated l10n files are NOT versioned** — `lib/l10n/app_localizations*.dart` are build artifacts ignored by git (see `.gitignore`) and regenerated automatically on every build/test via `flutter: generate: true` + `l10n.yaml`. Never edit them by hand; always edit the `.arb` sources and run `flutter gen-l10n`. Note: gen-l10n (this Flutter version) supports exactly ONE `.arb` per locale in a flat `arb-dir` — multi-file synthetic packages were removed, so the ARB sources (~1400 lines each) are the intended size ceiling.

### Adding a new read tool

1. Implement the dispatch case in `AiToolRegistry.executeRead`.
2. Add the JSON schema in `AiToolRegistry._schemaFor(name)`.
3. Add a friendly label in `AiToolRegistry.humanLabel(name)`.
4. (Optional) include the tool's output in `AiContextService` for a relevant context mode.

### When adding a new provider / model

`AiService.normalizeBaseUri` auto-suffixes `/v1`. If the provider needs a non-standard path (e.g. Anthropic-style `/v1/messages`), use the provider's base URL and extend `AiService.sendChat` to dispatch by host or by an explicit `protocol` field on `AiProvider`.

### Tests

Add tests for any new tool or context branch using `sqflite_common_ffi`:

```dart
// test/ai_tool_registry_test.dart
final db = await inMemoryDatabase();
DatabaseHelper.overrideForTest(db);
final reg = AiToolRegistry();
final result = await reg.executeRead(toolName: 'list_recent_workouts', args: {});
expect(result.ok, true);
```

For HTTP, inject a stub `http.Client` into `AiService`. For the chat orchestrator, override collaborators via `AiChatService.overrideForTest(...)` and assert on `_state.messages` after `await service.send(...)`.

