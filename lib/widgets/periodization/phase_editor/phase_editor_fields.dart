import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhaseNumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? suffix;
  final String? helper;
  final VoidCallback onChanged;
  final bool decimal;

  const PhaseNumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.suffix,
    this.helper,
    this.decimal = false,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: (_) => onChanged(),
    keyboardType: TextInputType.numberWithOptions(decimal: decimal),
    inputFormatters: [
      FilteringTextInputFormatter.allow(
        RegExp(decimal ? r'[0-9.,]' : r'[0-9]'),
      ),
    ],
    decoration: InputDecoration(
      labelText: label,
      suffixText: suffix,
      helperText: helper,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
  );
}

class PhasePickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const PhasePickerRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withAlpha(90),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
