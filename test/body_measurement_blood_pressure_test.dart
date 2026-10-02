import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';

import 'support/test_db.dart';

void main() {
  setUpAll(initSqfliteFfiForTests);

  test('formats blood pressure with systolic and diastolic values', () {
    const type = MeasureType(
      'bloodPressure',
      Icons.favorite,
      'mmHg',
      Colors.red,
      false,
    );

    expect(
      formatMeasurementValue({'value': 120.0, 'secondary_value': 80.0}, type),
      '120/80 mmHg',
    );
  });
}
