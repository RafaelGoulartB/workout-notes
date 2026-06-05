# Workout Notes 🏋️

> A beautiful workout tracker built with Flutter.

**Workout Notes** helps you track your workouts, log sets, monitor progress, and stay motivated — all with a clean Material 3 design and automatic dark mode.

---

## ✨ Features

### 🏋️ Workout Tracker

| Feature | Description |
|---|---|
| 📚 **Exercise Library** | Browse exercises organized by category and energy system (aerobic / anaerobic) |
| ▶️ **Active Workout** | Start a live session with timer, set logging, and real-time tracking |
| 🔢 **Set Tracking** | Log weight, reps, distance, time, RPE, warmup sets, and notes per exercise |
| 📅 **Workout History** | Review past workouts with full details |
| 📈 **Progress Charts** | Visualize your progress over time with animated charts (`fl_chart`) |
| 📆 **Calendar View** | See your workout history on a calendar with heatmap |
| 🔁 **Routines** | Create, save, and reuse workout routines |
| 📏 **Body Measurements** | Track weight, measurements, and body stats over time |
| ⏱️ **Rest Timer** | Built-in rest timer between sets with notifications |
| ⚡ **Quick Add** | Rapidly log a workout without full session setup |
| 📤 **CSV Export** | Export your workout data as CSV files |
| 🏷️ **Exercise Detail** | View exercise info, history, and stats in tabbed detail screens |
| ⭐ **Favorites** | Mark exercises as favorites for quick access |

### 🎨 App Experience

| Feature | Description |
|---|---|
| 🌗 **Dark Mode** | Automatically adapts to your system theme |
| 🎨 **Custom Accent Colors** | 8 hand-picked seed colors to personalize your app |
| ✨ **Smooth Animations** | Animated transitions powered by `flutter_animate` |
| 🔔 **Notifications** | Rest timer alerts and reminders |
| 📱 **Cross-Platform** | Android, iOS, Web, Linux, macOS, Windows |

---

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK** 3.44+
- **Dart** 3.12+

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/workout_notes.git

# Navigate to the project
cd workout_notes

# Get dependencies
flutter pub get

# Run the app
flutter run
```

### Building for Release

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release

# Linux / macOS / Windows
flutter build linux --release   # or macos / windows
```

---

## 🧱 Tech Stack

| Layer | Technology |
|---|---|
| **Language** | Dart 3.12+ |
| **UI Framework** | Flutter — Material 3 |
| **State Management** | `setState` + `ChangeNotifier` (lightweight) |
| **Storage** | `sqflite` (SQLite) |
| **Charts** | `fl_chart` |
| **Animations** | `flutter_animate` |
| **Export** | `share_plus` + `csv` |
| **Notifications** | `flutter_local_notifications` |
| **UUID** | `uuid` (v4) |
| **Date/Time** | `intl` with `pt_BR` locale |

---

## 🏛️ Architecture

```
lib/
├── main.dart                       # App entry, theme shell, navigation
├── database/
│   ├── database_helper.dart        # SQLite singleton & migrations
│   ├── seed_data.dart              # Default exercise categories & exercises
│   └── test_seed_data.dart         # Sample data for development
├── services/
│   ├── export_service.dart         # CSV data export
│   ├── notification_service.dart   # Notification setup & scheduling
│   └── rest_timer_service.dart     # Rest timer logic
├── screens/
│   └── workout/
│       ├── workout_home_screen.dart
│       ├── active_workout_screen.dart
│       ├── workout_detail_screen.dart
│       ├── exercise_library_screen.dart
│       ├── exercise_form_screen.dart
│       ├── exercise_detail_tabs_screen.dart
│       ├── routines_screen.dart
│       ├── calendar_screen.dart
│       ├── progress_screen.dart
│       ├── body_tracker_screen.dart
│       ├── settings_screen.dart
│       ├── export_screen.dart
│       ├── quick_add_screen.dart
│       └── rest_timer_screen.dart
└── widgets/
    ├── empty_state_placeholder.dart
    ├── exercise_picker_sheet.dart
    ├── collapsible_section.dart
    └── workout_heatmap.dart
```

### Data Model

Full relational schema via SQLite:

```
exercise_categories (1) ──→ (N) exercises (1) ──→ (N) exercise_entries (1) ──→ (N) sets
                                │
routines (1) ──→ (N) routine_days (1) ──→ (N) routine_exercises (1) ──→ (N) predefined_sets
                                │
workouts (1) ──→ (N) exercise_entries
                                │
body_measurements (standalone)
app_settings (key-value)
```

> Data is stored locally using **SQLite** — no internet required.

---

## 📸 Screenshots

> *Coming soon — add your app screenshots here.*

| Workout Dashboard | Active Workout | Progress Charts |
|---|---|---|
| ![][screenshot-workout] | ![][screenshot-active] | ![][screenshot-charts] |

---

## 🧪 Running Tests

```bash
# Run all tests
flutter test

# Static analysis
flutter analyze
```

---

## 🤝 Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---
