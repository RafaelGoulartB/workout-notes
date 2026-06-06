import 'package:flutter/material.dart';

/// Represents a body measurement type (e.g., weight, body fat, waist).
class MeasureType {
  final String id;
  final IconData icon;
  final String unit;
  final Color color;
  final bool isBilateral;

  const MeasureType(
    this.id,
    this.icon,
    this.unit,
    this.color,
    this.isBilateral,
  );
}

/// Represents a derived statistic shown in the body tracker dashboard.
class DerivedStat {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const DerivedStat(
    this.label,
    this.value,
    this.icon,
    this.color,
  );
}
