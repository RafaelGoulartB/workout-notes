# Plan: Run Voice Alerts + Interval Sets (TTS)

## Context & Goal

Add **configurable English TTS announcements** only for the **Running module**, plus **work/rest interval sets** that speak on transitions.

User choices locked:
- Settings live in a **dedicated Run settings screen** (not global Settings).
- Configurable: master on/off, headphones-only, mute-on-call, **which events**, and **frequency**.
- MVP intervals: work/rest by **distance or time** + TTS on phase changes (no full preset library / history yet).
- Spoken language: **English only** (`en-US`), regardless of UI locale.

No TTS exists today. GPS run tracking is Android-first (`RunTrackingService` + native foreground service). Voice must work while the record screen is open (and ideally while screen is on with the Flutter engine alive); native background TTS while the Flutter isolate is dead is **out of scope** for MVP.

## Design decisions

| Topic | Choice |
|---|---|
| Settings entry | Gear on `RunStatsScreen` → `RunVoiceSettingsScreen` |
| Persistence | `app_settings` key `run_voice_settings_v1` (JSON) via `SettingsRepository` — no schema bump |
| TTS package | `flutter_tts` (force `en-US`) |
| Headphones / in-call | Small Android MethodChannel (`workout_notes/run_audio/methods`) — `isHeadsetConnected`, `isInPhoneCall` |
| Headphones rule | When enabled: announce only if wired/BT headset/earbuds present; otherwise skip |
| Call rule | When enabled: skip announce if `AudioManager.mode` is `MODE_IN_CALL` / `MODE_IN_COMMUNICATION` |
| Event engine | Pure Dart `RunVoiceCoach` listening to `RunTrackingService` state deltas |
| Interval state | Session-only (not persisted on activity for MVP); configured defaults from settings |
| Interval UI | On `RunRecordScreen`: enable/disable intervals for this run + live phase chip (Work N / Rest N) |
| Pause behavior | Interval clock freezes while run is paused; no announce on pause/resume unless GPS status changes |
| Pace warning | Optional target pace (sec/km) + tolerance %; speak when rolling pace drifts outside band (throttled) |
| Scope | Run module only — no traditional alarms / sleep / workout gym TTS |

### Configurable settings model

```dart
class RunVoiceSettings {
  bool enabled;                 // master
  bool headphonesOnly;
  bool muteDuringCall;
  bool announceDistance;        // every N km
  int distanceEveryKm;          // 1 | 2 | 5 (default 1)
  bool announceSplit;           // each completed km split (pace of last km)
  bool announcePaceWarning;     // off-target pace
  int? targetPaceSecPerKm;      // null = disabled threshold logic
  int paceTolerancePercent;     // default 10
  bool announceGpsStatus;       // weak / recovered (throttled)
  bool announceIntervals;       // work/rest transitions + countdown cues
  bool intervalsEnabledByDefault;
  RunIntervalPreset interval;   // work/rest mode+value + repeats
}

class RunIntervalPreset {
  RunIntervalMetric workMetric; // distance | time
  int workValue;                // meters or seconds
  RunIntervalMetric restMetric;
  int restValue;
  int repeats;                  // work segments to complete
}
```

### Announcement catalog (English strings, hardcoded — not ARB)

| Event | Example speech |
|---|---|
| Distance milestone | `"2 kilometers. Time 12 minutes 4 seconds. Average pace 6 minutes 2 seconds per kilometer."` |
| Split complete | `"Kilometer 3. Pace 5 minutes 48 seconds."` |
| Pace too fast / slow | `"Pace too fast."` / `"Pace too slow."` |
| GPS weak / recovered | `"Weak GPS signal."` / `"GPS signal restored."` |
| Interval work start | `"Work interval 1 of 8. Go."` |
| Interval rest start | `"Rest. 90 seconds."` (or `"Rest. 200 meters."`) |
| Interval complete | `"Intervals complete."` |
| Interval halfway cue (optional, time-based only) | `"30 seconds remaining."` when ≤30s left on current phase |

UI labels/settings copy stay in ARB (`runVoice*`, `runInterval*`) in **en + pt**. Spoken phrases stay English constants in `lib/services/run_voice_phrases.dart`.

### Audio gating flow

```
shouldSpeak(settings, audioCaps):
  if !settings.enabled → false
  if settings.muteDuringCall && audioCaps.inCall → false
  if settings.headphonesOnly && !audioCaps.headsetConnected → false
  return true
```

Poll / listen:
- On each announce attempt, query native caps (cheap).
- Optionally subscribe to headset plug / audio-mode changes via EventChannel later; MVP = query at speak time is enough.

### Interval engine (session)

