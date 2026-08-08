import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/workout_card_helpers.dart';
import 'package:workout_notes/widgets/workout/stepper_button.dart';

/// Shared, purpose-built controls for editing the values of a workout set.
///
/// The database stores time as seconds, but the user edits it as a duration.
/// Weight and distance are rounded before they are sent back to the screen so
/// binary floating point artifacts cannot leak into the UI or persistence.
class WorkoutSetFieldControls extends StatelessWidget {
  final String exerciseType;
  final double weight;
  final int reps;
  final double distance;
  final int timeSeconds;
  final double weightIncrement;
  final bool showPace;
  final ValueChanged<double>? onWeightChanged;
  final ValueChanged<int>? onRepsChanged;
  final ValueChanged<double>? onDistanceChanged;
  final ValueChanged<int>? onTimeChanged;

  const WorkoutSetFieldControls({
    super.key,
    required this.exerciseType,
    required this.weight,
    required this.reps,
    required this.distance,
    required this.timeSeconds,
    this.weightIncrement = 1,
    this.showPace = false,
    this.onWeightChanged,
    this.onRepsChanged,
    this.onDistanceChanged,
    this.onTimeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fields = getFieldsForType(exerciseType).keys;
    final children = <Widget>[];
    var hasDistance = false;

    for (final field in fields) {
      switch (field) {
        case 'weight':
          children.add(_buildWeightControl(context));
        case 'reps':
          children.add(_buildRepsControl(context));
        case 'distance':
          hasDistance = true;
          children.add(_buildDistanceControl(context));
        case 'time_seconds':
          if (showPace && hasDistance && distance > 0 && timeSeconds > 0) {
            children.add(_buildPaceDisplay(context));
          }
          children.add(_buildTimeControl(context));
      }
    }

    return Column(children: children);
  }

  Widget _buildWeightControl(BuildContext context) {
    final primaryStep = _positiveStep(weightIncrement, fallback: 1);
    final fineStep = primaryStep <= 1
        ? primaryStep
        : primaryStep <= 2.5
        ? 0.5
        : 1.0;
    final loc = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          loc.activeWorkoutWeight,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            StepperButton(
              icon: Icons.remove,
              onTap: () => _emitWeight(weight - primaryStep),
            ),
            const SizedBox(width: 6),
            StepperButton(
              icon: Icons.remove,
              small: true,
              onTap: () => _emitWeight(weight - fineStep),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _valueButton(
                context,
                _formatDecimal(weight),
                onTap: () async {
                  final value = await _showDecimalEditor(
                    context,
                    title: 'Editar peso',
                    current: weight,
                    suffix: 'kg',
                    maxDecimals: 2,
                  );
                  if (value != null) _emitWeight(value);
                },
              ),
            ),
            const SizedBox(width: 8),
            StepperButton(
              icon: Icons.add,
              small: true,
              onTap: () => _emitWeight(weight + fineStep),
            ),
            const SizedBox(width: 6),
            StepperButton(
              icon: Icons.add,
              onTap: () => _emitWeight(weight + primaryStep),
            ),
          ],
        ),

        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [20, 30, 40, 50, 60, 80, 100, 120]
              .map(
                (value) => ActionChip(
                  label: Text('$value', style: const TextStyle(fontSize: 10)),
                  onPressed: () => _emitWeight(value.toDouble()),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildRepsControl(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          loc.activeWorkoutReps,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            StepperButton(icon: Icons.remove, onTap: () => _emitReps(reps - 1)),
            const SizedBox(width: 8),
            Expanded(
              child: _valueButton(
                context,
                '$reps',
                onTap: () async {
                  final value = await _showIntegerEditor(
                    context,
                    title: 'Editar repetições',
                    current: reps,
                    suffix: 'reps',
                  );
                  if (value != null) _emitReps(value);
                },
              ),
            ),
            const SizedBox(width: 8),
            StepperButton(icon: Icons.add, onTap: () => _emitReps(reps + 1)),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [1, 3, 5, 8, 10, 12, 15, 20]
              .map(
                (value) => ActionChip(
                  label: Text('$value', style: const TextStyle(fontSize: 10)),
                  onPressed: () => _emitReps(value),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildDistanceControl(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          loc.activeWorkoutDistance,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            StepperButton(
              icon: Icons.remove,
              small: true,
              onTap: () => _emitDistance(distance - 0.1),
            ),
            const SizedBox(width: 6),
            StepperButton(
              icon: Icons.remove,
              onTap: () => _emitDistance(distance - 0.5),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _valueButton(
                context,
                '${_formatDecimal(distance)} km',
                onTap: () async {
                  final value = await _showDecimalEditor(
                    context,
                    title: 'Editar distância',
                    current: distance,
                    suffix: 'km',
                    maxDecimals: 2,
                  );
                  if (value != null) _emitDistance(value);
                },
              ),
            ),
            const SizedBox(width: 8),
            StepperButton(
              icon: Icons.add,
              onTap: () => _emitDistance(distance + 0.5),
            ),
            const SizedBox(width: 6),
            StepperButton(
              icon: Icons.add,
              small: true,
              onTap: () => _emitDistance(distance + 0.1),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [1.0, 2.0, 3.0, 5.0, 10.0]
              .map(
                (value) => ActionChip(
                  label: Text(
                    '${_formatDecimal(value)} km',
                    style: const TextStyle(fontSize: 10),
                  ),
                  onPressed: () => _emitDistance(value),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildTimeControl(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          loc.activeWorkoutTime,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            StepperButton(
              icon: Icons.remove,
              onTap: () => _emitTime(timeSeconds - 60),
            ),
            const SizedBox(width: 6),
            StepperButton(
              icon: Icons.remove,
              small: true,
              onTap: () => _emitTime(timeSeconds - 5),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _valueButton(
                context,
                _formatDuration(timeSeconds),
                onTap: () async {
                  final value = await _showDurationPicker(context, timeSeconds);
                  if (value != null) _emitTime(value);
                },
              ),
            ),
            const SizedBox(width: 8),
            StepperButton(
              icon: Icons.add,
              small: true,
              onTap: () => _emitTime(timeSeconds + 5),
            ),
            const SizedBox(width: 6),
            StepperButton(
              icon: Icons.add,
              onTap: () => _emitTime(timeSeconds + 60),
            ),
          ],
        ),

        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [30, 60, 120, 300, 600, 1200, 1800, 2700, 3600]
              .map(
                (value) => ActionChip(
                  label: Text(
                    _formatDuration(value),
                    style: const TextStyle(fontSize: 10),
                  ),
                  onPressed: () => _emitTime(value),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildPaceDisplay(BuildContext context) {
    final pace = timeSeconds / distance;
    final minutes = pace ~/ 60;
    final seconds = pace.round() % 60;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935).withAlpha(15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.speed, size: 16, color: Color(0xFFE53935)),
            const SizedBox(width: 6),
            Text(
              'Pace: $minutes:${seconds.toString().padLeft(2, '0')} /km',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFFE53935),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _valueButton(
    BuildContext context,
    String value, {
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _emitWeight(double value) {
    onWeightChanged?.call(_clampDecimal(value, max: 999));
  }

  void _emitReps(int value) {
    onRepsChanged?.call(value.clamp(0, 999));
  }

  void _emitDistance(double value) {
    onDistanceChanged?.call(_clampDecimal(value, max: 999));
  }

  void _emitTime(int value) {
    onTimeChanged?.call(value.clamp(0, 86399));
  }

  Future<double?> _showDecimalEditor(
    BuildContext context, {
    required String title,
    required double current,
    required String suffix,
    required int maxDecimals,
  }) async {
    final controller = TextEditingController(
      text: _formatDecimal(current, decimals: maxDecimals),
    );
    return showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_DecimalInputFormatter(maxDecimals: maxDecimals)],
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            suffixText: suffix,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(
                controller.text.replaceAll(',', '.'),
              );
              if (parsed != null && parsed.isFinite && parsed >= 0) {
                Navigator.pop(
                  dialogContext,
                  _roundDecimal(parsed, maxDecimals),
                );
              }
            },
            child: Text(AppLocalizations.of(context)!.commonSave),
          ),
        ],
      ),
    );
  }

  Future<int?> _showIntegerEditor(
    BuildContext context, {
    required String title,
    required int current,
    required String suffix,
  }) async {
    final controller = TextEditingController(text: '$current');
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            suffixText: suffix,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text);
              if (parsed != null) {
                Navigator.pop(dialogContext, parsed.clamp(0, 999));
              }
            },
            child: Text(AppLocalizations.of(context)!.commonSave),
          ),
        ],
      ),
    );
  }

