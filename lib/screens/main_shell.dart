import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/screens/workout/sleep_tracker_screen.dart';
import 'package:workout_notes/screens/workout/workout_home_screen.dart';
import 'package:workout_notes/screens/workout/nutrition_home_screen.dart';
import 'package:workout_notes/screens/workout/periodization_home_screen.dart';

/// Primary application navigation. Each tab keeps its own navigation state
/// while the user switches between workout, sleep, nutrition and plan
/// tracking. Optional sections (e.g. Plan) can be hidden from settings.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WorkoutNotesApp.sections.addListener(_onSectionsChanged);
  }

  @override
  void dispose() {
    WorkoutNotesApp.sections.removeListener(_onSectionsChanged);
    super.dispose();
  }

  void _onSectionsChanged() {
    if (!mounted) return;
    setState(() {
      if (!WorkoutNotesApp.sections.planEnabled && _selectedIndex == 3) {
        _selectedIndex = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final planEnabled = WorkoutNotesApp.sections.planEnabled;
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          const WorkoutHomeScreen(),
          const SleepTrackerScreen(),
          const NutritionHomeScreen(),
          if (planEnabled) const PeriodizationHomeScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
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
