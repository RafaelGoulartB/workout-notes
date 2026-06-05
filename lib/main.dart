import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/notification_service.dart';
import 'screens/workout/workout_home_screen.dart';
import 'screens/home_screen.dart';

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

  static const List<String> labels = [
    'Vermelho',
    'Laranja Escuro',
    'Laranja',
    'Âmbar',
    'Roxo',
    'Azul Escuro',
    'Graphite',
    'Verde Musgo',
  ];

  static const List<IconData> icons = [
    Icons.circle,
    Icons.circle,
    Icons.circle,
    Icons.circle,
    Icons.circle,
    Icons.circle,
    Icons.circle,
    Icons.circle,
  ];

  static const defaultColor = Color(0xFF4A6741);
  static const defaultIndex = 7;

  static int indexOf(Color color) {
    for (int i = 0; i < options.length; i++) {
      if (options[i].value == color.value) return i;
    }
    return defaultIndex;
  }
}

/// Simple notifier for accent color changes.
class ThemeNotifier extends ChangeNotifier {
  Color _seedColor;

  ThemeNotifier(this._seedColor);

  Color get seedColor => _seedColor;

  void setSeedColor(Color color) {
    _seedColor = color;
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);

  // Initialize notification service
  final notif = NotificationService.instance;
  await notif.init();
  await notif.loadSettings();
  await notif.requestPermission();

  // Load saved accent color
  final prefs = await SharedPreferences.getInstance();
  final savedColor = prefs.getInt('accent_color') ?? AccentColors.defaultColor.value;
  final initialColor = Color(savedColor);

  runApp(LifeNotesApp(initialColor: initialColor));
}

class LifeNotesApp extends StatefulWidget {
  final Color initialColor;
  
  const LifeNotesApp({super.key, required this.initialColor});

  static final ThemeNotifier themeNotifier = ThemeNotifier(AccentColors.defaultColor);

  @override
  State<LifeNotesApp> createState() => _LifeNotesAppState();
}

class _LifeNotesAppState extends State<LifeNotesApp> {
  late Color _seedColor;

  @override
  void initState() {
    super.initState();
    _seedColor = widget.initialColor;
    LifeNotesApp.themeNotifier.addListener(_onThemeChanged);
    // Sync the notifier's initial value
    LifeNotesApp.themeNotifier.setSeedColor(_seedColor);
  }

  @override
  void dispose() {
    LifeNotesApp.themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {
      _seedColor = LifeNotesApp.themeNotifier.seedColor;
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
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Life Notes',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(_seedColor, Brightness.light),
      darkTheme: _buildTheme(_seedColor, Brightness.dark),
      themeMode: ThemeMode.system,
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          HomeScreen(),
          WorkoutHomeScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: theme.colorScheme.surface,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: 'Notas',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Treino',
          ),
        ],
      ),
    );
  }
}
