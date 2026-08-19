import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';

class RunHistoryScreen extends StatefulWidget {
  const RunHistoryScreen({super.key});

  @override
  State<RunHistoryScreen> createState() => _RunHistoryScreenState();
}

class _RunHistoryScreenState extends State<RunHistoryScreen> {
  final _repo = RunRepository();
  List<RunActivity> _activities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _repo.listActivities(limit: 100);
    if (!mounted) return;
    setState(() {
      _activities = rows;
      _loading = false;
    });
  }

  Future<void> _openRecord() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunRecordScreen()),
    );
    if (mounted) _load();
  }

  Future<void> _openDetail(RunActivity activity) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(activityId: activity.id),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(loc.runHistoryTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRecord,
        icon: const Icon(Icons.directions_run),
        label: Text(loc.runRecordStart),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _activities.isEmpty
              ? EmptyStatePlaceholder(
                  icon: Icons.directions_run,
                  title: loc.runHistoryEmptyTitle,
                  subtitle: loc.runHistoryEmptySubtitle,
                  actionLabel: loc.runHistoryEmptyCta,
                  onAction: _openRecord,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                    itemCount: _activities.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final activity = _activities[index];
                      final date = DateFormat.yMMMd(
                        Localizations.localeOf(context).toString(),
                      ).add_Hm().format(activity.startedAt.toLocal());
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            backgroundColor:
                                theme.colorScheme.primaryContainer,
                            child: Icon(
                              Icons.directions_run,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            activity.title?.isNotEmpty == true
                                ? activity.title!
                                : loc.runDetailUntitled,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '$date · ${RunFormatters.distanceWithUnit(activity.distanceMeters)} · ${RunFormatters.duration(activity.movingTimeSeconds)}',
                          ),
                          trailing: Text(
                            RunFormatters.pace(activity.avgPaceSecPerKm),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onTap: () => _openDetail(activity),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
