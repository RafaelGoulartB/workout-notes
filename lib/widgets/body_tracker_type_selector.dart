import 'package:flutter/material.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';

/// Dropdown-style selector that opens a bottom sheet grid of all types.
/// Much more scalable than horizontal scrolling — works with any number of types.
class BodyTypeSelector extends StatelessWidget {
  final List<MeasureType> types;
  final String selectedType;
  final ValueChanged<String> onSelected;
  final Map<String, Map<String, dynamic>?>? latestByType;

  const BodyTypeSelector({
    super.key,
    required this.types,
    required this.selectedType,
    required this.onSelected,
    this.latestByType,
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
              _buildGrid(ctx, theme),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGrid(BuildContext context, ThemeData theme) {
    const crossAxisCount = 4;
    final rowCount = (types.length / crossAxisCount).ceil();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(rowCount, (row) {
        final start = row * crossAxisCount;
        final end = (start + crossAxisCount).clamp(0, types.length);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: List.generate(end - start, (col) {
              final t = types[start + col];
              final isSelected = t.id == selectedType;
              final value = _latestValue(t.id);

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: col > 0 ? 8 : 0,
                  ),
                  child: _TypeGridItem(
                    type: t,
                    isSelected: isSelected,
                    latestValue: value,
                    onTap: () {
                      onSelected(t.id);
                      Navigator.pop(context);
                    },
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

/// Single item in the measurement type grid.
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
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              type.icon,
              size: 24,
              color: isSelected ? type.color : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              typeName(type.id, context).split(' ').first,
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
              const SizedBox(height: 2),
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
}
