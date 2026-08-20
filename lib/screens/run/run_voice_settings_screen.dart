import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/services/run_voice_settings_store.dart';
import 'package:workout_notes/services/run_voice_coach.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/settings/settings.dart';

class RunVoiceSettingsScreen extends StatefulWidget {
  const RunVoiceSettingsScreen({super.key});

  @override
  State<RunVoiceSettingsScreen> createState() => _RunVoiceSettingsScreenState();
}

class _RunVoiceSettingsScreenState extends State<RunVoiceSettingsScreen> {
  final _store = RunVoiceSettingsStore.instance;
  RunVoiceSettings _settings = const RunVoiceSettings.defaults();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loaded = await _store.load();
    if (!mounted) return;
    setState(() {
      _settings = loaded;
      _loading = false;
    });
  }

  Future<void> _persist(RunVoiceSettings next) async {
    setState(() => _settings = next);
    await _store.save(next);
  }

  Future<void> _playTestAnnouncement() async {
    final loc = AppLocalizations.of(context)!;
    if (!_settings.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.runVoiceTestDisabled)),
      );
      return;
    }
    final coach = RunVoiceCoach();
    coach.settingsOverride = _settings;
    final ok = await coach.speakTestAnnouncement();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.runVoiceTestFailed)),
      );
    }
  }

  Future<void> _pickDistanceEvery() async {
    final loc = AppLocalizations.of(context)!;
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(loc.runVoiceDistanceEveryKm(1)),
              onTap: () => Navigator.pop(ctx, 1),
            ),
            ListTile(
              title: Text(loc.runVoiceDistanceEveryKm(2)),
              onTap: () => Navigator.pop(ctx, 2),
            ),
            ListTile(
              title: Text(loc.runVoiceDistanceEveryKm(5)),
              onTap: () => Navigator.pop(ctx, 5),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await _persist(_settings.copyWith(distanceEveryKm: choice));
  }

  Future<void> _editTargetPace() async {
    final loc = AppLocalizations.of(context)!;
    var minutes = ((_settings.targetPaceSecPerKm ?? 360) ~/ 60).clamp(2, 15);
    var seconds = ((_settings.targetPaceSecPerKm ?? 0) % 60);
    seconds = (seconds ~/ 5) * 5;

    final action = await showDialog<_PaceDialogAction>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(loc.runVoiceTargetPace),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(loc.runVoiceTargetPaceHint),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('pace-min-$minutes'),
                          initialValue: minutes,
                          decoration: InputDecoration(
                            labelText: loc.runVoiceMinutes,
                          ),
                          items: [
                            for (var m = 2; m <= 15; m++)
                              DropdownMenuItem(value: m, child: Text('$m')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setDialogState(() => minutes = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('pace-sec-$seconds'),
                          initialValue: seconds,
                          decoration: InputDecoration(
                            labelText: loc.runVoiceSeconds,
                          ),
                          items: [
                            for (var s = 0; s < 60; s += 5)
                              DropdownMenuItem(
                                value: s,
                                child: Text(s.toString().padLeft(2, '0')),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setDialogState(() => seconds = v);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(ctx, _PaceDialogAction.clear),
                  child: Text(loc.runVoiceClearTargetPace),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    ctx,
                    _PaceDialogAction.save(minutes * 60 + seconds),
                  ),
                  child: Text(loc.commonSave),
                ),
              ],
            );
          },
        );
      },
    );
    if (action == null) return;
    if (action.clear) {
      await _persist(_settings.copyWith(clearTargetPace: true));
    } else if (action.seconds != null) {
      await _persist(_settings.copyWith(targetPaceSecPerKm: action.seconds));
    }
  }

  Future<void> _editInterval() async {
    final loc = AppLocalizations.of(context)!;
    var draft = _settings.interval;
    final saved = await showDialog<RunIntervalPreset>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(loc.runIntervalPresetTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IntervalMetricEditor(
                      label: loc.runIntervalWork,
                      metric: draft.workMetric,
                      value: draft.workValue,
                      onChanged: (metric, value) {
                        setDialogState(() {
                          draft = draft.copyWith(
                            workMetric: metric,
                            workValue: value,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _IntervalMetricEditor(
                      label: loc.runIntervalRest,
                      metric: draft.restMetric,
                      value: draft.restValue,
                      allowZero: true,
                      onChanged: (metric, value) {
                        setDialogState(() {
                          draft = draft.copyWith(
                            restMetric: metric,
                            restValue: value,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: Text(loc.runIntervalRepeats)),
                        IconButton(
                          onPressed: draft.repeats <= 1
                              ? null
                              : () => setDialogState(() {
                                    draft = draft.copyWith(
                                      repeats: draft.repeats - 1,
                                    );
                                  }),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('${draft.repeats}'),
                        IconButton(
                          onPressed: draft.repeats >= 99
                              ? null
                              : () => setDialogState(() {
                                    draft = draft.copyWith(
                                      repeats: draft.repeats + 1,
                                    );
                                  }),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, draft),
                  child: Text(loc.commonSave),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved == null) return;
    await _persist(_settings.copyWith(interval: saved));
  }

  String _intervalSummary(AppLocalizations loc) {
    final p = _settings.interval;
    String fmt(RunIntervalMetric metric, int value) {
      if (metric == RunIntervalMetric.time) {
        return RunFormatters.duration(value);
      }
      return value >= 1000 ? '${(value / 1000).toStringAsFixed(1)} km' : '$value m';
    }

    return loc.runIntervalPresetSummary(
      fmt(p.workMetric, p.workValue),
      fmt(p.restMetric, p.restValue),
      p.repeats,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final s = _settings;

    return Scaffold(
      appBar: SettingsAppBar(title: loc.runVoiceSettingsTitle),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  loc.runVoiceEnglishOnlyHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                SettingsSectionHeader(text: loc.runVoiceSectionGeneral),
                SettingsCard(
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.record_voice_over_outlined,
                      title: loc.runVoiceEnabled,
                      subtitle: loc.runVoiceEnabledSubtitle,
                      value: s.enabled,
                      onChanged: (v) => _persist(s.copyWith(enabled: v)),
                    ),
                    const SettingsCardDivider(),
                    SettingsLinkTile(
                      icon: Icons.play_circle_outline,
                      title: loc.runVoiceTestAnnouncement,
                      subtitle: loc.runVoiceTestAnnouncementSubtitle,
                      onTap: _playTestAnnouncement,
                    ),
                    const SettingsCardDivider(),
                    SettingsSwitchTile(
                      icon: Icons.headphones_outlined,
                      title: loc.runVoiceHeadphonesOnly,
                      subtitle: loc.runVoiceHeadphonesOnlySubtitle,
                      value: s.headphonesOnly,
                      onChanged: (v) =>
                          _persist(s.copyWith(headphonesOnly: v)),
                    ),
                    const SettingsCardDivider(),
                    SettingsSwitchTile(
                      icon: Icons.phone_disabled_outlined,
                      title: loc.runVoiceMuteOnCall,
                      subtitle: loc.runVoiceMuteOnCallSubtitle,
                      value: s.muteDuringCall,
                      onChanged: (v) =>
                          _persist(s.copyWith(muteDuringCall: v)),
                    ),
                  ],
                ),
                SettingsSectionHeader(text: loc.runVoiceSectionAnnouncements),
                SettingsCard(
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.straighten,
                      title: loc.runVoiceAnnounceDistance,
                      subtitle: loc.runVoiceAnnounceDistanceSubtitle,
                      value: s.announceDistance,
                      onChanged: (v) =>
                          _persist(s.copyWith(announceDistance: v)),
                    ),
                    if (s.announceDistance) ...[
                      const SettingsCardDivider(),
                      SettingsLinkTile(
                        icon: Icons.repeat,
                        title: loc.runVoiceDistanceFrequency,
                        subtitle: loc.runVoiceDistanceEveryKm(s.distanceEveryKm),
                        onTap: _pickDistanceEvery,
                      ),
                    ],
                    const SettingsCardDivider(),
                    SettingsSwitchTile(
                      icon: Icons.flag_outlined,
                      title: loc.runVoiceAnnounceSplit,
                      subtitle: loc.runVoiceAnnounceSplitSubtitle,
                      value: s.announceSplit,
                      onChanged: (v) =>
                          _persist(s.copyWith(announceSplit: v)),
                    ),
                    const SettingsCardDivider(),
                    SettingsSwitchTile(
                      icon: Icons.speed,
                      title: loc.runVoiceAnnouncePace,
                      subtitle: loc.runVoiceAnnouncePaceSubtitle,
                      value: s.announcePaceWarning,
                      onChanged: (v) =>
                          _persist(s.copyWith(announcePaceWarning: v)),
                    ),
                    if (s.announcePaceWarning) ...[
                      const SettingsCardDivider(),
                      SettingsLinkTile(
                        icon: Icons.timer_outlined,
                        title: loc.runVoiceTargetPace,
                        subtitle: s.targetPaceSecPerKm == null
                            ? loc.runVoiceTargetPaceNotSet
                            : RunFormatters.paceWithUnit(
                                s.targetPaceSecPerKm!.toDouble(),
                              ),
                        onTap: _editTargetPace,
                      ),
                    ],
                    const SettingsCardDivider(),
                    SettingsSwitchTile(
                      icon: Icons.satellite_alt_outlined,
                      title: loc.runVoiceAnnounceGps,
                      subtitle: loc.runVoiceAnnounceGpsSubtitle,
                      value: s.announceGpsStatus,
                      onChanged: (v) =>
                          _persist(s.copyWith(announceGpsStatus: v)),
                    ),
                    const SettingsCardDivider(),
                    SettingsSwitchTile(
                      icon: Icons.av_timer,
                      title: loc.runVoiceAnnounceIntervals,
                      subtitle: loc.runVoiceAnnounceIntervalsSubtitle,
                      value: s.announceIntervals,
                      onChanged: (v) =>
                          _persist(s.copyWith(announceIntervals: v)),
                    ),
                  ],
                ),
                SettingsSectionHeader(text: loc.runVoiceSectionIntervals),
                SettingsCard(
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.playlist_play,
                      title: loc.runIntervalDefaultOn,
                      subtitle: loc.runIntervalDefaultOnSubtitle,
                      value: s.intervalsEnabledByDefault,
                      onChanged: (v) =>
                          _persist(s.copyWith(intervalsEnabledByDefault: v)),
                    ),
                    const SettingsCardDivider(),
                    SettingsLinkTile(
                      icon: Icons.edit_outlined,
                      title: loc.runIntervalPresetTitle,
                      subtitle: _intervalSummary(loc),
                      onTap: _editInterval,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _PaceDialogAction {
  final bool clear;
  final int? seconds;

  const _PaceDialogAction._({required this.clear, this.seconds});
  const _PaceDialogAction.clear() : this._(clear: true);
  const _PaceDialogAction.save(int seconds)
      : this._(clear: false, seconds: seconds);
}

class _IntervalMetricEditor extends StatelessWidget {
  final String label;
  final RunIntervalMetric metric;
  final int value;
  final bool allowZero;
  final void Function(RunIntervalMetric metric, int value) onChanged;

  const _IntervalMetricEditor({
    required this.label,
    required this.metric,
    required this.value,
    required this.onChanged,
    this.allowZero = false,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<RunIntervalMetric>(
          segments: [
            ButtonSegment(
              value: RunIntervalMetric.distance,
              label: Text(loc.runIntervalMetricDistance),
            ),
            ButtonSegment(
              value: RunIntervalMetric.time,
              label: Text(loc.runIntervalMetricTime),
            ),
          ],
          selected: {metric},
          onSelectionChanged: (set) {
            final next = set.first;
            final defaultValue =
                next == RunIntervalMetric.distance ? 400 : 90;
            onChanged(next, value > 0 ? value : defaultValue);
          },
        ),
        const SizedBox(height: 8),
        if (metric == RunIntervalMetric.distance)
          DropdownButtonFormField<int>(
            key: ValueKey('dist-$metric-$value'),
            initialValue: _nearestDistance(value),
            decoration: InputDecoration(labelText: loc.runIntervalDistance),
            items: [
              if (allowZero)
                DropdownMenuItem(value: 0, child: Text(loc.runIntervalNone)),
              for (final m in const [100, 200, 400, 600, 800, 1000, 1600])
                DropdownMenuItem(
                  value: m,
                  child: Text(m >= 1000 ? '${m / 1000} km' : '$m m'),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              onChanged(metric, v);
            },
          )
        else
          DropdownButtonFormField<int>(
            key: ValueKey('time-$metric-$value'),
            initialValue: _nearestTime(value),
            decoration: InputDecoration(labelText: loc.runIntervalDuration),
            items: [
              if (allowZero)
                DropdownMenuItem(value: 0, child: Text(loc.runIntervalNone)),
              for (final s in const [30, 45, 60, 90, 120, 180, 300])
                DropdownMenuItem(
                  value: s,
                  child: Text(RunFormatters.duration(s)),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              onChanged(metric, v);
            },
          ),
      ],
    );
  }

  int _nearestDistance(int value) {
    final options = allowZero
        ? const [0, 100, 200, 400, 600, 800, 1000, 1600]
        : const [100, 200, 400, 600, 800, 1000, 1600];
    return options.reduce(
      (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
    );
  }

  int _nearestTime(int value) {
    final options = allowZero
        ? const [0, 30, 45, 60, 90, 120, 180, 300]
        : const [30, 45, 60, 90, 120, 180, 300];
    return options.reduce(
      (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
    );
  }
}
