import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_data_field.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/utils/run_data_field_values.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

String runDataFieldLabel(AppLocalizations loc, RunDataField field) =>
    switch (field) {
      RunDataField.time => loc.runFieldTime,
      RunDataField.distance => loc.runFieldDistance,
      RunDataField.pace => loc.runFieldPace,
      RunDataField.avgPace => loc.runFieldAvgPace,
      RunDataField.kmPace => loc.runFieldKmPace,
      RunDataField.lapTime => loc.runFieldLapTime,
      RunDataField.lapDistance => loc.runFieldLapDistance,
      RunDataField.calories => loc.runFieldCalories,
      RunDataField.clock => loc.runFieldClock,
    };

/// The live numbers of a recording: 3 to 6 user-picked fields in a clean 2 or
/// 3 column grid. Long-pressing a cell swaps that field; [onCustomize] opens
/// the full editor.
class RunDataFieldsGrid extends StatelessWidget {
  final List<RunDataField> fields;
  final RunTrackingState state;
  final CardioActivityType activityType;
  final double bodyWeightKg;
  final DateTime now;

  /// Called with the index of the long-pressed cell; null disables swapping.
  final ValueChanged<int>? onFieldLongPress;
  final VoidCallback? onCustomize;

  const RunDataFieldsGrid({
    super.key,
    required this.fields,
    required this.state,
    required this.activityType,
    required this.now,
    this.bodyWeightKg = 70,
    this.onFieldLongPress,
    this.onCustomize,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final rows = RunDataFieldLayout.rowsFor(fields.length);
    var index = 0;
    final children = <Widget>[];
    for (var r = 0; r < rows.length; r++) {
      final columns = rows[r];
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        final i = index++;
        if (c > 0) {
          cells.add(_VerticalDivider(color: AppUi.divider(theme.colorScheme)));
        }
        cells.add(
          Expanded(
            child: _FieldCell(
              key: ValueKey('run-data-field-${fields[i].storageValue}'),
              label: runDataFieldLabel(loc, fields[i]),
              value: RunDataFieldValues.of(
                fields[i],
                state: state,
                now: now,
                activityType: activityType,
                bodyWeightKg: bodyWeightKg,
                use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
              ),
              // Two big cells per row read from an arm's length; three need
              // a smaller numeral to fit 360 dp.
              large: columns <= 2,
              dimmed: state.isAutoPaused || state.isPaused,
              onLongPress: onFieldLongPress == null
                  ? null
                  : () => onFieldLongPress!(i),
            ),
          ),
        );
      }
      if (r > 0) {
        children.add(
          Divider(height: 1, color: AppUi.divider(theme.colorScheme)),
        );
      }
      children.add(IntrinsicHeight(child: Row(children: cells)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...children,
        if (onCustomize != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('run-data-fields-customize'),
              onPressed: onCustomize,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                textStyle: theme.textTheme.labelMedium,
              ),
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: Text(loc.runFieldCustomize),
            ),
          ),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  final Color color;

  const _VerticalDivider({required this.color});

  @override
  Widget build(BuildContext context) =>
      VerticalDivider(width: 1, thickness: 1, color: color);
}

class _FieldCell extends StatelessWidget {
  final String label;
  final RunDataValue value;
  final bool large;
  final bool dimmed;
  final VoidCallback? onLongPress;

  const _FieldCell({
    super.key,
    required this.label,
    required this.value,
    required this.large,
    required this.dimmed,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final valueStyle =
        (large ? theme.textTheme.displaySmall : theme.textTheme.headlineMedium)
            ?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.05,
              fontFeatures: AppUi.tabular,
              color: dimmed ? colors.onSurfaceVariant : colors.onSurface,
            );
    return Semantics(
      label: '$label ${value.value} ${value.unit ?? ''}'.trim(),
      child: InkWell(
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: large ? 12 : 10,
            horizontal: 4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value.value, style: valueStyle),
              ),
              SizedBox(
                height: 16,
                child: value.unit == null
                    ? null
                    : Text(
                        value.unit!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet to choose, remove and reorder the live fields. Every change
/// is reported through [onChanged] immediately, so closing the sheet by
/// swiping never loses an edit.
Future<void> showRunDataFieldsSheet(
  BuildContext context, {
  required List<RunDataField> initial,
  required ValueChanged<List<RunDataField>> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _FieldsEditor(initial: initial, onChanged: onChanged),
  );
}

class _FieldsEditor extends StatefulWidget {
  final List<RunDataField> initial;
  final ValueChanged<List<RunDataField>> onChanged;

  const _FieldsEditor({required this.initial, required this.onChanged});

  @override
  State<_FieldsEditor> createState() => _FieldsEditorState();
}

class _FieldsEditorState extends State<_FieldsEditor> {
  late List<RunDataField> _fields = List.of(widget.initial);

  void _update(List<RunDataField> next) {
    setState(() => _fields = next);
    widget.onChanged(List.unmodifiable(next));
  }

  void _remove(RunDataField field) {
    if (_fields.length <= RunDataFieldLayout.minFields) {
      _hint(
        AppLocalizations.of(
          context,
        )!.runFieldMinReached(RunDataFieldLayout.minFields),
      );
      return;
    }
    _update([..._fields]..remove(field));
  }

  void _add(RunDataField field) {
    if (_fields.length >= RunDataFieldLayout.maxFields) {
      _hint(
        AppLocalizations.of(
          context,
        )!.runFieldMaxReached(RunDataFieldLayout.maxFields),
      );
      return;
    }
    _update([..._fields, field]);
  }

  void _hint(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final available = [
      for (final field in RunDataField.values)
        if (!_fields.contains(field)) field,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              loc.runFieldSheetTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              loc.runFieldSheetHint(
                RunDataFieldLayout.minFields,
                RunDataFieldLayout.maxFields,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            AppSectionHeader(
              loc.runFieldVisible,
              padding: const EdgeInsets.fromLTRB(4, 16, 0, 6),
            ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) {
                final next = [..._fields];
                next.insert(to, next.removeAt(from));
                _update(next);
              },
              children: [
                for (var i = 0; i < _fields.length; i++)
                  ListTile(
                    key: ValueKey('field-${_fields[i].storageValue}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_indicator_rounded),
                    ),
                    title: Text(runDataFieldLabel(loc, _fields[i])),
                    trailing: IconButton(
                      tooltip: loc.commonRemove,
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                      onPressed: () => _remove(_fields[i]),
                    ),
                  ),
              ],
            ),
            if (available.isNotEmpty) ...[
              AppSectionHeader(
                loc.runFieldAvailable,
                padding: const EdgeInsets.fromLTRB(4, 12, 0, 6),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final field in available)
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 18),
                      label: Text(runDataFieldLabel(loc, field)),
                      onPressed: () => _add(field),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: TextButton(
                    onPressed: () =>
                        _update(List.of(RunDataFieldLayout.defaults)),
                    child: Text(
                      loc.runFieldRestoreDefault,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(loc.runFieldDone),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks the field that replaces [replacing] (long-press on a grid cell).
Future<RunDataField?> showRunDataFieldPicker(
  BuildContext context, {
  required RunDataField replacing,
  required List<RunDataField> current,
}) {
  final loc = AppLocalizations.of(context)!;
  final options = [
    for (final field in RunDataField.values)
      if (!current.contains(field)) field,
  ];
  return showModalBottomSheet<RunDataField>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                loc.runFieldReplaceTitle(runDataFieldLabel(loc, replacing)),
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          for (final field in options)
            ListTile(
              title: Text(runDataFieldLabel(loc, field)),
              onTap: () => Navigator.pop(ctx, field),
            ),
        ],
      ),
    ),
  );
}
