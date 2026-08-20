import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/screens/workout/sleep_tracker_screen.dart';
import 'package:workout_notes/screens/workout/workout_home_screen.dart';
import 'package:workout_notes/screens/workout/nutrition_home_screen.dart';
import 'package:workout_notes/screens/workout/periodization_home_screen.dart';

/// Primary application navigation. Each tab keeps its own navigation state
/// while the user switches between workout, sleep, nutrition and progress
/// (plan + body measurements). Optional sections (e.g. Progress) can be
/// hidden from settings.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  final ValueNotifier<int> _selectedTab = ValueNotifier<int>(0);
  late final Map<int, Widget> _builtTabs = <int, Widget>{
    0: WorkoutHomeScreen(selectedTab: _selectedTab),
  };

  @override
  void initState() {
    super.initState();
    WorkoutNotesApp.sections.addListener(_onSectionsChanged);
  }

  @override
  void dispose() {
    WorkoutNotesApp.sections.removeListener(_onSectionsChanged);
    _selectedTab.dispose();
    super.dispose();
  }

  void _onSectionsChanged() {
    if (!mounted) return;
    var resetToWorkout = false;
    setState(() {
      if (!WorkoutNotesApp.sections.planEnabled && _selectedIndex == 3) {
        _selectedIndex = 0;
        resetToWorkout = true;
      }
    });
    if (resetToWorkout) _selectedTab.value = 0;
  }

  Widget _createTab(int index) => switch (index) {
        0 => WorkoutHomeScreen(selectedTab: _selectedTab),
        1 => const SleepTrackerScreen(),
        2 => const NutritionHomeScreen(),
        3 => const PeriodizationHomeScreen(),
        _ => const SizedBox.shrink(),
      };

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      _builtTabs.putIfAbsent(index, () => _createTab(index));
    });
    _selectedTab.value = index;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final planEnabled = WorkoutNotesApp.sections.planEnabled;
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: List<Widget>.generate(
          planEnabled ? 4 : 3,
          (index) => _builtTabs[index] ?? const SizedBox.shrink(),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.fitness_center_outlined),
            selectedIcon: const Icon(Icons.fitness_center),
            label: loc.tabWorkout,
          ),
          NavigationDestination(
            icon: const Icon(Icons.nightlight_outlined),
            selectedIcon: const Icon(Icons.nightlight_round),
            label: loc.tabSleep,
          ),
          NavigationDestination(
            icon: const Icon(Icons.restaurant_outlined),
            selectedIcon: const Icon(Icons.restaurant),
            label: loc.tabNutrition,
          ),
          if (planEnabled)
            NavigationDestination(
              icon: const Icon(Icons.view_timeline_outlined),
              selectedIcon: const Icon(Icons.view_timeline),
              label: loc.tabPlan,
            ),
        ],
      ),
    );
  }
}
