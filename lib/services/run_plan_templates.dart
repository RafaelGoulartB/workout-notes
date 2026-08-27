import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/services/run_plan_composer.dart';

enum RunPlanTemplateCategory {
  gettingStarted,
  fiveK,
  tenK,
  half,
  marathon,
  conditioning,
}

enum RunPlanTemplateLevel { beginner, intermediate, advanced }

enum RunPlanTemplateStyle { continuous, performance, runWalk }

class RunPlanTemplateStep {
  final RunStepRole role;
  final RunIntervalMetric metric;
  final int value;
  final int? repeatGroup;
  final int repeatCount;
  final double? targetPaceMinSecPerKm;
  final double? targetPaceMaxSecPerKm;
  const RunPlanTemplateStep({
    required this.role,
    this.metric = RunIntervalMetric.distance,
    required this.value,
    this.repeatGroup,
    this.repeatCount = 1,
    this.targetPaceMinSecPerKm,
    this.targetPaceMaxSecPerKm,
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
  final double? targetPaceSecPerKm;
  final List<RunPlanTemplateStep> steps;
  const RunPlanTemplateWorkout({
    required this.name,
    required this.kind,
    required this.dayOfWeek,
    this.notes,
    this.effortZone,
    this.targetDistanceMeters,
    this.targetDurationSeconds,
    this.targetPaceSecPerKm,
    this.steps = const [],
  });
}

/// A complete progressive template. Every entry in [schedule] is one week.
///
/// Blueprint fields ([continuousKm], [performanceLongKm], …) feed
/// [RunPlanComposer] when the user customises days / intensity / paces.
class RunPlanTemplate {
  final String key;
  final RunPlanGoalKind goalKind;
  final RunPlanTemplateCategory category;
  final RunPlanTemplateLevel level;
  final RunPlanTemplateStyle style;
  final String titlePt,
      titleEn,
      descriptionPt,
      descriptionEn,
      prerequisitePt,
      prerequisiteEn;
  final List<List<RunPlanTemplateWorkout>> schedule;

  /// Weekly volume (km) the prerequisite text assumes the athlete already
  /// runs. When the wizard has no measured baseline the composer anchors
  /// week 1 here instead of starting at the template's full ladder.
  final double? prerequisiteWeeklyKm;

  /// Continuous / base ladders: each inner list is one week of km (last = long).
  final List<List<double>>? continuousKm;
  final bool raceFinish;

  /// Performance ladders.
  final List<double>? performanceLongKm;
  final double? performanceEasyKm;
  final int? performanceIntervalMeters;
  final int? performanceBaseReps;

  /// Run/walk ladders (seconds / reps per week).
  final List<int>? runWalkWork;
  final List<int>? runWalkRest;
  final List<int>? runWalkReps;

  const RunPlanTemplate({
    required this.key,
    required this.goalKind,
    required this.category,
    required this.level,
    required this.style,
    required this.titlePt,
    required this.titleEn,
    required this.descriptionPt,
    required this.descriptionEn,
    required this.prerequisitePt,
    required this.prerequisiteEn,
    required this.schedule,
    this.prerequisiteWeeklyKm,
    this.continuousKm,
    this.raceFinish = false,
    this.performanceLongKm,
    this.performanceEasyKm,
    this.performanceIntervalMeters,
    this.performanceBaseReps,
    this.runWalkWork,
    this.runWalkRest,
    this.runWalkReps,
    this.allowedWeeks = const [],
  });
  List<RunPlanTemplateWorkout> get week => schedule.first;
  int get sessionsPerWeek =>
      schedule.fold(0, (max, value) => value.length > max ? value.length : max);
  String title(bool pt) => pt ? titlePt : titleEn;
  String description(bool pt) => pt ? descriptionPt : descriptionEn;
  String prerequisite(bool pt) => pt ? prerequisitePt : prerequisiteEn;

  /// When non-empty, the customize wizard lets the athlete pick plan length
  /// and the composer expands the blueprint into that many varied weeks.
  final List<int> allowedWeeks;

  bool get selectableWeeks => allowedWeeks.isNotEmpty;

  /// Flat-volume “keep what you have” plans — no race build or taper.
  bool get maintainFitness => key == 'keep_fit';

  /// Default length when the wizard has not picked yet (also used by tests /
  /// catalog when [RunPlanBuildConfig.weeks] is omitted).
  int get defaultSelectableWeeks {
    if (!selectableWeeks) return schedule.length;
    if (allowedWeeks.contains(8)) return 8;
    return allowedWeeks[allowedWeeks.length ~/ 2];
  }

  /// Display / catalog week count. Selectable plans report their default
  /// length; the composed schedule may differ once the athlete picks.
  int get weeks =>
      selectableWeeks ? defaultSelectableWeeks : schedule.length;

  /// Suggested days/week choices for the customize wizard.
  ///
  /// Beginner and return progressions cap at four days: bone and tendon
  /// adaptation lags the cardiovascular system, so these runners gain little
  /// from a fifth impact day and take on avoidable injury risk.
  List<int> get allowedSessionsPerWeek {
    if (style == RunPlanTemplateStyle.runWalk ||
        key == 'return' ||
        key == 'return_injury' ||
        key == 'walk_jog' ||
        key == 'first_5k' ||
        key == 'habit_3x') {
      return const [3, 4];
    }
    return const [3, 4, 5];
  }

  /// Easy aerobic blocks that should not prescribe structured quality.
  bool get aerobicOnly =>
      key == 'base' || key == 'habit_3x' || key == 'trail_intro';

  /// Return-to-running (or post-injury) progressions that stay gentler longer.
  bool get returnStyle => key == 'return' || key == 'return_injury';
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
  static final returnAfterInjury = _continuous(
    key: 'return_injury',
    goal: RunPlanGoalKind.base,
    category: RunPlanTemplateCategory.gettingStarted,
    titlePt: 'Voltar após lesão',
    titleEn: 'Return after injury',
    descriptionPt:
        'Progressão mais lenta, sem tiros no início, para retomar o impacto com cuidado.',
    descriptionEn:
        'A slower progression with no early speed work, easing back into impact carefully.',
    prerequisitePt:
        'Alta médica para correr e caminhar 30 min sem dor há 1 semana',
    prerequisiteEn:
        'Cleared to run and able to walk 30 minutes pain-free for one week',
    km: const [
      [2, 2.5, 3],
      [2.5, 3, 3.5],
      [3, 3, 4],
      [2.5, 3, 3.5],
      [3, 3.5, 4.5],
      [3.5, 4, 5],
      [3.5, 4.5, 5.5],
      [4, 4.5, 6],
    ],
  );
  static final walkJog = _runWalk(
    key: 'walk_jog',
    titlePt: 'Caminhada ao trote',
    titleEn: 'Walk to jog',
    descriptionPt:
        'Blocos curtos de trote com caminhada longa — o degrau antes de “Começar a correr”.',
    descriptionEn:
        'Short jog blocks with generous walks — the step before Start running.',
    prerequisitePt: 'Caminhar 20 minutos em terreno plano sem desconforto',
    prerequisiteEn: 'Walk 20 minutes on flat ground without discomfort',
    work: const [20, 30, 45, 60, 75, 90, 120, 150],
    rest: const [90, 90, 90, 90, 75, 75, 60, 60],
    reps: const [10, 10, 9, 8, 8, 7, 6, 6],
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
    prereqKm: 8,
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
    prereqKm: 15,
    longKm: const [7, 8, 9, 7, 9, 10, 11, 8, 9, 7],
    easyKm: 5,
    intervalMeters: 400,
    baseReps: 5,
  );
  static final fiveKAdvanced = _performance(
    key: '5k_advanced',
    goal: RunPlanGoalKind.fiveK,
    category: RunPlanTemplateCategory.fiveK,
    level: RunPlanTemplateLevel.advanced,
    titlePt: '5 km avançado',
    titleEn: 'Advanced 5K',
    descriptionPt:
        'Mais volume, reps e limiar para quem já tem base e busca um 5 km competitivo.',
    descriptionEn:
        'Higher volume, reps and threshold work for runners chasing a competitive 5K.',
    prerequisitePt: 'Correr 5 km sob esforço e manter 30 km semanais',
    prerequisiteEn: 'Run a hard 5K and sustain 30 km per week',
    prereqKm: 30,
    sessions: 5,
    longKm: const [8, 9, 10, 8, 10, 11, 12, 9, 11, 12, 10, 7],
    easyKm: 7,
    intervalMeters: 400,
    baseReps: 6,
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
    prereqKm: 15,
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
    prereqKm: 25,
    longKm: const [10, 11, 12, 9, 12, 13, 14, 10, 14, 15, 11, 8],
    easyKm: 6,
    intervalMeters: 800,
    baseReps: 4,
  );
  static final tenKAdvanced = _performance(
    key: '10k_advanced',
    goal: RunPlanGoalKind.tenK,
    category: RunPlanTemplateCategory.tenK,
    level: RunPlanTemplateLevel.advanced,
    titlePt: '10 km avançado',
    titleEn: 'Advanced 10K',
    descriptionPt:
        'Cinco dias, limiar e VO2 para quem já completa 10 km e quer baixar o pace.',
    descriptionEn:
        'Five days, threshold and VO2 work for runners who finish 10K and want a faster pace.',
    prerequisitePt: 'Completar 10 km e correr 40 km ou mais por semana',
    prerequisiteEn: 'Complete 10K and run at least 40 km per week',
    prereqKm: 40,
    sessions: 5,
    longKm: const [12, 13, 14, 11, 14, 15, 16, 12, 16, 17, 14, 10],
    easyKm: 8,
    intervalMeters: 1000,
    baseReps: 5,
  );
  static final toHalf = _continuous(
    key: 'to_half',
    goal: RunPlanGoalKind.half,
    category: RunPlanTemplateCategory.half,
    titlePt: 'Dos 10 km à meia',
    titleEn: 'From 10K to half',
    descriptionPt:
        'Volume e longões graduais para completar a meia com conforto, sem pressão de tempo.',
    descriptionEn:
        'Gradual volume and long runs to finish the half comfortably, without chasing a time.',
    prerequisitePt: 'Correr 10 km contínuos e manter 25 km semanais',
    prerequisiteEn: 'Run 10K continuously and sustain 25 km per week',
    prereqKm: 25,
    race: true,
    km: const [
      [6, 6, 10],
      [6, 7, 12],
      [7, 7, 13],
      [6, 6, 10],
      [7, 8, 14],
      [8, 8, 15],
      [8, 9, 16],
      [7, 7, 12],
      [8, 9, 17],
      [9, 9, 18],
      [9, 10, 19],
      [8, 8, 14],
      [8, 9, 16],
      [6, 6, 12],
    ],
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
    prereqKm: 25,
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
    prereqKm: 40,
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
    prereqKm: 35,
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
  static final marathonPb = _performance(
    key: 'marathon_pb',
    goal: RunPlanGoalKind.marathon,
    category: RunPlanTemplateCategory.marathon,
    level: RunPlanTemplateLevel.advanced,
    titlePt: 'Maratona: novo recorde',
    titleEn: 'Marathon PB',
    descriptionPt:
        'Mais volume, blocos no ritmo de prova e longões longos para quem já terminou 42 km.',
    descriptionEn:
        'Higher volume, race-pace blocks and long long-runs for runners who have finished 42K.',
    prerequisitePt: 'Já ter completado uma maratona e correr 50 km por semana',
    prerequisiteEn: 'Have finished a marathon and run 50 km per week',
    prereqKm: 50,
    sessions: 5,
    longKm: const [
      16,
      18,
      20,
      16,
      22,
      24,
      26,
      20,
      27,
      29,
      30,
      22,
      30,
      32,
      32,
      24,
      28,
      20,
      14,
      8,
    ],
    easyKm: 10,
    intervalMeters: 1000,
    baseReps: 4,
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
    prereqKm: 12,
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
  static final habit = _continuous(
    key: 'habit_3x',
    goal: RunPlanGoalKind.maintenance,
    category: RunPlanTemplateCategory.conditioning,
    titlePt: 'Criar o hábito de correr',
    titleEn: 'Build the running habit',
    descriptionPt:
        'Oito semanas estáveis, 3–4 dias, para criar consistência sem meta de prova.',
    descriptionEn:
        'Eight steady weeks, 3–4 days, to build consistency without a race goal.',
    prerequisitePt: 'Correr ou trotar com conforto por 20 minutos',
    prerequisiteEn: 'Run or jog comfortably for 20 minutes',
    prereqKm: 10,
    km: const [
      [4, 5, 7],
      [4, 5, 7],
      [5, 5, 8],
      [4, 5, 7],
      [5, 5, 8],
      [5, 6, 8],
      [5, 6, 9],
      [4, 5, 7],
    ],
  );
  static final trailIntro = _continuous(
    key: 'trail_intro',
    goal: RunPlanGoalKind.base,
    category: RunPlanTemplateCategory.conditioning,
    level: RunPlanTemplateLevel.intermediate,
    titlePt: 'Introdução ao trail',
    titleEn: 'Trail introduction',
    descriptionPt:
        'Volume por esforço em terreno irregular: subidas caminhadas, descidas controladas.',
    descriptionEn:
        'Effort-based volume on uneven terrain: hike the climbs, control the descents.',
    prerequisitePt: 'Correr 40 minutos em asfalto e ter acesso a trilha leve',
    prerequisiteEn: 'Run 40 minutes on road and have access to easy trails',
    prereqKm: 18,
    km: const [
      [4, 5, 7],
      [5, 5, 8],
      [5, 6, 9],
      [4, 5, 7],
      [5, 6, 9],
      [6, 6, 10],
      [6, 7, 11],
      [5, 6, 9],
    ],
  );
  static final thresholdBlock = _performance(
    key: 'threshold_block',
    goal: RunPlanGoalKind.base,
    category: RunPlanTemplateCategory.conditioning,
    titlePt: 'Bloco de limiar',
    titleEn: 'Threshold block',
    descriptionPt:
        'Seis semanas focadas em ritmo controlado e cruise intervals entre ciclos de prova.',
    descriptionEn:
        'Six weeks of controlled tempo and cruise intervals between race cycles.',
    prerequisitePt: 'Correr 45 minutos contínuos e manter 25 km semanais',
    prerequisiteEn: 'Run 45 minutes continuously and sustain 25 km per week',
    prereqKm: 25,
    longKm: const [10, 11, 12, 9, 12, 11],
    easyKm: 6,
    intervalMeters: 1000,
    baseReps: 3,
  );
  static final hills = _performance(
    key: 'hills',
    goal: RunPlanGoalKind.base,
    category: RunPlanTemplateCategory.conditioning,
    titlePt: 'Força em subidas',
    titleEn: 'Hill strength',
    descriptionPt:
        'Repetições em ladeira por esforço para potência e economia — sem pace de plano.',
    descriptionEn:
        'Effort-based hill repeats for power and economy — no flat-ground paces.',
    prerequisitePt: 'Correr 30 minutos e ter uma subida de 60–90 s por perto',
    prerequisiteEn: 'Run 30 minutes and have a 60–90 s hill nearby',
    prereqKm: 20,
    longKm: const [8, 9, 10, 8, 10, 9],
    easyKm: 5,
    intervalMeters: 200,
    baseReps: 8,
  );
  static final raceSharpen = _performance(
    key: 'race_sharpen',
    goal: RunPlanGoalKind.tenK,
    category: RunPlanTemplateCategory.conditioning,
    titlePt: 'Polimento de prova',
    titleEn: 'Race sharpening',
    descriptionPt:
        'Cinco semanas leves de qualidade e taper para chegar afiado numa prova de 5–10 km.',
    descriptionEn:
        'Five light weeks of quality and taper to arrive sharp for a 5–10K race.',
    prerequisitePt: 'Já ter base recente e uma prova de 5–10 km marcada',
    prerequisiteEn: 'Have recent base fitness and a 5–10K race on the calendar',
    prereqKm: 28,
    longKm: const [11, 12, 13, 9, 8],
    easyKm: 7,
    intervalMeters: 800,
    baseReps: 4,
  );
  static final keepFit = _continuous(
    key: 'keep_fit',
    goal: RunPlanGoalKind.maintenance,
    category: RunPlanTemplateCategory.conditioning,
    level: RunPlanTemplateLevel.intermediate,
    titlePt: 'Manter o desempenho',
    titleEn: 'Maintain performance',
    descriptionPt:
        'Semanas variadas no seu volume atual — qualidade leve para não perder o que conquistou, sem buscar melhora.',
    descriptionEn:
        'Varied weeks at your current volume — light quality to keep what you earned, without chasing gains.',
    prerequisitePt: 'Já ter uma rotina estável e um volume semanal conhecido',
    prerequisiteEn: 'Have a stable routine and a known weekly volume',
    prereqKm: 25,
    allowedWeeks: const [4, 6, 8, 10, 12, 16],
    // Blueprint week only — the composer expands to the chosen length.
    km: const [
      [5, 6, 10],
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
    returnAfterInjury,
    walkJog,
    runWalk,
    firstFiveK,
    fiveK,
    fiveKAdvanced,
    firstTenK,
    tenK,
    tenKAdvanced,
    toHalf,
    half,
    halfPerformance,
    marathon,
    marathonPb,
    base,
    habit,
    trailIntro,
    thresholdBlock,
    hills,
    raceSharpen,
    keepFit,
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
    RunPlanBuildConfig? config,
  }) async {
    final schedule = config == null
        ? template.schedule
        : RunPlanComposer.compose(template, config);
    final plan = await repository.createPlan(
      name: name,
      goalKind: template.goalKind,
      raceDate: config?.raceDate ?? raceDate,
      weeks: schedule.length,
    );
    for (var week = 0; week < schedule.length; week++) {
      for (final session in schedule[week]) {
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
          targetPaceSecPerKm: session.targetPaceSecPerKm,
        );
        for (final step in session.steps) {
          await repository.addStep(
            workoutId: created.id,
            role: step.role,
            metric: step.metric,
            value: step.value,
            repeatGroup: step.repeatGroup,
            repeatCount: step.repeatCount,
            targetPaceMinSecPerKm: step.targetPaceMinSecPerKm,
            targetPaceMaxSecPerKm: step.targetPaceMaxSecPerKm,
          );
        }
      }
    }
    return (await repository.getPlan(plan.id))!;
  }

  static RunPlanTemplate _runWalk({
    String key = 'run_walk',
    String titlePt = 'Começar a correr',
    String titleEn = 'Start running',
    String descriptionPt =
        'Alterne corrida e caminhada até sustentar blocos de 15 minutos.',
    String descriptionEn =
        'Alternate running and walking up to controlled 15-minute running blocks.',
    String prerequisitePt = 'Caminhar 30 minutos sem desconforto',
    String prerequisiteEn = 'Walk for 30 minutes without discomfort',
    List<int> work = const [60, 90, 120, 180, 300, 480, 600, 900],
    List<int> rest = const [120, 120, 120, 120, 120, 120, 90, 60],
    List<int> reps = const [8, 8, 7, 6, 4, 3, 3, 2],
  }) {
    final weeks = <List<RunPlanTemplateWorkout>>[];
    for (var w = 0; w < work.length; w++) {
      weeks.add([
        for (final day in const [2, 4, 7])
          RunPlanTemplateWorkout(
            name: key == 'walk_jog'
                ? 'Trote e caminhada'
                : 'Corrida e caminhada',
            kind: RunWorkoutKind.easy,
            dayOfWeek: day,
            effortZone: 'RPE 3–4',
            notes: key == 'walk_jog'
                ? 'Trote bem leve; caminhe antes de perder a respiração.'
                : 'Corra confortável e caminhe antes de perder a forma.',
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
      key: key,
      goalKind: RunPlanGoalKind.base,
      category: RunPlanTemplateCategory.gettingStarted,
      level: RunPlanTemplateLevel.beginner,
      style: RunPlanTemplateStyle.runWalk,
      titlePt: titlePt,
      titleEn: titleEn,
      descriptionPt: descriptionPt,
      descriptionEn: descriptionEn,
      prerequisitePt: prerequisitePt,
      prerequisiteEn: prerequisiteEn,
      schedule: weeks,
      runWalkWork: work,
      runWalkRest: rest,
      runWalkReps: reps,
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
    double? prereqKm,
    bool race = false,
    List<int> allowedWeeks = const [],
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
      style: RunPlanTemplateStyle.continuous,
      titlePt: titlePt,
      titleEn: titleEn,
      descriptionPt: descriptionPt,
      descriptionEn: descriptionEn,
      prerequisitePt: prerequisitePt,
      prerequisiteEn: prerequisiteEn,
      schedule: weeks,
      prerequisiteWeeklyKm: prereqKm,
      continuousKm: km,
      raceFinish: race,
      allowedWeeks: allowedWeeks,
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
    double? prereqKm,
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
      style: RunPlanTemplateStyle.performance,
      titlePt: titlePt,
      titleEn: titleEn,
      descriptionPt: descriptionPt,
      descriptionEn: descriptionEn,
      prerequisitePt: prerequisitePt,
      prerequisiteEn: prerequisiteEn,
      schedule: weeks,
      prerequisiteWeeklyKm: prereqKm,
      performanceLongKm: longKm,
      performanceEasyKm: easyKm,
      performanceIntervalMeters: intervalMeters,
      performanceBaseReps: baseReps,
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
