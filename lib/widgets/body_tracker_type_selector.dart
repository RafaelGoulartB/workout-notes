import 'package:flutter/material.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';

/// Horizontal scrollable row of ChoiceChips for selecting measurement type.
class BodyTypeSelector extends StatelessWidget {
  final List<MeasureType> types;
  final String selectedType;
  final ValueChanged<String> onSelected;

  const BodyTypeSelector({
    super.key,
    required this.types,
    required this.selectedType,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: types.map((t) {
            final isSelected = selectedType == t.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(
                  t.icon,
                  size: 16,
                  color: isSelected
                      ? t.color
                      : theme.colorScheme.onSurfaceVariant,
                ),
                label: Text(typeName(t.id, context)),
                selected: isSelected,
                selectedColor: t.color.withAlpha(25),
                onSelected: (_) => onSelected(t.id),
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected
                        ? t.color.withAlpha(80)
                        : theme.colorScheme.outlineVariant.withAlpha(40),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
