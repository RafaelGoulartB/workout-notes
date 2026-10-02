import 'package:flutter/foundation.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/utils/body_progress_analytics.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Which trend chart the chart card is showing.
enum BodyChartTab { weekly, delta, daily }

/// How fast the selected measure is moving, for the rate card's pill.
enum BodyPace { stable, aggressive, sustainable }

/// BMI category boundaries (WHO adult ranges).
enum BmiCategory { under, normal, over, obese }

/// Data and derived values of the body statistics screen: every measurement
/// row, the selected type/period/chart, the height used for BMI and the
/// active periodization phase's target weight. Analytics themselves come from
/// [BodyProgressAnalytics].
class BodyStatsController extends ChangeNotifier {
  BodyStatsController({
    required String initialTypeId,
    List<MeasureType> types = const [],
    BodyMeasurementRepository? bodyRepo,
    SettingsRepository? settingsRepo,
    PeriodizationRepository? periodizationRepo,
  }) : _selectedType = initialTypeId,
       _types = types.isEmpty ? kBodyMeasureTypes : types,
       _bodyRepo = bodyRepo ?? DatabaseHelper.instance.bodyMeasurementRepo,
       _settingsRepo = settingsRepo ?? DatabaseHelper.instance.settingsRepo,
       _periodizationRepo =
           periodizationRepo ?? DatabaseHelper.instance.periodizationRepo;

  final BodyMeasurementRepository _bodyRepo;
  final SettingsRepository _settingsRepo;
  final PeriodizationRepository _periodizationRepo;
  final List<MeasureType> _types;

  String _selectedType;
  BodyStatsPeriod _period = BodyStatsPeriod.weeks12;
  BodyChartTab _chartTab = BodyChartTab.weekly;

  bool _loading = true;
  bool _loadFailed = false;
  bool _disposed = false;

  /// Every measurement row, newest first.
  List<Map<String, dynamic>> _allRows = [];

  /// Rows of the selected type, newest first.
  List<Map<String, dynamic>> _rows = [];

  /// Types that actually have at least one measurement.
  Set<String> _typesWithData = {};

  double? _heightCm;
  PeriodizationPhase? _phase;
  double? _phaseTargetWeightKg;

  List<MeasureType> get types => _types;
  String get selectedType => _selectedType;
  BodyStatsPeriod get period => _period;
  BodyChartTab get chartTab => _chartTab;
  bool get loading => _loading;
  bool get loadFailed => _loadFailed;
  PeriodizationPhase? get phase => _phase;

  MeasureType get currentType => _types.firstWhere(
    (t) => t.id == _selectedType,
    orElse: () => kBodyMeasureTypes.first,
  );

  bool get isDecreasingGood => isDecreasingGoodFor(_selectedType);

  String get unit => currentType.unit;

  int get decimals => _selectedType == 'bloodPressure' ? 0 : 1;

  /// Types worth offering: those with data, plus the current selection.
  List<MeasureType> get visibleTypes => _types
      .where((t) => _typesWithData.contains(t.id) || t.id == _selectedType)
      .toList();

  /// Analytics of the selected type over the selected period.
  BodyProgressAnalytics get analytics =>
      BodyProgressAnalytics.fromRows(_rows, period: _period);

  // ------------------------------------------------------------------
  // Loading and selection
  // ------------------------------------------------------------------

  Future<void> load() async {
    _loading = true;
    _loadFailed = false;
    _notify();
    try {
      final all = await _bodyRepo.getBodyMeasurements(limit: 2000);
      final height = await _settingsRepo.getSetting(
        'nutrition_profile_height_cm',
      );
      final phase = await _loadPhase();
      if (_disposed) return;
      _allRows = all;
      _rows = all.where((m) => m['type'] == _selectedType).toList();
      _typesWithData = all.map((m) => m['type'] as String).toSet();
      _heightCm = double.tryParse(height?.replaceAll(',', '.') ?? '');
      _phase = phase.$1;
      _phaseTargetWeightKg = phase.$2;
      _loading = false;
      _notify();
    } catch (error, stack) {
      debugPrint('Body stats failed to load: $error\n$stack');
      if (_disposed) return;
      _loading = false;
      _loadFailed = true;
      _notify();
    }
  }

