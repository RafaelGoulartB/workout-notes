import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';
import 'package:workout_notes/widgets/body_tracker_badges.dart';
import 'package:workout_notes/widgets/body_tracker_selectors.dart';

// ═══════════════════════════════════════════════════════════════════════
// ADD MEASUREMENT SHEET
// ═══════════════════════════════════════════════════════════════════════

/// Shows a bottom sheet for adding a single measurement.
Future<void> showAddMeasurementSheet(
  BuildContext context, {
  required BodyMeasurementRepository repo,
  required MeasureType currentType,
  required String typeId,
  required VoidCallback onSaved,
}) async {
  final valueCtl = TextEditingController();
  final secondaryValueCtl = TextEditingController();
  final commentCtl = TextEditingController();
  var date = DateTime.now();
  String? timeOfDay;
  bool isFasted = false;
  String? side;
  final formKey = GlobalKey<FormState>();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final loc = AppLocalizations.of(ctx)!;
      final unit = currentType.unit;
      final isBloodPressure = typeId == 'bloodPressure';

      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(
                            60,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: currentType.color.withAlpha(20),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            currentType.icon,
                            size: 24,
                            color: currentType.color,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            loc.bodyTrackerAddTitle(typeName(typeId, ctx)),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: valueCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      autofocus: true,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: isBloodPressure
                            ? loc.bodyTrackerSystolic
                            : null,
                        hintText: '0.0',
                        suffixText: ' $unit',
                        suffixStyle: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(80),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 16,
                        ),
                      ),
                      validator: (v) {
                        final val = double.tryParse(
                          v?.replaceAll(',', '.') ?? '',
                        );
                        if (val == null || val <= 0) {
                          return loc.bodyTrackerInvalidValue;
                        }
                        return null;
                      },
                    ),
                    if (isBloodPressure) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: secondaryValueCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: loc.bodyTrackerDiastolic,
                          hintText: '0',
                          suffixText: ' $unit',
                          suffixStyle: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withAlpha(80),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 20,
                            horizontal: 16,
                          ),
                        ),
                        validator: (v) {
                          final val = double.tryParse(
                            v?.replaceAll(',', '.') ?? '',
                          );
                          if (val == null || val <= 0) {
                            return loc.bodyTrackerInvalidValue;
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: date,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setSheetState(() => date = picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant
                                      .withAlpha(100),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 18,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat(
                                      'd MMM yyyy',
                                      'pt_BR',
                                    ).format(date),
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TimeOfDaySelector(
                            value: timeOfDay,
                            onChanged: (v) =>
                                setSheetState(() => timeOfDay = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilterChip(
                            avatar: Icon(
                              Icons.nightlight_round,
                              size: 16,
                              color: isFasted
                                  ? Colors.deepPurple
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            label: Text(loc.bodyTrackerFasting),
                            selected: isFasted,
                            onSelected: (v) =>
                                setSheetState(() => isFasted = v),
                            selectedColor: Colors.deepPurple.withAlpha(30),
                            checkmarkColor: Colors.deepPurple,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Side selector for bilateral types
                    if (currentType.isBilateral) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SideSelector(
                              value: side,
                              onChanged: (v) => setSheetState(() => side = v),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 12),
                    TextFormField(
                      controller: commentCtl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: loc.bodyTrackerComment,
                        prefixIcon: Icon(
                          Icons.notes,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          final value = double.tryParse(
                            valueCtl.text.replaceAll(',', '.'),
                          );
                          if (value == null || value <= 0) return;
                          final secondaryValue = isBloodPressure
                              ? double.tryParse(
                                  secondaryValueCtl.text.replaceAll(',', '.'),
                                )
                              : null;
                          if (isBloodPressure &&
                              (secondaryValue == null || secondaryValue <= 0)) {
                            return;
                          }
                          await repo.addBodyMeasurement(
                            typeId,
                            value,
                            currentType.unit,
                            secondaryValue: secondaryValue,
                            date: date,
                            comment: commentCtl.text.isNotEmpty
                                ? commentCtl.text
                                : null,
                            timeOfDay: timeOfDay,
                            isFasted: isFasted,
                            side: side,
                          );
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(loc.bodyTrackerSaved),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                          onSaved();
                        },
                        icon: const Icon(Icons.check),
                        label: Text(
                          loc.bodyTrackerSave,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

// ═══════════════════════════════════════════════════════════════════════
// QUICK MEASURE SHEET (all types at once)
// ═══════════════════════════════════════════════════════════════════════

/// Shows a bottom sheet for quickly entering measurements for all types.
Future<void> showQuickMeasureSheet(
  BuildContext context, {
  required BodyMeasurementRepository repo,
  required List<MeasureType> types,
  required Map<String, Map<String, dynamic>?> latestByType,
  required VoidCallback onSaved,
}) async {
  final controllers = <String, TextEditingController>{};
  final hasValue = <String, bool>{};
  for (final t in types) {
    if (t.id == 'bloodPressure') {
      controllers['${t.id}_systolic'] = TextEditingController();
      controllers['${t.id}_diastolic'] = TextEditingController();
      hasValue['${t.id}_systolic'] = false;
      hasValue['${t.id}_diastolic'] = false;
    } else if (t.isBilateral) {
      controllers['${t.id}_left'] = TextEditingController();
      controllers['${t.id}_right'] = TextEditingController();
      hasValue['${t.id}_left'] = false;
      hasValue['${t.id}_right'] = false;
    } else {
      controllers[t.id] = TextEditingController();
      hasValue[t.id] = false;
    }
  }
  var date = DateTime.now();
  String? timeOfDay;
  bool isFasted = false;
  final commentCtl = TextEditingController();

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final loc = AppLocalizations.of(ctx)!;
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          final anyFilled = hasValue.values.any((v) => v);
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (ctx, scrollController) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withAlpha(
                            60,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.bolt,
                            size: 22,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                loc.bodyTrackerQuickMeasure,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                loc.bodyTrackerQuickMeasureSubtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: date,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setSheetState(() => date = picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant
                                      .withAlpha(100),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      DateFormat(
                                        'd MMM yyyy',
                                        'pt_BR',
                                      ).format(date),
                                      style: theme.textTheme.bodySmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          avatar: Icon(
                            Icons.nightlight_round,
                            size: 14,
                            color: isFasted
                                ? Colors.deepPurple
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          label: Text(
                            loc.bodyTrackerFasted,
                            style: TextStyle(fontSize: 12),
                          ),
                          selected: isFasted,
                          onSelected: (v) => setSheetState(() => isFasted = v),
                          selectedColor: Colors.deepPurple.withAlpha(30),
                          checkmarkColor: Colors.deepPurple,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    QuickTimeOfDaySelector(
                      value: timeOfDay,
                      onChanged: (v) => setSheetState(() => timeOfDay = v),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        children: _buildQuickMeasureFields(
                          ctx,
                          theme,
                          controllers,
                          hasValue,
                          setSheetState,
                          types,
                          latestByType,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: commentCtl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: loc.bodyTrackerQuickCommentHint,
                        prefixIcon: Icon(
                          Icons.notes,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: anyFilled
                            ? () async {
                                final batch = <Map<String, dynamic>>[];
                                for (final t in types) {
                                  if (t.id == 'bloodPressure') {
                                    final systolic = double.tryParse(
                                      controllers['${t.id}_systolic']!.text
                                          .replaceAll(',', '.'),
                                    );
                                    final diastolic = double.tryParse(
                                      controllers['${t.id}_diastolic']!.text
                                          .replaceAll(',', '.'),
                                    );
                                    if (systolic == null ||
                                        systolic <= 0 ||
                                        diastolic == null ||
                                        diastolic <= 0) {
                                      continue;
                                    }
                                    batch.add({
                                      'type': t.id,
                                      'value': systolic,
                                      'secondary_value': diastolic,
                                      'unit': t.unit,
                                      'date': date.toIso8601String().substring(
                                        0,
                                        10,
                                      ),
                                      'comment': commentCtl.text.isNotEmpty
                                          ? commentCtl.text
                                          : null,
                                      'time_of_day': timeOfDay,
                                      'is_fasted': isFasted,
                                    });
                                  } else if (t.isBilateral) {
                                    for (final side in ['left', 'right']) {
                                      final key = '${t.id}_$side';
                                      final txt = controllers[key]!.text;
                                      if (txt.isEmpty) continue;
                                      final val = double.tryParse(
                                        txt.replaceAll(',', '.'),
                                      );
                                      if (val == null || val <= 0) continue;
                                      batch.add({
                                        'type': t.id,
                                        'value': val,
                                        'unit': t.unit,
                                        'date': date
                                            .toIso8601String()
                                            .substring(0, 10),
                                        'comment': commentCtl.text.isNotEmpty
                                            ? commentCtl.text
                                            : null,
                                        'time_of_day': timeOfDay,
                                        'is_fasted': isFasted,
                                        'side': side,
                                      });
                                    }
                                  } else {
                                    final txt = controllers[t.id]!.text;
                                    if (txt.isEmpty) continue;
                                    final val = double.tryParse(
                                      txt.replaceAll(',', '.'),
                                    );
                                    if (val == null || val <= 0) continue;
                                    batch.add({
                                      'type': t.id,
                                      'value': val,
                                      'unit': t.unit,
                                      'date': date.toIso8601String().substring(
                                        0,
                                        10,
                                      ),
                                      'comment': commentCtl.text.isNotEmpty
                                          ? commentCtl.text
                                          : null,
                                      'time_of_day': timeOfDay,
                                      'is_fasted': isFasted,
                                    });
                                  }
                                }
                                if (batch.isNotEmpty) {
                                  await repo.addBodyMeasurementsBatch(batch);
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          loc.bodyTrackerSavedBatch(
                                            batch.length,
                                          ),
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  onSaved();
                                }
                              }
                            : null,
                        icon: const Icon(Icons.save),
                        label: Text(
                          loc.bodyTrackerSaveAll,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}

/// Builds the list of quick-measure fields for all measurement types.
List<Widget> _buildQuickMeasureFields(
  BuildContext context,
  ThemeData theme,
  Map<String, TextEditingController> controllers,
  Map<String, bool> hasValue,
  void Function(VoidCallback) setSheetState,
  List<MeasureType> types,
  Map<String, Map<String, dynamic>?> latestByType,
) {
  final loc = AppLocalizations.of(context)!;
  final items = <Widget>[];
  for (final t in types) {
    if (t.id == 'bloodPressure') {
      for (final part in ['systolic', 'diastolic']) {
        final key = '${t.id}_$part';
        final ctl = controllers[key]!;
        items.add(
          _buildQuickMeasureField(
            theme: theme,
            loc: loc,
            type: t,
            label: part == 'systolic'
                ? loc.bodyTrackerSystolic
                : loc.bodyTrackerDiastolic,
            controller: ctl,
            isFilled: hasValue[key] == true,
            latest: latestByType[t.id],
            onChanged: (v) => setSheetState(() => hasValue[key] = v),
          ),
        );
      }
    } else if (t.isBilateral) {
      for (final side in ['left', 'right']) {
        final key = '${t.id}_$side';
        final ctl = controllers[key]!;
        items.add(
          _buildQuickMeasureField(
            theme: theme,
            loc: loc,
            type: t,
            label:
                '${_typeLabel(t.id, context)} ${side == 'left' ? loc.bodyTrackerLeftAbbr : loc.bodyTrackerRightAbbr}.',
            controller: ctl,
            isFilled: hasValue[key] == true,
            latest: latestByType[t.id],
            onChanged: (v) => setSheetState(() => hasValue[key] = v),
          ),
        );
      }
    } else {
      final ctl = controllers[t.id]!;
      items.add(
        _buildQuickMeasureField(
          theme: theme,
          loc: loc,
          type: t,
          label: _typeLabel(t.id, context),
          controller: ctl,
          isFilled: hasValue[t.id] == true,
          latest: latestByType[t.id],
          onChanged: (v) => setSheetState(() => hasValue[t.id] = v),
        ),
      );
    }
  }
  return items;
}

/// Builds a single quick-measure field row.
Widget _buildQuickMeasureField({
  required ThemeData theme,
  required AppLocalizations loc,
  required MeasureType type,
  required String label,
  required TextEditingController controller,
  required bool isFilled,
  required Map<String, dynamic>? latest,
  required ValueChanged<bool> onChanged,
}) {
  final latestVal = latest != null
      ? formatMeasurementValue(latest, type)
      : null;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFilled
              ? type.color.withAlpha(80)
              : theme.colorScheme.outlineVariant.withAlpha(40),
        ),
        color: isFilled ? type.color.withAlpha(10) : null,
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: type.color.withAlpha(22),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(type.icon, size: 18, color: type.color),
        ),
        title: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: isFilled ? type.color : null,
          ),
        ),
        subtitle: latestVal != null
            ? Text(
                '${loc.bodyTrackerLastLabel}$latestVal',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
                ),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        trailing: SizedBox(
          width: 80,
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.end,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isFilled ? type.color : theme.colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
              ),
              suffixText: isFilled ? ' ${type.unit}' : null,
              suffixStyle: TextStyle(color: type.color, fontSize: 11),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (v) => onChanged(v.isNotEmpty),
          ),
        ),
      ),
    ),
  );
}

/// Convenience wrapper for accessing typeName with a local context.
String _typeLabel(String typeId, BuildContext context) {
  return typeName(typeId, context);
}

// ═══════════════════════════════════════════════════════════════════════
// MEASUREMENT DETAIL SHEET
// ═══════════════════════════════════════════════════════════════════════

/// Shows a bottom sheet with full details for a single measurement.
Future<void> showMeasurementDetailSheet(
  BuildContext context, {
  required Map<String, dynamic> measurement,
  required MeasureType type,
  required String typeId,
  required double? delta,
  required BodyMeasurementRepository repo,
  required VoidCallback onDeleted,
}) async {
  final theme = Theme.of(context);
  final loc = AppLocalizations.of(context)!;

  final date = measurement['date'] as String? ?? '';
  final comment = measurement['comment'] as String?;
  final timeOfDay = measurement['time_of_day'] as String?;
  final isFasted = (measurement['is_fasted'] as int?) == 1;
  final side = measurement['side'] as String?;

  await showModalBottomSheet(
    context: context,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(60),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: type.color.withAlpha(22),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(type.icon, size: 28, color: type.color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        typeName(typeId, context),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        formatDate(date),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  type.id == 'bloodPressure'
                      ? formatMeasurementValue(measurement, type)
                      : ((measurement['value'] as num).toDouble())
                            .toStringAsFixed(1),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -1,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (type.id != 'bloodPressure') ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      type.unit,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (delta != null && delta != 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    delta > 0 ? Icons.trending_up : Icons.trending_down,
                    size: 16,
                    color: delta > 0 ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} ${type.unit}',
                    style: TextStyle(
                      fontSize: 13,
                      color: delta > 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (side != null || timeOfDay != null || isFasted)
              Wrap(
                spacing: 8,
                children: [
                  if (side != null && type.isBilateral)
                    SideChip(side: side, theme: theme),
                  if (timeOfDay != null && timeOfDay.isNotEmpty)
                    TimeOfDayChip(tod: timeOfDay, theme: theme),
                  if (isFasted) FastedChip(theme: theme),
                ],
              ),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(
                    100,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notes,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(comment)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text(loc.bodyTrackerDeleteConfirm),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: Text(loc.commonCancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: Text(
                              loc.commonDelete,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await repo.deleteBodyMeasurement(
                        measurement['id'] as String,
                      );
                      onDeleted();
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(loc.commonDelete),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
