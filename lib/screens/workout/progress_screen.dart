import 'package:flutter/material.dart';
import 'package:workout_notes/screens/strength/strength_insights_screen.dart';

/// Kept so older navigation keeps working: progress now lives in the strength
/// analysis ([StrengthInsightsScreen]).
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) => const StrengthInsightsScreen();
}
