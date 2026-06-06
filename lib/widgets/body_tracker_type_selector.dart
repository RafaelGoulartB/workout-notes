import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';

/// Dropdown-style selector that opens a bottom sheet grid of all types.
/// Much more scalable than horizontal scrolling — works with any number of types.
class BodyTypeSelector extends StatelessWidget {
  final List<MeasureType> types;
  final String selectedType;
  final ValueChanged<String> onSelected;
  final Map<String, Map<String, dynamic>?>? latestByType;
  final List<MeasureType>? allTypes;
  final ValueChanged<List<MeasureType>>? onCustomize;

  const BodyTypeSelector({
    super.key,
    required this.types,
    required this.selectedType,
    required this.onSelected,
    this.latestByType,
    this.allTypes,
    this.onCustomize,
  });

  MeasureType get _current =>
      types.firstWhere((t) => t.id == selectedType);

  double? _latestValue(String typeId) {
    final entry = latestByType?[typeId];
    if (entry == null) return null;
    return (entry['value'] as num?)?.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = _current;
    final value = _latestValue(selectedType);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openPicker(context),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surface,
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withAlpha(100),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Current type icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: type.color.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(type.icon, size: 22, color: type.color),
              ),
              const SizedBox(width: 14),

              // Type name + latest value
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      typeName(type.id, context),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (value != null)
                      Text(
                        '${value.toStringAsFixed(1)} ${type.unit}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),

              // Arrow + chevron
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: type.color.withAlpha(15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      type.unit,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: type.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPicker(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
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
              const SizedBox(height: 16),

              // Title
              Text(
                'Selecionar Medida',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Grid of types
              _buildGrid(ctx, theme, loc),

              // Customize button
              if (allTypes != null) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showCustomizeSheet(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withAlpha(60),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.tune,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Personalizar',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showCustomizeSheet(BuildContext context) {
    final theme = Theme.of(context);
    final all = allTypes!;
    final loc = AppLocalizations.of(context)!;

    // Build list of enabled/disabled state from current types
    final currentIds = types.map((t) => t.id).toSet();
    final enabled = <String, bool>{};
    for (final t in all) {
      enabled[t.id] = currentIds.contains(t.id);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                  const SizedBox(height: 16),
                  Text(
                    'Personalizar Medidas',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Selecione as medidas que quer acompanhar',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: all.map((t) {
                        final isOn = enabled[t.id] ?? true;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SwitchListTile(
                            value: isOn,
                            onChanged: (v) {
                              setSheetState(() => enabled[t.id] = v);
                            },
                            secondary: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: t.color.withAlpha(20),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(t.icon, size: 20, color: t.color),
                            ),
                            title: Text(
                              typeName(t.id, context),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              t.isBilateral
                                  ? '${loc.bodyTrackerLeft} / ${loc.bodyTrackerRight}'
                                  : t.unit,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () {
                        final result = all
                            .where((t) => enabled[t.id] == true)
                            .toList();
                        Navigator.pop(ctx);
                        onCustomize?.call(result);
                      },
                      child: const Text('Salvar'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGrid(BuildContext context, ThemeData theme, AppLocalizations loc) {
    const crossAxisCount = 4;
    final rowCount = (types.length / crossAxisCount).ceil();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(rowCount, (row) {
        final start = row * crossAxisCount;
        final end = (start + crossAxisCount).clamp(0, types.length);
        final itemsInRow = end - start;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              // Real items
              for (int col = 0; col < crossAxisCount; col++) ...[
                if (col < itemsInRow) ...[
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: col > 0 ? 8 : 0),
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: _TypeGridItem(
                          type: types[start + col],
                          isSelected: types[start + col].id == selectedType,
                          latestValue: _latestValue(types[start + col].id),
                          onTap: () {
                            onSelected(types[start + col].id);
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // Placeholder to keep same column widths
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: col > 0 ? 8 : 0),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      }),
    );
  }
}

/// Single square item in the measurement type grid.
class _TypeGridItem extends StatelessWidget {
  final MeasureType type;
  final bool isSelected;
  final double? latestValue;
  final VoidCallback onTap;

  const _TypeGridItem({
    required this.type,
    required this.isSelected,
    required this.latestValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isSelected
              ? type.color.withAlpha(18)
              : theme.colorScheme.surfaceContainerHighest.withAlpha(60),
          border: Border.all(
            color: isSelected
                ? type.color.withAlpha(100)
                : theme.colorScheme.outlineVariant.withAlpha(40),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type.icon,
              size: 26,
              color: isSelected ? type.color : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              _shortName(context),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 11,
                color: isSelected
                    ? type.color
                    : theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (latestValue != null) ...[
              const SizedBox(height: 1),
              Text(
                latestValue!.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? type.color
                      : theme.colorScheme.onSurface.withAlpha(160),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Short label for the grid item (first meaningful word).
  String _shortName(BuildContext context) {
    final full = typeName(type.id, context);
    // Handle compound English names
    if (full.startsWith('Body ')) return full.split(' ').last;
    if (full.startsWith('% ')) return full.split(' ').first;
    // Single-word names: just use as-is (works for both languages)
    if (!full.contains(' ')) return full;
    // Multi-word: use first word (e.g. "Peso Corporal" -> "Peso")
    return full.split(' ').first;
  }
}
