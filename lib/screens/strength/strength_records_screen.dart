import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/widgets/run/insights/run_insight_card.dart';
import 'package:workout_notes/widgets/strength/insights/strength_insights_data.dart';
import 'package:workout_notes/widgets/strength/records/strength_recent_records.dart';
import 'package:workout_notes/widgets/strength/records/strength_records_hero.dart';
import 'package:workout_notes/widgets/strength/records/strength_records_list.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Personal records: headline counts, the latest bests as a timeline and the
/// best e1RM / heaviest weight / best session volume of each exercise grouped
/// by muscle group.
class StrengthRecordsScreen extends StatefulWidget {
  const StrengthRecordsScreen({super.key});

  @override
  State<StrengthRecordsScreen> createState() => _StrengthRecordsScreenState();
}

class _StrengthRecordsScreenState extends State<StrengthRecordsScreen> {
  bool _loading = true;
  bool _failed = false;
  List<StrengthRecord> _records = const [];
  List<StrengthRecordEvent> _events = const [];
  List<Map<String, dynamic>> _categories = const [];
  int _thisMonth = 0;
  int _thisYear = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sets = await DatabaseHelper.instance.strengthRecordsRepo.loadSets();
      final categories = await DatabaseHelper.instance.exerciseRepo
          .getCategories();
      if (!mounted) return;
      final records = StrengthRecordsCalculator.records(sets);
      // Oldest first from the calculator; the timeline wants newest first.
      final events = StrengthRecordsCalculator.events(sets).reversed.toList();
      final now = DateTime.now();
      setState(() {
        _records = records;
        _events = events;
        _categories = [
          for (final c in categories)
            if ((c['energy_system'] as String?) != 'aerobic') c,
        ];
        _thisMonth = events
            .where((e) => e.date.year == now.year && e.date.month == now.month)
            .length;
        _thisYear = events.where((e) => e.date.year == now.year).length;
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _open({
    required String exerciseId,
    required Map<String, dynamic> exerciseRow,
  }) async {
    await openStrengthExercise(
      context,
      exerciseId: exerciseId,
      exerciseRow: exerciseRow,
    );
    // The exercise may have been renamed or deleted meanwhile.
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.strengthRecordsTitle),
        actions: [
          IconButton(
            tooltip: loc.runInsightsHowItWorks,
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => showRunInsightInfo(
              context,
              loc.strengthRecordsTitle,
              loc.strengthRecordsInfo,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? AppEmptyState(
              icon: Icons.error_outline_rounded,
              title: loc.strengthInsightsLoadError,
              subtitle: '',
            )
          : _records.isEmpty
          ? AppEmptyState(
              icon: Icons.emoji_events_outlined,
              title: loc.strengthRecordsEmptyTitle,
              subtitle: loc.strengthRecordsEmptySubtitle,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: AppUi.screenPadding.copyWith(top: 8, bottom: 40),
                children: [
                  StrengthRecordsHero(
                    exercises: _records.length,
                    thisMonth: _thisMonth,
                    thisYear: _thisYear,
                  ),
                  AppSectionHeader(loc.strengthRecordsRecent),
                  StrengthRecentRecords(
                    events: _events,
                    onOpen: (e) => _open(
                      exerciseId: e.exerciseId,
                      exerciseRow: e.exerciseRow,
                    ),
                  ),
                  AppSectionHeader(loc.strengthRecordsByExercise),
                  StrengthRecordsList(
                    records: _records,
                    categories: _categories,
                    onOpen: (r) => _open(
                      exerciseId: r.exerciseId,
                      exerciseRow: r.exerciseRow,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
