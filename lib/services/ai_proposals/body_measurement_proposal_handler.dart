import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_schema.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/ai_derived_id.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// `propose_body_measurement`: log one or several body measurements (weight,
/// body fat, circumferences, blood pressure) on a date. Append-only and low
/// risk, but the card still shows the previous value of each measurement so a
/// typo (80 kg instead of 8 kg) is caught before it lands in the charts.
class BodyMeasurementProposalHandler extends AiProposalHandler {
  final DatabaseHelper _db;
  final DateTime Function() _now;

  BodyMeasurementProposalHandler({DatabaseHelper? db, DateTime Function()? now})
    : _db = db ?? DatabaseHelper.instance,
      _now = now ?? DateTime.now;

  @override
  String get kind => 'body_measurement';

  @override
  String get toolName => 'propose_body_measurement';

  @override
  AiToolDomain get domain => AiToolDomain.body;

  /// Plausible human range per measurement type, in the type's unit. Outside
  /// it the value is almost certainly a typo or a unit mix-up.
  static const Map<String, (double, double)> ranges = {
    'weight': (20, 400),
    'bodyFat': (2, 70),
    'waist': (30, 250),
    'chest': (30, 250),
    'arm': (10, 100),
    'forearm': (10, 80),
    'neck': (15, 80),
    'thigh': (20, 150),
    'calf': (15, 90),
    'hip': (40, 250),
    'bloodPressure': (60, 260),
  };
  static const _diastolic = (30.0, 160.0);
  static const _timesOfDay = ['morning', 'afternoon', 'evening', 'night'];
  static const maxMeasurements = 12;

  static final Map<String, MeasureType> _types = {
    for (final type in kBodyMeasureTypes) type.id: type,
  };

  @override
  AiToolSpec get spec => AiToolSpec(
    name: toolName,
    proposal: true,
    domain: domain,
    description:
        'Log body measurements the user states, in kg, cm, body fat % and mmHg (convert lb and inches).',
    properties: {
      'date': AiSchema.date('Default today'),
      'time_of_day': AiSchema.enumOf(_timesOfDay),
      'is_fasted': AiSchema.boolean(),
      'comment': AiSchema.str(),
      'measurements': AiSchema.list(
        AiSchema.object(
          {
            'type': AiSchema.enumOf([for (final t in kBodyMeasureTypes) t.id]),
            'value': AiSchema.number('Systolic for bloodPressure.'),
            'secondary_value': AiSchema.number(
              'Diastolic, bloodPressure only.',
              0,
            ),
            'side': AiSchema.enumOf([
              'left',
              'right',
            ], 'arm, forearm, thigh, calf only.'),
          },
          required: ['type', 'value'],
        ),
        min: 1,
        max: maxMeasurements,
      ),
    },
    required: ['measurements'],
  );