```
phase: idle | work | rest | done
On run start + intervals on for session:
  enter work #1
On each tracking tick (distance/time deltas while recording):
  accumulate phase progress against work/rest target
  when target hit → announce transition → next phase
  after last work → if rest configured, do final rest optional OR go done after last work
```

MVP rule: **repeats = number of work segments**. After each work except the last, run rest; after last work → `done` (no trailing rest unless rest value > 0 and we always rest after work — prefer: rest after every work including last only if `restAfterLast == false` default skip trailing rest).

Default preset: work 400 m / rest 90 s / repeats 8.

## Affected Files

### New
- `lib/models/run_voice_settings.dart` — settings + interval preset + JSON (de)serialize
- `lib/services/run_voice_settings_store.dart` — load/save via `SettingsRepository` / `DatabaseHelper.instance`
- `lib/services/run_voice_phrases.dart` — English phrase builders (pace/distance formatting for speech)
- `lib/services/run_tts_service.dart` — thin `flutter_tts` wrapper (en-US, queue, stop on dispose)
- `lib/services/run_audio_gate_service.dart` — MethodChannel facade + safe defaults off-Android
- `lib/services/run_voice_coach.dart` — ChangeNotifier or plain listener: hooks tracking + settings + gate + TTS + interval FSM
- `lib/services/run_interval_engine.dart` — pure FSM (easy to unit test)
- `lib/screens/run/run_voice_settings_screen.dart` — toggles, frequency, target pace, interval preset editor
- `android/.../run/RunAudioBridge.kt` — headset + call detection
- `test/run_interval_engine_test.dart`
- `test/run_voice_coach_test.dart` (fake TTS + fake gate + synthetic tracking snapshots)

### Modified
- `pubspec.yaml` — add `flutter_tts`
- `android/.../MainActivity.kt` (or existing plugin registrant pattern) — register `RunAudioBridge`
- `android/app/src/main/AndroidManifest.xml` — only if a permission is required; prefer **no** `READ_PHONE_STATE` (use `AudioManager.mode` instead)
- `lib/screens/run/run_stats_screen.dart` — AppBar gear → settings
- `lib/screens/run/run_record_screen.dart` — start/stop coach; interval toggle + phase chip; optional quick link to settings
- `lib/l10n/app_en.arb` + `app_pt.arb` — `runVoice*` / `runInterval*` UI strings; then `flutter gen-l10n`

## Implementation Checklist

### Phase 1: Settings + TTS plumbing
- [x] Add `flutter_tts` dependency
- [x] Implement `RunVoiceSettings` JSON store with sensible defaults
- [x] Implement `RunTtsService` (en-US, speak/stop, ignore failures on desktop/tests)
- [x] Implement `RunAudioBridge` (Kotlin) + Dart gate service
- [x] Build `RunVoiceSettingsScreen` + navigate from `RunStatsScreen`

### Phase 2: Announcement coach (free run)
- [x] `RunVoiceCoach` listens to `RunTrackingService`
- [x] Distance every N km, split complete, GPS weak/recover (debounce ≥ 20s), pace warning (debounce ≥ 45s)
- [x] Wire coach lifecycle to `RunRecordScreen` (attach on start/resume recording, detach on stop/discard)
- [x] Honor headphones-only + mute-on-call before every `speak`

### Phase 3: Interval sets
- [x] Pure `RunIntervalEngine` (distance/time work+rest, repeats)
- [x] Drive engine from tracking ticks inside coach
- [x] Record UI: session toggle “Intervals”, show Work/Rest progress
- [x] TTS on phase transitions + optional time remaining cue

### Phase 4: Validation
- [x] Unit tests for interval FSM edge cases (pause freeze, zero rest, last-work no trailing rest)
- [x] Unit tests for coach event selection / throttling with fakes
- [ ] Manual on Android device: headset on/off, fake call (Bluetooth call or dialer), debug GPS sim for km + intervals
- [x] `flutter analyze` + targeted `flutter test`

## Risks & Technical Debt

- **Flutter TTS while screen off:** Android may pause the Flutter engine; announcements may stop until user returns. Accept for MVP; future: native TTS inside `RunTrackingService` notification path.
- **Headphones detection quirks:** BT watches / car audio may count as headset — document as intentional (wired + BT SCO/A2DP).
- **No READ_PHONE_STATE:** call mute via audio mode is best-effort (VoIP may vary).
- **Interval results not saved** on the activity — fine for MVP; later attach interval summary to notes/spool if needed.
- **Double-announce risk** if both “distance every 1 km” and “split” are on — allow both but keep phrases short; or document that split = last-km pace and distance = cumulative summary.

## Out of scope (explicit)

- iOS run tracking / iOS audio gate
- Custom TTS voice picker / non-English speech
- Interval preset library, templates, or history charts
- Speaking gym workouts / sleep / traditional alarms
- Native background TTS without Flutter UI
