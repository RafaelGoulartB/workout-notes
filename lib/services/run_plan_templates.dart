import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';

enum RunPlanTemplateCategory {
  gettingStarted,
  fiveK,
  tenK,
  half,
  marathon,
  conditioning,
}

enum RunPlanTemplateLevel { beginner, intermediate, advanced }

class RunPlanTemplateStep {
  final RunStepRole role;
  final RunIntervalMetric metric;
  final int value;
  final int? repeatGroup;
  final int repeatCount;
  const RunPlanTemplateStep({
    required this.role,
    this.metric = RunIntervalMetric.distance,
    required this.value,
    this.repeatGroup,
    this.repeatCount = 1,
  });
}

class RunPlanTemplateWorkout {
  final String name;
  final RunWorkoutKind kind;
  final int dayOfWeek;
  final String? notes;
  final String? effortZone;
  final double? targetDistanceMeters;
  final int? targetDurationSeconds;
  final List<RunPlanTemplateStep> steps;
  const RunPlanTemplateWorkout({
    required this.name,
    required this.kind,
    required this.dayOfWeek,
    this.notes,
    this.effortZone,
    this.targetDistanceMeters,
    this.targetDurationSeconds,
    this.steps = const [],
  });
}

/// A complete progressive template. Every entry in [schedule] is one week.
class RunPlanTemplate {
  final String key;
  final RunPlanGoalKind goalKind;
  final RunPlanTemplateCategory category;
  final RunPlanTemplateLevel level;
  final String titlePt,
      titleEn,
      descriptionPt,
      descriptionEn,
      prerequisitePt,
      prerequisiteEn;
  final List<List<RunPlanTemplateWorkout>> schedule;
  const RunPlanTemplate({
    required this.key,
    required this.goalKind,
    required this.category,
    required this.level,
    required this.titlePt,
    required this.titleEn,
    required this.descriptionPt,
    required this.descriptionEn,
    required this.prerequisitePt,
    required this.prerequisiteEn,
    required this.schedule,
  });
  int get weeks => schedule.length;
  List<RunPlanTemplateWorkout> get week => schedule.first;
  int get sessionsPerWeek =>
      schedule.fold(0, (max, value) => value.length > max ? value.length : max);
  String title(bool pt) => pt ? titlePt : titleEn;
  String description(bool pt) => pt ? descriptionPt : descriptionEn;
  String prerequisite(bool pt) => pt ? prerequisitePt : prerequisiteEn;
}

