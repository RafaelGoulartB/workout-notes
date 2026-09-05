<h1 align="center">Workout Notes</h1>

<p align="center">
  <a href="https://www.linkedin.com/in/rafael-goulartb/">
    <img alt="Rafael Goulart" src="https://img.shields.io/badge/-Rafael%20Goulart-0B7285?style=flat&logo=Linkedin&logoColor=white" />
  </a>
  <a href="https://github.com/RafaelGoulartB/workout-notes#readme">
    <img alt="Documentation" src="https://img.shields.io/badge/documentation-yes-0B7285.svg" />
  </a>
  <a href="https://github.com/RafaelGoulartB/workout-notes/graphs/commit-activity">
    <img alt="Maintenance" src="https://img.shields.io/badge/Maintained%3F-yes-0B7285.svg" />
  </a>
  <a href="https://github.com/RafaelGoulartB/workout-notes/blob/main/LICENSE">
    <img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-0B7285.svg" />
  </a>
  <a href="https://github.com/RafaelGoulartB/workout-notes/actions/workflows/release-android.yml">
    <img alt="Android release" src="https://img.shields.io/github/actions/workflow/status/RafaelGoulartB/workout-notes/release-android.yml?branch=main&label=Android%20release&color=0B7285" />
  </a>
  <img alt="GitHub Pull Requests" src="https://img.shields.io/github/issues-pr/RafaelGoulartB/workout-notes?color=0B7285" />
  <img alt="GitHub Contributors" src="https://img.shields.io/github/contributors/RafaelGoulartB/workout-notes?color=0B7285" />
  <img alt="GitHub repository size" src="https://img.shields.io/github/repo-size/RafaelGoulartB/workout-notes?color=0B7285" />
</p>

<p align="center">
  Training, nutrition, sleep, and progress in one local-first app.
</p>

Workout Notes brings strength training, GPS runs, food logging, sleep tracking, and body measurements together. Build routines, follow a periodized plan, and see how your habits change over time. Your journal lives on your device, with no account required.

Built with Flutter and Material 3, with English and Brazilian Portuguese, metric and imperial units, light and dark themes, and a customizable accent color. **Android is the most complete target**: background tracking, sleep monitoring, alarms, barcode scanning, and run voice coaching rely on native Android integrations.

## Train and track your progress

- **Strength training:** log sets, weight, reps, warm-ups, RPE, and notes. Build multi-day routines, group supersets, use rest timers, and review completed sessions.
- **Running and cardio:** record GPS routes or stationary-bike sessions, follow running plans and intervals, and use voice coaching. Review pace, splits, route replays, records, and trends.
- **Goals and measurements:** follow training volume, frequency, personal records, and an annual heatmap. Track weight, body composition, circumferences, and progress photos.

<table>
  <tr>
    <th width="33%">Live strength workout</th>
    <th width="33%">Live run tracking</th>
    <th width="33%">Training progress</th>
  </tr>
  <tr>
    <td><a href="assets/screenshots/workout-progress.png"><img src="assets/screenshots/workout-progress.png" width="100%" alt="Strength workout in progress with session and rest timers, weights, reps, and completed and pending sets" /></a></td>
    <td><a href="assets/screenshots/run-progress.png"><img src="assets/screenshots/run-progress.png" width="100%" alt="Run in progress using simulated GPS, with a live route, elapsed time, distance, pace, and session controls" /></a></td>
    <td><a href="assets/screenshots/progress.png"><img src="assets/screenshots/progress.png" width="100%" alt="Training report with goals, annual activity heatmap, and weekly workout frequency" /></a></td>
  </tr>
</table>

Also explore [completed run analysis](assets/screenshots/run.png) and [body measurements](assets/screenshots/body-measurements.png).

## Connect food, recovery, and planning

- **Nutrition:** keep a daily food diary with calorie and macro targets, saved meals, food search, barcode lookup, and nutrition trends.
- **Sleep:** log nights or monitor sleep on Android. Review duration, efficiency, regularity, estimated sleep stages, and weekly summaries; configure alarms and a sleep goal.
- **Periodization:** organize training into phases and weeks, link routines and running plans, set nutrition, training, weight, and sleep targets, and review check-ins or compare cycles.

<table>
  <tr>
    <th width="33%">Nutrition diary</th>
    <th width="33%">Sleep and recovery</th>
    <th width="33%">Periodization</th>
  </tr>
  <tr>
    <td><a href="assets/screenshots/nutrition.png"><img src="assets/screenshots/nutrition.png" width="100%" alt="Nutrition diary with daily calories, macronutrients, a plan-linked target, and meals" /></a></td>
    <td><a href="assets/screenshots/sleep.png"><img src="assets/screenshots/sleep.png" width="100%" alt="Sleep dashboard with goal completion, efficiency, bedtime, and estimated sleep stages" /></a></td>
    <td><a href="assets/screenshots/periodization.png"><img src="assets/screenshots/periodization.png" width="100%" alt="Active periodization plan with phases, weekly nutrition and training targets, and a weekly review" /></a></td>
  </tr>
</table>

<sub>Captured from the Android emulator in dark mode; the live run uses simulated GPS. Tap an image to view it at full resolution.</sub>

## Optional AI Coach

Connect your own OpenAI-compatible provider to discuss training, running, nutrition, and recovery using context from your journal. Configure the provider URL, API token, and model in **Settings > Configure AI**.

When used, the coach sends conversation and relevant app data to your chosen provider. Routine and manual-food changes are presented as proposals for approval before they are applied. Credentials stay in platform secure storage; no API key or hosted AI service is bundled.

## Your data

Core logging works locally in SQLite. Online features such as AI, map tiles, and remote food lookup need connectivity. Export and restore a compact JSON backup for device migration, or export workouts as CSV and share session summaries.

Backups include essential history, preferences, and progress photos, but exclude API tokens, AI conversations and proposals, detailed sleep stages, permissions, and active background sessions.

## Run locally

Use a Flutter SDK with Dart **3.12.1 or a compatible newer 3.x version**, Android tooling, and an emulator or physical device.

```bash
flutter doctor
flutter pub get
flutter run
```

## Development

The app uses `setState` and `ChangeNotifier`, SQLite repositories, and Kotlin services for Android background features. Feature code lives in `lib/screens`, `lib/services`, and `lib/repositories`; shared plan logic lives in `lib/periodization`.

```bash
flutter gen-l10n
flutter analyze
flutter test
flutter build apk --release
```

For native unit tests, run `./gradlew test` from `android/` (`.\gradlew.bat test` on Windows). See [AGENTS.md](AGENTS.md) for architecture, migrations, localization, and contribution conventions. Issues and pull requests are welcome.

The Android release workflow validates app changes on `main` before building an APK. README and screenshot-only changes do not trigger it; manual runs are available in Actions.

## License

[MIT](LICENSE) · [Rafael Goulart](https://www.linkedin.com/in/rafael-goulartb/)
