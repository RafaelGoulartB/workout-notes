import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'l10n/app_localizations.dart';
import 'services/notification_service.dart';
import 'screens/workout/workout_home_screen.dart';

/// List of accent seed colors available in settings.
class AccentColors {
  static const List<Color> options = [
    Color(0xFFC62828), // Deep Red
    Color(0xFFD84315), // Dark Orange
    Color(0xFFE65100), // Orange
    Color(0xFFF9A825), // Amber
    Color(0xFF6A1B9A), // Deep Purple
    Color(0xFF0D47A1), // Dark Blue
    Color(0xFF37474F), // Graphite
    Color(0xFF4A6741), // Forest Green (default)
  ];

  static const defaultColor = Color(0xFF37474F);
  static const defaultIndex = 6;

  static int indexOf(Color color) {
    for (int i = 0; i < options.length; i++) {
      if (options[i].toARGB32() == color.toARGB32()) return i;
    }
    return defaultIndex;
  }
}

/// Simple notifier for accent color and theme mode changes.
class ThemeNotifier extends ChangeNotifier {
  Color _seedColor;
  ThemeMode _themeMode;

  ThemeNotifier(this._seedColor, this._themeMode);

  Color get seedColor => _seedColor;
  ThemeMode get themeMode => _themeMode;

  void setSeedColor(Color color) {
    _seedColor = color;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}

/// Notifier for locale/language changes.
class LocaleNotifier extends ChangeNotifier {
  Locale _locale;

  LocaleNotifier(this._locale);

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    _locale = locale;
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notification service
  final notif = NotificationService.instance;
  await notif.init();
  await notif.loadSettings();
  await notif.requestPermission();

  // Load saved settings
  final prefs = await SharedPreferences.getInstance();
  final savedColor = prefs.getInt('accent_color') ?? AccentColors.defaultColor.toARGB32();
  final initialColor = Color(savedColor);

  final themeModeStr = prefs.getString('theme_mode') ?? 'system';
  final initialThemeMode = _parseThemeMode(themeModeStr);

  // Load saved locale
  final localeStr = prefs.getString('app_locale') ?? 'en';
  final initialLocale = _parseLocale(localeStr);

  // Initialize date formatting based on locale
  final localeForDateFormat = localeStr == 'pt' ? 'pt_BR' : 'en';
  await initializeDateFormatting(localeForDateFormat, null);
  Intl.defaultLocale = localeForDateFormat;

  // Initialize the theme notifier with the loaded values
  WorkoutNotesApp.themeNotifier = ThemeNotifier(initialColor, initialThemeMode);
  WorkoutNotesApp.localeNotifier = LocaleNotifier(initialLocale);

  runApp(WorkoutNotesApp(
    initialColor: initialColor,
    initialThemeMode: initialThemeMode,
    initialLocale: initialLocale,
  ));
}

Locale _parseLocale(String value) {
  if (value == 'pt' || value == 'pt_BR') {
    return const Locale('pt', 'BR');
  }
  return const Locale('en');
}

ThemeMode _parseThemeMode(String value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

class WorkoutNotesApp extends StatefulWidget {
  final Color initialColor;
  final ThemeMode initialThemeMode;
  final Locale initialLocale;

  const WorkoutNotesApp({
    super.key,
    required this.initialColor,
    required this.initialThemeMode,
    required this.initialLocale,
  });

  static late ThemeNotifier themeNotifier;
  static late LocaleNotifier localeNotifier;

  @override
  State<WorkoutNotesApp> createState() => _WorkoutNotesAppState();
}

class _WorkoutNotesAppState extends State<WorkoutNotesApp> {
  late Color _seedColor;
  late ThemeMode _themeMode;
  late Locale _locale;

  @override
  void initState() {
    super.initState();
    _seedColor = widget.initialColor;
    _themeMode = widget.initialThemeMode;
    _locale = widget.initialLocale;
    WorkoutNotesApp.themeNotifier.addListener(_onThemeChanged);
    WorkoutNotesApp.localeNotifier.addListener(_onLocaleChanged);
    // Sync the notifier's initial values
    WorkoutNotesApp.themeNotifier.setSeedColor(_seedColor);
    WorkoutNotesApp.themeNotifier.setThemeMode(_themeMode);
    WorkoutNotesApp.localeNotifier.setLocale(_locale);
  }

  @override
  void dispose() {
    WorkoutNotesApp.themeNotifier.removeListener(_onThemeChanged);
    WorkoutNotesApp.localeNotifier.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {
      _seedColor = WorkoutNotesApp.themeNotifier.seedColor;
      _themeMode = WorkoutNotesApp.themeNotifier.themeMode;
    });
  }

  void _onLocaleChanged() {
    setState(() {
      _locale = WorkoutNotesApp.localeNotifier.locale;
    });
  }

  ThemeData _buildTheme(Color seed, Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ),
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Workout Notes',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: _buildTheme(_seedColor, Brightness.light),
      darkTheme: _buildTheme(_seedColor, Brightness.dark),
      themeMode: _themeMode,
      home: const WorkoutHomeScreen(),
    );
  }
}