abstract final class RunPlanTemplates {
  static final returnToRunning = _continuous(
    key: 'return',
    goal: RunPlanGoalKind.base,
    category: RunPlanTemplateCategory.gettingStarted,
    titlePt: 'Voltar a correr com segurança',
    titleEn: 'Return to running safely',
    descriptionPt:
        'Recupere a consistência sem tentar retomar do ponto onde parou.',
    descriptionEn:
        'Rebuild consistency without trying to resume where you stopped.',
    prerequisitePt: 'Para quem ficou 4 semanas ou mais sem correr',
    prerequisiteEn: 'For runners returning after 4+ weeks off',
    km: const [
      [2.5, 3, 4],
      [3, 3.5, 4.5],
      [3.5, 4, 5],
      [3, 3.5, 4.5],
      [4, 4.5, 5.5],
      [4, 5, 6],
    ],
  );
  static final runWalk = _runWalk();
  static final firstFiveK = _continuous(
    key: 'first_5k',
    goal: RunPlanGoalKind.fiveK,
    category: RunPlanTemplateCategory.fiveK,
    titlePt: 'Primeiros 5 km',
    titleEn: 'First 5K',
    descriptionPt: 'Construa resistência para completar 5 km com conforto.',
    descriptionEn: 'Build endurance to complete 5K comfortably.',
    prerequisitePt: 'Correr ou alternar corrida e caminhada por 25 min',
    prerequisiteEn: 'Run or run-walk for 25 minutes',
    race: true,
    km: const [
      [2.5, 3, 3.5],
      [3, 3.5, 4],
      [3, 3.5, 4.5],
      [2.5, 3, 4],
      [3.5, 4, 5],
      [3.5, 4.5, 5.5],
      [4, 4.5, 6],
      [3, 3.5, 5],
    ],
  );
  static final fiveK = _performance(
    key: '5k',
    goal: RunPlanGoalKind.fiveK,
    category: RunPlanTemplateCategory.fiveK,
    titlePt: '5 km mais rápido',
    titleEn: 'Faster 5K',
    descriptionPt:
        'Tiros curtos e ritmo controlado para reduzir o pace sem excesso de intensidade.',
    descriptionEn:
        'Short intervals and controlled tempo to improve pace without excess intensity.',
    prerequisitePt: 'Completar 5 km e correr 15 km ou mais por semana',
    prerequisiteEn: 'Complete 5K and run at least 15 km per week',
    longKm: const [7, 8, 9, 7, 9, 10, 11, 8, 9, 7],
    easyKm: 5,
    intervalMeters: 400,
    baseReps: 5,
  );
  static final firstTenK = _continuous(
    key: 'first_10k',
    goal: RunPlanGoalKind.tenK,
    category: RunPlanTemplateCategory.tenK,
    titlePt: 'Dos 5 aos 10 km',
    titleEn: 'From 5K to 10K',
    descriptionPt: 'Aumente o longão aos poucos e chegue aos 10 km inteiro.',
    descriptionEn:
        'Gradually extend the long run and reach 10K feeling strong.',
    prerequisitePt: 'Correr 5 km contínuos e treinar 3 vezes por semana',
    prerequisiteEn: 'Run 5K continuously and train 3 times per week',
    race: true,
    km: const [
      [4, 4, 6],
      [4, 5, 7],
      [5, 5, 8],
      [4, 4, 6],
      [5, 5, 8],
      [5, 6, 9],
      [5, 6, 10],
      [4, 5, 8],
      [5, 6, 11],
      [4, 4, 10],
    ],
  );
  static final tenK = _performance(
    key: '10k',
    goal: RunPlanGoalKind.tenK,
    category: RunPlanTemplateCategory.tenK,
    titlePt: '10 km mais rápido',
    titleEn: 'Faster 10K',
    descriptionPt:
        'Limiar, intervalos e longões para sustentar um pace melhor.',
    descriptionEn:
        'Threshold work, intervals and long runs to hold a faster pace.',
    prerequisitePt: 'Completar 10 km e correr 25 km ou mais por semana',
    prerequisiteEn: 'Complete 10K and run at least 25 km per week',
    longKm: const [10, 11, 12, 9, 12, 13, 14, 10, 14, 15, 11, 8],
    easyKm: 6,
    intervalMeters: 800,
    baseReps: 4,
  );
  static final half = _performance(
    key: 'first_half',
    goal: RunPlanGoalKind.half,
    category: RunPlanTemplateCategory.half,
    titlePt: 'Primeira meia maratona',
    titleEn: 'First half marathon',
    descriptionPt:
        'Amplie a resistência e pratique um ritmo sustentável para os 21,1 km.',
    descriptionEn: 'Build endurance and practise sustainable pacing for 21.1K.',
    prerequisitePt: 'Correr 10 km e manter 25 km semanais há 1 mês',
    prerequisiteEn: 'Run 10K and sustain 25 km/week for one month',
    longKm: const [10, 12, 13, 10, 14, 15, 16, 12, 17, 18, 19, 14, 12, 8],
    easyKm: 6,
    intervalMeters: 1000,
    baseReps: 3,
  );
  static final halfPerformance = _performance(
    key: 'half_pb',
    goal: RunPlanGoalKind.half,
    category: RunPlanTemplateCategory.half,
    level: RunPlanTemplateLevel.advanced,
    titlePt: 'Meia maratona: novo recorde',
    titleEn: 'Half marathon PB',
    descriptionPt:
        'Mais volume e blocos no limiar para quem já domina a distância.',
    descriptionEn:
        'Higher volume and threshold blocks for runners who know the distance.',
    prerequisitePt: 'Já ter completado 21 km e correr 40 km por semana',
    prerequisiteEn: 'Have completed 21K and run 40 km per week',
    sessions: 5,
    longKm: const [
      14,
      15,
      16,
      13,
      17,
      18,
      19,
      15,
      20,
      21,
      22,
      17,
      22,
      18,
      14,
      9,
    ],
    easyKm: 8,
    intervalMeters: 1000,
    baseReps: 4,
  );
  static final marathon = _performance(
    key: 'first_marathon',
    goal: RunPlanGoalKind.marathon,
    category: RunPlanTemplateCategory.marathon,
    level: RunPlanTemplateLevel.advanced,
    titlePt: 'Primeira maratona',
    titleEn: 'First marathon',
    descriptionPt:
        'Longões graduais, recuperação planejada e três semanas de polimento.',
    descriptionEn:
        'Gradual long runs, planned recovery and a three-week taper.',
    prerequisitePt: 'Correr 15 km e sustentar 35 km semanais por 6 semanas',
    prerequisiteEn: 'Run 15K and sustain 35 km/week for six weeks',
    longKm: const [
      14,
      16,
      18,
      14,
      19,
      21,
      23,
      17,
      24,
      26,
      28,
      21,
      28,
      30,
      32,
      24,
      32,
      24,
      16,
      8,
    ],
    easyKm: 8,
    intervalMeters: 1000,
    baseReps: 3,
  );
  static final base = _continuous(
    key: 'base',
    goal: RunPlanGoalKind.base,
    category: RunPlanTemplateCategory.conditioning,
    titlePt: 'Construir base aeróbica',
    titleEn: 'Build aerobic base',
    descriptionPt:
        'Oito semanas leves para criar consistência e tolerância ao volume.',
    descriptionEn:
        'Eight easy weeks to build consistency and volume tolerance.',
    prerequisitePt: 'Correr confortavelmente por 30 minutos',
    prerequisiteEn: 'Run comfortably for 30 minutes',
    km: const [
      [4, 5, 7],
      [4, 5, 8],
      [5, 5, 9],
      [4, 5, 7],
      [5, 6, 9],
      [5, 6, 10],
      [6, 6, 11],
      [4, 5, 8],
    ],
  );
  static final maintenance = _continuous(
    key: 'maintenance',
    goal: RunPlanGoalKind.maintenance,
    category: RunPlanTemplateCategory.conditioning,
    level: RunPlanTemplateLevel.intermediate,
    titlePt: 'Manter o condicionamento',
    titleEn: 'Maintain fitness',
    descriptionPt:
        'Uma semana equilibrada para repetir entre ciclos específicos.',
    descriptionEn: 'A balanced repeatable week between goal-specific cycles.',
    prerequisitePt: 'Já ter uma rotina regular de corrida',
    prerequisiteEn: 'Have an established running routine',
    km: const [
      [5, 6, 10],
    ],
  );