  /// Active phase and its effective target weight, when a periodization plan
  /// is running. Both null when there is no plan — the goal card is hidden.
  Future<(PeriodizationPhase?, double?)> _loadPhase() async {
    try {
      final phase = await _periodizationRepo.getEffectivePhase(DateTime.now());
      if (phase == null) return (null, null);
      final target = await _periodizationRepo.getEffectiveTarget(phase.id);
      return (phase, target?.targetWeightKg);
    } catch (_) {
      return (null, null);
    }
  }

  void switchType(String typeId) {
    // Every type is already in memory, so switching needs no new query.
    _selectedType = typeId;
    _rows = _allRows.where((m) => m['type'] == typeId).toList();
    _notify();
  }

  void setPeriod(BodyStatsPeriod period) {
    _period = period;
    _notify();
  }

  void setChartTab(BodyChartTab tab) {
    _chartTab = tab;
    _notify();
  }

  // ------------------------------------------------------------------
  // Derived values
  // ------------------------------------------------------------------

  String value(double? v, {int? decimals}) =>
      v == null ? '--' : AppNumberFormat.decimal(v, decimals ?? this.decimals);

  String signed(double? v, {int decimals = 1}) {
    if (v == null) return '--';
    final sign = v > 0
        ? '+'
        : v < 0
        ? '-'
        : '';
    return '$sign${AppNumberFormat.decimal(v.abs(), decimals)}';
  }

  /// True when a change of [delta] moves in the direction the user wants.
  bool isGood(double delta) => isDecreasingGood ? delta < 0 : delta > 0;

  /// BMI for the current weight, or null when the type is not weight or no
  /// height is configured in the nutrition profile.
  double? bmi(double? weightKg) {
    final height = _heightCm;
    if (_selectedType != 'weight' || weightKg == null) return null;
    if (height == null || height < 80 || height > 260) return null;
    final meters = height / 100;
    return weightKg / (meters * meters);
  }

  static BmiCategory bmiCategory(double bmi) {
    if (bmi < 18.5) return BmiCategory.under;
    if (bmi < 25) return BmiCategory.normal;
    if (bmi < 30) return BmiCategory.over;
    return BmiCategory.obese;
  }

  /// A rate faster than 1%/week of body weight is worth flagging; the same
  /// threshold reads fine for circumferences and body fat. Null without a rate.
  static BodyPace? paceFor(double? rate, double? ratePercent) {
    if (rate == null) return null;
    if (rate.abs() < 0.02 || (ratePercent != null && ratePercent.abs() < 0.1)) {
      return BodyPace.stable;
    }
    if (ratePercent != null && ratePercent.abs() > 1.0) {
      return BodyPace.aggressive;
    }
    return BodyPace.sustainable;
  }

  /// Progress toward the active phase's target weight; null when there is
  /// nothing to track (goal only applies to weight, and needs a running plan).
  BodyGoalProgress? goalProgress(BodyProgressAnalytics a) {
    final target = _phaseTargetWeightKg;
    final phase = _phase;
    if (_selectedType != 'weight' || target == null || phase == null) {
      return null;
    }
    // The phase start is the honest anchor for progress: it is where the user
    // committed to the target. Falls back to the period start when the phase
    // began before any measurement.
    final startValue = weightAt(phase.startDate) ?? a.firstValue;
    return a.goalProgress(target, startValue: startValue);
  }

  /// Weight recorded closest to [date] — the first entry on or after it, or
  /// the last one before it when the phase started after the final entry.
  double? weightAt(DateTime date) => closestValue(_rows, date);

  /// Value closest to [date] in [rows] (newest first): the first entry on or
  /// after it, otherwise the latest one before it.
  @visibleForTesting
  static double? closestValue(List<Map<String, dynamic>> rows, DateTime date) {
    final target = dayOf(date);
    // Rows come newest first, so the last match walking down is the closest
    // entry on or after the phase start.
    double? onOrAfter;
    double? before;
    for (final row in rows) {
      final raw = row['date'];
      final value = (row['value'] as num?)?.toDouble();
      if (raw is! String || raw.length < 10 || value == null) continue;
      final d = DateTime.tryParse(raw.substring(0, 10));
      if (d == null) continue;
      if (d.isBefore(target)) {
        before ??= value;
      } else {
        onOrAfter = value;
      }
    }
    return onOrAfter ?? before;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
