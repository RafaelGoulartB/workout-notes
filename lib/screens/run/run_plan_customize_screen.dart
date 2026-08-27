import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

/// Coach-style wizard: days → intent/volume → paces → preview → create.
class RunPlanCustomizeScreen extends StatefulWidget {
  final RunPlanTemplate template;

  const RunPlanCustomizeScreen({super.key, required this.template});

  @override
  State<RunPlanCustomizeScreen> createState() => _RunPlanCustomizeScreenState();
}

class _RunPlanCustomizeScreenState extends State<RunPlanCustomizeScreen> {
  final _repo = RunPlanRepository();
  final _timeCtl = TextEditingController();
  final _weeklyKmCtl = TextEditingController();

  int _step = 0;
  late int _sessions;
  final Set<int> _days = {};
  RunPlanIntent _intent = RunPlanIntent.finish;
  RunPlanIntensity _intensity = RunPlanIntensity.standard;
  bool _includeHills = true;
  bool _skipPace = false;
  _PaceSource _paceSource = _PaceSource.goal;
  late double _paceDistanceMeters;
  DateTime? _raceDate;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    // Templates cap what they allow (a run/walk progression tops out at four
    // days), so the default has to be a value the user can actually re-pick.
    final allowed = widget.template.allowedSessionsPerWeek;
    final preferred = widget.template.sessionsPerWeek.clamp(3, 5);
    _sessions = allowed.contains(preferred) ? preferred : allowed.last;
    _paceDistanceMeters = _defaultDistance(widget.template.goalKind);
    _seedDefaultDays();
    if (widget.template.key == 'return' ||
        widget.template.key == 'first_5k' ||
        widget.template.key == 'first_10k' ||
        widget.template.key == 'first_half' ||
        widget.template.key == 'first_marathon') {
      _intent = RunPlanIntent.finish;
    } else if (widget.template.style == RunPlanTemplateStyle.performance ||
        widget.template.raceFinish) {
      _intent = RunPlanIntent.pb;
    } else {
      _intent = RunPlanIntent.finish;
    }
  }

  @override
  void dispose() {
    _timeCtl.dispose();
    _weeklyKmCtl.dispose();
    super.dispose();
  }

  /// Current weekly volume, when the athlete filled it in.
  double? get _currentWeeklyKm {
    final raw = _weeklyKmCtl.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || value < 0) return null;
    return value;
  }

  void _seedDefaultDays() {
    _days
      ..clear()
      ..addAll(_defaultDaysFor(_sessions));
  }

  static List<int> _defaultDaysFor(int sessions) => switch (sessions) {
    3 => const [2, 5, 7],
    5 => const [2, 4, 5, 6, 7],
    _ => const [2, 4, 5, 7],
  };

  static double _defaultDistance(RunPlanGoalKind goal) => switch (goal) {
    RunPlanGoalKind.fiveK => RunPaceCalculator.fiveKMeters,
    RunPlanGoalKind.tenK => RunPaceCalculator.tenKMeters,
    RunPlanGoalKind.half => RunPaceCalculator.halfMeters,
    RunPlanGoalKind.marathon => RunPaceCalculator.marathonMeters,
    _ => RunPaceCalculator.fiveKMeters,
  };

  bool get _daysValid => _days.length == _sessions;

  RunPlanPaceCalibration? get _calibration {
    if (_skipPace) return null;
    final seconds = _parseDuration(_timeCtl.text);
    if (seconds == null || seconds <= 0) return null;
    return RunPlanPaceCalibration(
      distanceMeters: _paceDistanceMeters,
      timeSeconds: seconds,
    );
  }

  RunPaces? get _previewPaces {
    try {
      return _calibration?.paces;
    } catch (_) {
      return null;
    }
  }

  RunPlanBuildConfig get _config => RunPlanBuildConfig(
    sessionsPerWeek: _sessions,
    availableDays: (_days.toList()..sort()),
    intent: _intent,
    intensity: _intensity,
    calibration: _calibration,
    raceDate: _raceDate,
    currentWeeklyKm: _currentWeeklyKm,
    includeHills: _includeHills,
  );

  List<RunPlanTemplateWorkout> get _weekPreview {
    if (!_daysValid) return const [];
    return RunPlanComposer.compose(widget.template, _config).first;
  }

  RunPlanReadiness? get _readiness {
    if (!_daysValid) return null;
    try {
      return RunPlanComposer.assess(widget.template, _config);
    } catch (_) {
      return null;
    }
  }

  static String _km(double value) => value.toStringAsFixed(0);

  /// Coach warnings for the current step. Days step: only the schedule smell;
  /// preview step: everything, so the athlete sees it right before creating.
  Widget _buildWarnings(
    AppLocalizations loc,
    ThemeData theme, {
    required bool full,
  }) {
    final readiness = _readiness;
    if (readiness == null) return const SizedBox.shrink();
    final messages = <String>[
      if (readiness.consecutiveDays) loc.runPlanCustomizeWarnConsecutiveDays,
      if (full && readiness.baselineZero) loc.runPlanCustomizeWarnZeroBaseline,
      if (full && readiness.volumeGap)
        loc.runPlanCustomizeWarnVolumeGap(
          _km(readiness.startWeeklyKm),
          _km(readiness.currentWeeklyKm ?? 0),
        ),
      if (full && readiness.timeCapDistanceGap)
        loc.runPlanCustomizeWarnTimeCapGap(
          _km(readiness.longRunCapKm),
          _km(readiness.requiredLongKm),
        )
      else if (full && readiness.longRunShort)
        loc.runPlanCustomizeWarnLongRunShort(
          _km(readiness.peakLongKm),
          _km(readiness.requiredLongKm),
        ),
    ];
    if (messages.isEmpty) return const SizedBox.shrink();
    final scheme = theme.colorScheme;
    final blocking = full && !readiness.canCreate;
    final background = blocking
        ? scheme.errorContainer
        : scheme.tertiaryContainer;
    final foreground = blocking
        ? scheme.onErrorContainer
        : scheme.onTertiaryContainer;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        color: background,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: foreground),
                  const SizedBox(width: 8),
                  Text(
                    loc.runPlanCustomizeWarnTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ),
              for (final message in messages) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(color: foreground),
                ),
              ],
              if (blocking) ...[
                const SizedBox(height: 8),
                Text(
                  loc.runPlanCustomizeBlocked,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (_creating || !_daysValid || !(_readiness?.canCreate ?? false)) return;
    setState(() => _creating = true);
    try {
      final isPt = Localizations.localeOf(context).languageCode == 'pt';
      final plan = await RunPlanTemplates.create(
        _repo,
        widget.template,
        name: widget.template.title(isPt),
        config: _config,
      );
      if (!mounted) return;
      Navigator.pop(context, plan);
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isPt = Localizations.localeOf(context).languageCode == 'pt';
    final canNext = switch (_step) {
      0 => _daysValid,
      1 => true,
      2 => _skipPace || _calibration != null,
      _ => _daysValid && (_readiness?.canCreate ?? false),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.runPlanCustomizeTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.template.title(isPt),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  loc.runPlanCustomizeSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      Expanded(
                        child: Container(
                          height: 4,
                          margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: i <= _step
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_step == 0) _buildDaysStep(loc, theme),
                if (_step == 1) _buildIntentStep(loc, theme),
                if (_step == 2) _buildPaceStep(loc, theme),
                if (_step == 3) _buildPreviewStep(loc, theme),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: _creating
                          ? null
                          : () => setState(() => _step--),
                      child: Text(loc.runPlanCustomizeBack),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: !canNext || _creating
                        ? null
                        : () {
                            if (_step < 3) {
                              setState(() => _step++);
                            } else {
                              _create();
                            }
                          },
                    child: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _step < 3
                                ? loc.runPlanCustomizeNext
                                : loc.runPlanCustomizeCreate,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaysStep(AppLocalizations loc, ThemeData theme) {
    final labels = [
      loc.runPlanCustomizeWeekdayMon,
      loc.runPlanCustomizeWeekdayTue,
      loc.runPlanCustomizeWeekdayWed,
      loc.runPlanCustomizeWeekdayThu,
      loc.runPlanCustomizeWeekdayFri,
      loc.runPlanCustomizeWeekdaySat,
      loc.runPlanCustomizeWeekdaySun,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.runPlanCustomizeDaysTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          loc.runPlanCustomizeDaysHelp,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in widget.template.allowedSessionsPerWeek)
              ChoiceChip(
                label: Text(loc.runPlanCustomizeSessions(n)),
                selected: _sessions == n,
                onSelected: (_) => setState(() {
                  _sessions = n;
                  _seedDefaultDays();
                }),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          loc.runPlanCustomizePickDays(_sessions),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(labels[d - 1]),
                selected: _days.contains(d),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      if (_days.length >= _sessions) {
                        // Replace oldest selection so the user can re-pick.
                        final sorted = _days.toList()..sort();
                        _days.remove(sorted.first);
                      }
                      _days.add(d);
                    } else {
                      _days.remove(d);
                    }
                  });
                },
              ),
          ],
        ),
        if (!_daysValid) ...[
          const SizedBox(height: 12),
          Text(
            loc.runPlanCustomizePickDays(_sessions),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        _buildWarnings(loc, theme, full: false),
        const SizedBox(height: 24),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(loc.runPlanCustomizeRaceDate),
          subtitle: Text(
            _raceDate == null
                ? loc.runPlanRaceDateNone
                : MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(_raceDate!),
          ),
          trailing: IconButton(
            icon: Icon(
              _raceDate == null ? Icons.event_outlined : Icons.event_available,
            ),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    _raceDate ?? DateTime.now().add(const Duration(days: 84)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 800)),
              );
              if (picked != null) setState(() => _raceDate = picked);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildIntentStep(AppLocalizations loc, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.runPlanCustomizeIntentTitle,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          loc.runPlanCustomizeIntentHelp,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _OptionCard(
          selected: _intent == RunPlanIntent.finish,
          title: loc.runPlanCustomizeIntentFinish,
          subtitle: loc.runPlanCustomizeIntentFinishHint,
          onTap: () => setState(() => _intent = RunPlanIntent.finish),
        ),
        const SizedBox(height: 8),
        _OptionCard(
          selected: _intent == RunPlanIntent.pb,
          title: loc.runPlanCustomizeIntentPb,
          subtitle: loc.runPlanCustomizeIntentPbHint,
          onTap: () => setState(() => _intent = RunPlanIntent.pb),
        ),
        const SizedBox(height: 24),
        Text(loc.runPlanCustomizeIntensity, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in RunPlanIntensity.values)
              ChoiceChip(
                label: Text(switch (value) {
                  RunPlanIntensity.conservative =>
                    loc.runPlanCustomizeIntensityConservative,
                  RunPlanIntensity.standard =>
                    loc.runPlanCustomizeIntensityStandard,
                  RunPlanIntensity.aggressive =>
                    loc.runPlanCustomizeIntensityAggressive,
                }),
                selected: _intensity == value,
                onSelected: (_) => setState(() => _intensity = value),
              ),
          ],
        ),
        if (widget.template.style == RunPlanTemplateStyle.performance) ...[
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.runPlanCustomizeIncludeHills),
            subtitle: Text(loc.runPlanCustomizeIncludeHillsHelp),
            value: _includeHills,
            onChanged: (value) => setState(() => _includeHills = value),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          loc.runPlanCustomizeBaselineTitle,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          loc.runPlanCustomizeBaselineHelp,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _weeklyKmCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: loc.runPlanCustomizeBaselineField,
            hintText: loc.runPlanCustomizeBaselineHint,
            suffixText: 'km',
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildPaceStep(AppLocalizations loc, ThemeData theme) {
    final distances = <(String, double)>[
      ('5 km', RunPaceCalculator.fiveKMeters),
      ('10 km', RunPaceCalculator.tenKMeters),
      (loc.runPlanGoalHalf, RunPaceCalculator.halfMeters),
      (loc.runPlanGoalMarathon, RunPaceCalculator.marathonMeters),
    ];
    final paces = _previewPaces;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.runPlanCustomizePaceTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          loc.runPlanCustomizePaceHelp,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(loc.runPlanCustomizePaceSkip),
          value: _skipPace,
          onChanged: (v) => setState(() => _skipPace = v),
        ),
        if (!_skipPace) ...[
          const SizedBox(height: 8),
          SegmentedButton<_PaceSource>(
            segments: [
              ButtonSegment(
                value: _PaceSource.recent,
                label: Text(loc.runPlanCustomizePaceSourceRecent),
              ),
              ButtonSegment(
                value: _PaceSource.goal,
                label: Text(loc.runPlanCustomizePaceSourceGoal),
              ),
            ],
            selected: {_paceSource},
            onSelectionChanged: (s) => setState(() => _paceSource = s.first),
          ),
          const SizedBox(height: 16),
          Text(
            loc.runPlanCustomizePaceDistance,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in distances)
                ChoiceChip(
                  label: Text(entry.$1),
                  selected: (_paceDistanceMeters - entry.$2).abs() < 1,
                  onSelected: (_) =>
                      setState(() => _paceDistanceMeters = entry.$2),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _timeCtl,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              labelText: loc.runPlanCustomizePaceTime,
              hintText: loc.runPlanCustomizePaceTimeHint,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (paces != null) ...[
            const SizedBox(height: 16),
            Text(
              loc.runPlanCustomizePacePreview(
                RunPlanUi.paceLabel(paces.easySecPerKm),
                RunPlanUi.paceLabel(paces.tempoSecPerKm),
                RunPlanUi.paceLabel(paces.intervalSecPerKm),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              loc.runPlanCustomizePaceEstimateNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildPreviewStep(AppLocalizations loc, ThemeData theme) {
    final week = _weekPreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.runPlanCustomizePreviewTitle,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          loc.runPlanCustomizePreviewHelp,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        _buildWarnings(loc, theme, full: true),
        const SizedBox(height: 16),
        for (final session in week)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                RunPlanUi.kindIcon(session.kind),
                color: RunPlanUi.kindColor(theme.colorScheme, session.kind),
              ),
              title: Text(session.name),
              subtitle: Text(
                [
                  RunPlanUi.weekdayLabel(loc, session.dayOfWeek),
                  RunPlanUi.kindLabel(loc, session.kind),
                  if (session.targetDistanceMeters != null)
                    RunPlanUi.distanceLabel(session.targetDistanceMeters!),
                  if (session.targetPaceSecPerKm != null)
                    '${RunPlanUi.paceLabel(session.targetPaceSecPerKm)}/km',
                ].join(' · '),
              ),
            ),
          ),
      ],
    );
  }
}

enum _PaceSource { recent, goal }

class _OptionCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Parses `mm:ss` or `h:mm:ss` into total seconds.
int? _parseDuration(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length == 2) {
    final m = int.tryParse(parts[0]);
    final s = int.tryParse(parts[1]);
    if (m == null || s == null || s >= 60) return null;
    return m * 60 + s;
  }
  if (parts.length == 3) {
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = int.tryParse(parts[2]);
    if (h == null || m == null || s == null || m >= 60 || s >= 60) return null;
    return h * 3600 + m * 60 + s;
  }
  return int.tryParse(text);
}