  static final List<RunPlanTemplate> all = [
    returnToRunning,
    runWalk,
    firstFiveK,
    fiveK,
    firstTenK,
    tenK,
    half,
    halfPerformance,
    marathon,
    base,
    maintenance,
  ];
  static RunPlanTemplate? byKey(String key) {
    for (final item in all) {
      if (item.key == key) return item;
    }
    return null;
  }

  static Future<RunPlan> create(
    RunPlanRepository repository,
    RunPlanTemplate template, {
    required String name,
    DateTime? raceDate,
  }) async {
    final plan = await repository.createPlan(
      name: name,
      goalKind: template.goalKind,
      raceDate: raceDate,
      weeks: template.weeks,
    );
    for (var week = 0; week < template.schedule.length; week++) {
      for (final session in template.schedule[week]) {
        final created = await repository.addWorkout(
          planId: plan.id,
          weekIndex: week,
          name: session.name,
          kind: session.kind,
          dayOfWeek: session.dayOfWeek,
          notes: session.notes,
          effortZone: session.effortZone,
          targetDistanceMeters: session.targetDistanceMeters,
          targetDurationSeconds: session.targetDurationSeconds,
        );
        for (final step in session.steps) {
          await repository.addStep(
            workoutId: created.id,
            role: step.role,
            metric: step.metric,
            value: step.value,
            repeatGroup: step.repeatGroup,
            repeatCount: step.repeatCount,
          );
        }
      }
    }
    return (await repository.getPlan(plan.id))!;
  }