  Future<int?> _showDurationPicker(BuildContext context, int current) async {
    var selected = Duration(seconds: current.clamp(0, 86399));
    return showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Editar tempo',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text(AppLocalizations.of(context)!.commonCancel),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(sheetContext, selected.inSeconds),
                    child: Text(AppLocalizations.of(context)!.commonSave),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 190,
              child: CupertinoTimerPicker(
                mode: CupertinoTimerPickerMode.hms,
                initialTimerDuration: selected,
                minuteInterval: 1,
                secondInterval: 1,
                onTimerDurationChanged: (value) => selected = value,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _positiveStep(double value, {required double fallback}) {
    return value.isFinite && value > 0 ? _roundDecimal(value, 2) : fallback;
  }

  static double _clampDecimal(double value, {required double max}) {
    if (!value.isFinite) return 0;
    return _roundDecimal(value.clamp(0, max), 2);
  }

  static double _roundDecimal(double value, int decimals) {
    final fixed = value.toStringAsFixed(decimals);
    return double.tryParse(fixed) ?? 0;
  }

  static String _formatDecimal(double value, {int decimals = 2}) {
    final rounded = _roundDecimal(value, decimals);
    return rounded
        .toStringAsFixed(decimals)
        .replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _formatDuration(int seconds) {
    if (seconds <= 0) return '0 s';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
    if (minutes > 0) {
      return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
    }
    return '$seconds s';
  }
}

class _DecimalInputFormatter extends TextInputFormatter {
  final int maxDecimals;

  _DecimalInputFormatter({required this.maxDecimals});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '.');
    final pattern = RegExp('^\\d{0,3}(?:\\.\\d{0,$maxDecimals})?');
    final match = pattern.matchAsPrefix(text);
    return match != null && match.end == text.length ? newValue : oldValue;
  }
}
