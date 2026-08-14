import 'periodization_template_phase.dart';

class PeriodizationTemplate {
  final String key;
  final String nameKey;
  final List<PeriodizationTemplatePhase> phases;

  const PeriodizationTemplate({
    required this.key,
    required this.nameKey,
    required this.phases,
  });

  static const cuttingBulking = PeriodizationTemplate(
    key: 'cutting_bulking',
    nameKey: 'cuttingBulking',
    phases: [
      PeriodizationTemplatePhase(
        nameKey: 'cutting',
        intentKey: 'gradualDeficit',
        templateKey: 'cutting',
        weeks: 12,
        color: 0xFF4F8EF7,
      ),
      PeriodizationTemplatePhase(
        nameKey: 'deload',
        intentKey: 'recover',
        templateKey: 'deload',
        weeks: 1,
        color: 0xFFF5B942,
      ),
      PeriodizationTemplatePhase(
        nameKey: 'bulking',
        intentKey: 'controlledGain',
        templateKey: 'bulking',
        weeks: 16,
        color: 0xFF9B6BE8,
      ),
      PeriodizationTemplatePhase(
        nameKey: 'maintenance',
        intentKey: 'stabilize',
        templateKey: 'maintenance',
        weeks: 4,
        color: 0xFF43B581,
      ),
    ],
  );

  static const strength = PeriodizationTemplate(
    key: 'strength_cycle',
    nameKey: 'strength',
    phases: [
      PeriodizationTemplatePhase(
        nameKey: 'base',
        intentKey: 'buildCapacity',
        templateKey: 'base',
        weeks: 6,
        color: 0xFF4F8EF7,
      ),
      PeriodizationTemplatePhase(
        nameKey: 'intensification',
        intentKey: 'raiseIntensity',
        templateKey: 'intensification',
        weeks: 4,
        color: 0xFF9B6BE8,
      ),
      PeriodizationTemplatePhase(
        nameKey: 'deload',
        intentKey: 'recover',
        templateKey: 'deload',
        weeks: 1,
        color: 0xFFF5B942,
      ),
      PeriodizationTemplatePhase(
        nameKey: 'peak',
        intentKey: 'expressPerformance',
        templateKey: 'peak',
        weeks: 2,
        color: 0xFFE85858,
      ),
    ],
  );

  static const running = PeriodizationTemplate(
    key: 'running_season',
    nameKey: 'running',
    phases: [
      PeriodizationTemplatePhase(
        nameKey: 'base',
        intentKey: 'buildAerobicBase',
        templateKey: 'aerobic_base',
        weeks: 8,
        color: 0xFF4F8EF7,
      ),
      PeriodizationTemplatePhase(
        nameKey: 'build',
        intentKey: 'increaseSpecificLoad',
        templateKey: 'build',
        weeks: 6,
        color: 0xFF9B6BE8,
      ),
      PeriodizationTemplatePhase(
        nameKey: 'taper',
        intentKey: 'reduceFatigue',
        templateKey: 'taper',
        weeks: 2,
        color: 0xFFF5B942,
      ),
      PeriodizationTemplatePhase(
        nameKey: 'event',
        intentKey: 'eventWeek',
        templateKey: 'event',
        weeks: 1,
        color: 0xFFE85858,
      ),
    ],
  );

  static const all = [cuttingBulking, strength, running];
}