  @override
  Future<AiProposalDraft> prepare(
    DatabaseExecutor db,
    AiProposalArgs args,
  ) async {
    args.allowOnly({
      'date',
      'time_of_day',
      'is_fasted',
      'comment',
      'measurements',
    });
    final today = dateKey(_now());
    final date = args.optionalDate('date') ?? today;
    if (date.compareTo(today) > 0) {
      throw AiProposalException(
        'invalid_args',
        '"date" cannot be in the future.',
        param: 'date',
        expected: 'a date on or before $today',
        received: date,
        hint: 'Use today ($today) or an earlier date.',
      );
    }
    final timeOfDay = args.optionalEnum('time_of_day', _timesOfDay);
    final isFasted = args.optionalBool('is_fasted') ?? false;
    final comment = args.optionalString('comment', maxLength: 300);
    final entries = args.requiredObjects('measurements', max: maxMeasurements);
    final repo = _db.bodyMeasurementRepo;

    final items = <Map<String, dynamic>>[];
    final warnings = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final entry in entries) {
      entry.allowOnly({'type', 'value', 'secondary_value', 'side'});
      final type = entry.requiredEnum('type', [
        for (final t in kBodyMeasureTypes) t.id,
      ]);
      final measure = _types[type]!;
      final (min, max) = ranges[type]!;
      final isPressure = type == 'bloodPressure';
      final value = entry.requiredNumber('value', min: min, max: max);
      // Models often fill every optional field with a placeholder (0,
      // "left"…). Fields that do not apply to the type are ignored instead
      // of failing the whole proposal.
      final secondary = isPressure
          ? entry.optionalNumber(
              'secondary_value',
              min: _diastolic.$1,
              max: _diastolic.$2,
            )
          : null;
      if (isPressure && secondary == null) {
        throw AiProposalException(
          'invalid_args',
          'Blood pressure needs "secondary_value" (diastolic).',
          param: '${entry.path}.secondary_value',
          expected: 'diastolic pressure in mmHg',
          hint:
              'Send systolic as "value" and diastolic as "secondary_value", for example 120 and 80.',
        );
      }
      if (isPressure && secondary! >= value) {
        throw AiProposalException(
          'invalid_args',
          'Systolic must be higher than diastolic.',
          param: '${entry.path}.value',
          received: '$value/$secondary',
          hint: 'Check the order: systolic ("value") over diastolic.',
        );
      }
      final side = measure.isBilateral
          ? entry.optionalEnum('side', const ['left', 'right'])
          : null;
      if (!seen.add('$type/${side ?? ''}')) {
        throw AiProposalException(
          'invalid_args',
          'The same measurement appears twice.',
          param: entry.path,
          hint: 'Send each type (and side) once per proposal.',
        );
      }
      final previous = await repo.latestMeasurementOf(
        db,
        type: type,
        side: side,
        onOrBefore: date,
      );
      final sameDay = (await repo.measurementsOn(
        db,
        type: type,
        date: date,
      )).where((row) => (row['side'] as String?) == side).toList();
      final previousValue = (previous?['value'] as num?)?.toDouble();
      if (sameDay.isNotEmpty) {
        warnings.add({'code': 'already_logged', 'type': type, 'side': side});
      }
      if (previousValue != null && previousValue > 0) {
        final change = (value - previousValue) / previousValue;
        final limit = isPressure ? 0.3 : 0.15;
        if (change.abs() > limit) {
          warnings.add({
            'code': 'large_change',
            'type': type,
            'side': side,
            'percent': (change * 100).round(),
          });
        }
      }
      items.add({
        'type': type,
        'value': value,
        'secondary_value': secondary,
        'unit': measure.unit,
        'side': side,
        if (previous != null)
          'previous': {
            'value': previousValue,
            'secondary_value': previous['secondary_value'],
            'date': previous['date'],
          },
      });
    }

    return AiProposalDraft(
      payload: {
        'date': date,
        'time_of_day': timeOfDay,
        'is_fasted': isFasted,
        'comment': comment,
        'measurements': [
          for (final item in items)
            {
              'type': item['type'],
              'value': item['value'],
              'secondary_value': item['secondary_value'],
              'unit': item['unit'],
              'side': item['side'],
            },
        ],
      },
      preview: {
        'v': kAiProposalPreviewVersion,
        'date': date,
        'time_of_day': timeOfDay,
        'is_fasted': isFasted,
        'comment': comment,
        'items': items,
        'warnings': warnings,
      },
      summary: {
        'date': date,
        'measurements': [
          for (final item in items)
            {
              'type': item['type'],
              'value': item['value'],
              if (item['secondary_value'] != null)
                'secondary_value': item['secondary_value'],
              'unit': item['unit'],
              'side': ?item['side'],
            },
        ],
      },
    );
  }

  @override
  Future<Map<String, dynamic>> apply(
    DatabaseExecutor txn,
    AiProposal proposal,
  ) async {
    final payload = proposal.payload;
    final list = payload['measurements'];
    if (list is! List || list.isEmpty) {
      throw const AiProposalException(
        'invalid_payload',
        'The stored proposal has no measurements.',
      );
    }
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < list.length; i++) {
      final m = (list[i] as Map).cast<String, dynamic>();
      rows.add({
        'id': aiDerivedId(proposal.id, 'measurement$i'),
        'type': m['type'],
        'value': m['value'],
        'secondary_value': m['secondary_value'],
        'unit': m['unit'],
        'side': m['side'],
        'date': payload['date'],
        'comment': payload['comment'],
        'time_of_day': payload['time_of_day'],
        'is_fasted': payload['is_fasted'] == true,
      });
    }
    await _db.bodyMeasurementRepo.insertMeasurementsIn(txn, rows);
    return {'date': payload['date'], 'count': rows.length};
  }

  @override
  Map<String, dynamic> resultFacts(AiProposal proposal) => {
    'saved': proposal.result?['count'] ?? 0,
    'date': proposal.result?['date'],
  };
}