  static RunPlanTemplate _runWalk() {
    const work = [60, 90, 120, 180, 300, 480, 600, 900],
        rest = [120, 120, 120, 120, 120, 120, 90, 60],
        reps = [8, 8, 7, 6, 4, 3, 3, 2];
    final weeks = <List<RunPlanTemplateWorkout>>[];
    for (var w = 0; w < work.length; w++) {
      weeks.add([
        for (final day in const [2, 4, 7])
          RunPlanTemplateWorkout(
            name: 'Corrida e caminhada',
            kind: RunWorkoutKind.easy,
            dayOfWeek: day,
            effortZone: 'RPE 3–4',
            notes: 'Corra confortável e caminhe antes de perder a forma.',
            steps: [
              const RunPlanTemplateStep(
                role: RunStepRole.warmup,
                metric: RunIntervalMetric.time,
                value: 300,
              ),
              RunPlanTemplateStep(
                role: RunStepRole.work,
                metric: RunIntervalMetric.time,
                value: work[w],
                repeatGroup: 1,
                repeatCount: reps[w],
              ),
              RunPlanTemplateStep(
                role: RunStepRole.recovery,
                metric: RunIntervalMetric.time,
                value: rest[w],
                repeatGroup: 1,
                repeatCount: reps[w],
              ),
              const RunPlanTemplateStep(
                role: RunStepRole.cooldown,
                metric: RunIntervalMetric.time,
                value: 300,
              ),
            ],
          ),
      ]);
    }
    return RunPlanTemplate(
      key: 'run_walk',
      goalKind: RunPlanGoalKind.base,
      category: RunPlanTemplateCategory.gettingStarted,
      level: RunPlanTemplateLevel.beginner,
      titlePt: 'Começar a correr',
      titleEn: 'Start running',
      descriptionPt:
          'Alterne corrida e caminhada até sustentar blocos de 15 minutos.',
      descriptionEn:
          'Alternate running and walking up to controlled 15-minute running blocks.',
      prerequisitePt: 'Caminhar 30 minutos sem desconforto',
      prerequisiteEn: 'Walk for 30 minutes without discomfort',
      schedule: weeks,
    );
  }

  static RunPlanTemplate _continuous({
    required String key,
    required RunPlanGoalKind goal,
    required RunPlanTemplateCategory category,
    RunPlanTemplateLevel level = RunPlanTemplateLevel.beginner,
    required String titlePt,
    required String titleEn,
    required String descriptionPt,
    required String descriptionEn,
    required String prerequisitePt,
    required String prerequisiteEn,
    required List<List<double>> km,
    bool race = false,
  }) {
    final weeks = <List<RunPlanTemplateWorkout>>[];
    for (var w = 0; w < km.length; w++) {
      weeks.add([
        for (var s = 0; s < km[w].length; s++)
          RunPlanTemplateWorkout(
            name: race && w == km.length - 1 && s == km[w].length - 1
                ? 'Corrida-alvo'
                : s == km[w].length - 1
                ? 'Longão leve'
                : 'Rodagem leve',
            kind: race && w == km.length - 1 && s == km[w].length - 1
                ? RunWorkoutKind.race
                : s == km[w].length - 1
                ? RunWorkoutKind.long
                : RunWorkoutKind.easy,
            dayOfWeek: s == 0
                ? 2
                : s == 1
                ? 5
                : 7,
            targetDistanceMeters: km[w][s] * 1000,
            effortZone: 'Z1–Z2 / RPE 2–4',
            notes:
                'Ritmo de conversa. Termine sentindo que conseguiria continuar.',
          ),
      ]);
    }
    return RunPlanTemplate(
      key: key,
      goalKind: goal,
      category: category,
      level: level,
      titlePt: titlePt,
      titleEn: titleEn,
      descriptionPt: descriptionPt,
      descriptionEn: descriptionEn,
      prerequisitePt: prerequisitePt,
      prerequisiteEn: prerequisiteEn,
      schedule: weeks,
    );
  }

