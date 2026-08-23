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

/// Every measurement type the app can track, in display order. Shared by the
/// body tracker dashboard and the progress stats screen so both stay in sync.
const kBodyMeasureTypes = <MeasureType>[
  MeasureType('weight', Icons.monitor_weight, 'kg', Colors.indigo, false),
  MeasureType('bodyFat', Icons.water_drop, '%', Colors.orange, false),
  MeasureType('waist', Icons.straighten, 'cm', Colors.teal, false),
  MeasureType('chest', Icons.straighten, 'cm', Colors.blue, false),
  MeasureType('arm', Icons.straighten, 'cm', Colors.purple, true),
  MeasureType('forearm', Icons.straighten, 'cm', Colors.deepPurple, true),
  MeasureType('neck', Icons.straighten, 'cm', Colors.blueGrey, false),
  MeasureType('thigh', Icons.straighten, 'cm', Colors.deepOrange, true),
  MeasureType('calf', Icons.straighten, 'cm', Colors.brown, true),
  MeasureType('hip', Icons.straighten, 'cm', Colors.cyan, false),
  MeasureType('bloodPressure', Icons.favorite, 'mmHg', Colors.red, false),
];
