import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A circular stepper button with icon, used for increment/decrement actions.
class StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool small;

  const StepperButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.small = false,
  });

  void _handleTap() {
    HapticFeedback.lightImpact();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = small ? 36.0 : 48.0;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(120)),
          ),
          child: Icon(icon, size: small ? 18 : 24, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}