  static RunPlanTemplate _performance({
    required String key,
    required RunPlanGoalKind goal,
    required RunPlanTemplateCategory category,
    RunPlanTemplateLevel level = RunPlanTemplateLevel.intermediate,
    required String titlePt,
    required String titleEn,
    required String descriptionPt,
    required String descriptionEn,
    required String prerequisitePt,
    required String prerequisiteEn,
    required List<double> longKm,
    required double easyKm,
    required int intervalMeters,
    required int baseReps,
    int sessions = 4,
  }) {
    final weeks = <List<RunPlanTemplateWorkout>>[];
    final raceDistanceKm = switch (goal) {
      RunPlanGoalKind.fiveK => 5.0,
      RunPlanGoalKind.tenK => 10.0,
      RunPlanGoalKind.half => 21.1,
      RunPlanGoalKind.marathon => 42.195,
      _ => longKm.last,
    };
    for (var w = 0; w < longKm.length; w++) {
      final taper = w >= longKm.length - 2, recovery = w > 0 && w % 4 == 3;
      final reps = taper ? baseReps : baseReps + (w ~/ 3).clamp(0, 3),
          tempo = taper ? 12 : 15 + (w ~/ 3) * 5;
      final easy =
          easyKm *
          (recovery
              ? .8
              : taper
              ? .7
              : 1 + w * .015);
      final list = <RunPlanTemplateWorkout>[
        _interval(intervalMeters, reps, taper),
        _easy(4, easy),
        _tempo(tempo, taper),
      ];
      if (sessions == 5) list.add(_easy(6, easy * .75, recovery: true));
      list.add(
        RunPlanTemplateWorkout(
          name: w == longKm.length - 1 ? 'Corrida-alvo' : 'Longão leve',
          kind: w == longKm.length - 1
              ? RunWorkoutKind.race
              : RunWorkoutKind.long,
          dayOfWeek: 7,
          targetDistanceMeters:
              (w == longKm.length - 1 ? raceDistanceKm : longKm[w]) * 1000,
          effortZone: 'Z2 / RPE 3–4',
          notes: taper
              ? 'Reduza o volume e preserve a leveza.'
              : 'Ritmo de conversa; não transforme o longão em prova.',
        ),
      );
      weeks.add(list);
    }
    return RunPlanTemplate(
      key: key,
      goalKind: goal,
      category: category,
      level: level,
      titlePt: titlePt,
      titleEn: titleEn,
      descriptionPt: descriptionPt,
      descriptionEn: descriptionEn,
      prerequisitePt: prerequisitePt,
      prerequisiteEn: prerequisiteEn,
      schedule: weeks,
    );
  }

  static RunPlanTemplateWorkout _easy(
    int day,
    double km, {
    bool recovery = false,
  }) => RunPlanTemplateWorkout(
    name: recovery ? 'Regenerativo' : 'Rodagem leve',
    kind: recovery ? RunWorkoutKind.recovery : RunWorkoutKind.easy,
    dayOfWeek: day,
    targetDistanceMeters: (km * 100).round() * 10,
    effortZone: recovery ? 'Z1 / RPE 2' : 'Z1–Z2 / RPE 2–4',
    notes: 'Ritmo confortável, respirando com controle.',
  );
  static RunPlanTemplateWorkout _interval(
    int meters,
    int reps,
    bool taper,
  ) => RunPlanTemplateWorkout(
    name: '$reps×$meters m controlados',
    kind: RunWorkoutKind.interval,
    dayOfWeek: 2,
    effortZone: taper ? 'RPE 7' : 'RPE 8',
    notes: 'Corra forte e uniforme; preserve a técnica até a última repetição.',
    steps: [
      const RunPlanTemplateStep(role: RunStepRole.warmup, value: 1500),
      RunPlanTemplateStep(
        role: RunStepRole.work,
        value: meters,
        repeatGroup: 1,
        repeatCount: reps,
      ),
      RunPlanTemplateStep(
        role: RunStepRole.recovery,
        metric: RunIntervalMetric.time,
        value: meters >= 800 ? 120 : 90,
        repeatGroup: 1,
        repeatCount: reps,
      ),
      const RunPlanTemplateStep(role: RunStepRole.cooldown, value: 1000),
    ],
  );
  static RunPlanTemplateWorkout _tempo(int minutes, bool taper) =>
      RunPlanTemplateWorkout(
        name: 'Ritmo controlado · $minutes min',
        kind: RunWorkoutKind.tempo,
        dayOfWeek: 5,
        effortZone: taper ? 'RPE 6' : 'RPE 7',
        notes: 'Esforço sustentado: frases curtas, sem sprintar.',
        steps: [
          const RunPlanTemplateStep(role: RunStepRole.warmup, value: 1500),
          RunPlanTemplateStep(
            role: RunStepRole.steady,
            metric: RunIntervalMetric.time,
            value: minutes * 60,
          ),
          const RunPlanTemplateStep(role: RunStepRole.cooldown, value: 1000),
        ],
      );
}
