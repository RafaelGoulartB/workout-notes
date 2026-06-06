/// Translations for exercise and category names/notes.
/// These are used when a row has a non-null `locale_key`.
/// User-created exercises (null locale_key) fall back to the stored DB name.
class ExerciseLocalization {
  /// Returns the localized exercise name for [key] in the given [locale].
  /// Returns `null` if no translation exists.
  static String? exerciseName(String key, String locale) {
    return _exerciseNames[locale]?[key];
  }

  /// Returns the localized exercise notes for [key] in the given [locale].
  /// Returns `null` if no translation exists.
  static String? exerciseNotes(String key, String locale) {
    return _exerciseNotes[locale]?[key];
  }

  /// Returns the localized category name for [key] in the given [locale].
  /// Returns `null` if no translation exists.
  static String? categoryName(String key, String locale) {
    return _categoryNames[locale]?[key];
  }

  /// Returns all localized names for exercises in the given [locale].
  /// Useful for search across translations.
  static Map<String, String> allExerciseNames(String locale) {
    return _exerciseNames[locale] ?? {};
  }

  /// Returns all localized category names in the given [locale].
  static Map<String, String> allCategoryNames(String locale) {
    return _categoryNames[locale] ?? {};
  }

  /// Returns the full list of supported locale codes.
  static List<String> get supportedLocales => _exerciseNames.keys.toList();

  // ===================================================================
  // EXERCISE NAMES
  // ===================================================================

  static const Map<String, Map<String, String>> _exerciseNames = {
    'en': {
      // Chest
      'bench_press': 'Bench Press',
      'incl_bench': 'Incline Bench Press',
      'decl_bench': 'Decline Bench Press',
      'db_bench': 'Dumbbell Bench Press',
      'db_incl': 'Incline Dumbbell Press',
      'cable_fly': 'Cable Fly',
      'pec_deck': 'Pec Deck',
      'pushup': 'Push-up',
      'chest_dip': 'Chest Dip',
      'sm_bench': 'Smith Machine Bench Press',

      // Back
      'pullup': 'Pull-up',
      'chinup': 'Chin-up',
      'lat_pulldown': 'Lat Pulldown',
      'bent_row': 'Bent Over Row',
      'db_row': 'Dumbbell Row',
      'seated_row': 'Seated Row',
      'tbar_row': 'T-Bar Row',
      'face_pull': 'Face Pull',
      'deadlift': 'Deadlift',
      'rdl': 'Romanian Deadlift',
      'hyperextension': 'Hyperextension',

      // Shoulders
      'ohp': 'Overhead Press',
      'db_ohp': 'Dumbbell Overhead Press',
      'lat_raise': 'Lateral Raise',
      'front_raise': 'Front Raise',
      'rear_delt_fly': 'Rear Delt Fly',
      'upright_row': 'Upright Row',
      'arnold_press': 'Arnold Press',
      'shrug': 'Shrug',

      // Biceps
      'bb_curl': 'Barbell Curl',
      'db_curl': 'Dumbbell Curl',
      'hammer_curl': 'Hammer Curl',
      'preacher_curl': 'Preacher Curl',
      'cable_curl': 'Cable Curl',
      'concentration_curl': 'Concentration Curl',

      // Triceps
      'triceps_pushdown': 'Triceps Pushdown',
      'skull_crusher': 'Skull Crusher',
      'close_grip': 'Close Grip Bench Press',
      'triceps_extension': 'Triceps Extension',
      'bench_dip': 'Bench Dip',
      'kickback': 'Triceps Kickback',

      // Legs
      'squat': 'Squat',
      'front_squat': 'Front Squat',
      'leg_press': 'Leg Press',
      'romanian_dl': 'Romanian Deadlift',
      'leg_curl': 'Leg Curl',
      'leg_ext': 'Leg Extension',
      'bulgarian_split': 'Bulgarian Split Squat',
      'lunge': 'Lunge',
      'calf_raise': 'Calf Raise',
      'goblet_squat': 'Goblet Squat',
      'hack_squat': 'Hack Squat',
      'hip_thrust': 'Hip Thrust',

      // Core
      'crunch': 'Crunch',
      'leg_raise': 'Leg Raise',
      'plank': 'Plank',
      'russian_twist': 'Russian Twist',
      'cable_crunch': 'Cable Crunch',
      'ab_roller': 'Ab Wheel',
      'hanging_raise': 'Hanging Leg Raise',

      // Cardio
      'treadmill': 'Treadmill',
      'cycling': 'Cycling',
      'jump_rope': 'Jump Rope',
      'rowing': 'Rowing',
      'swimming': 'Swimming',
      'walking': 'Walking',
      'running': 'Running',
    },
    'pt': {
      // Chest
      'bench_press': 'Supino Reto',
      'incl_bench': 'Supino Inclinado',
      'decl_bench': 'Supino Declinado',
      'db_bench': 'Supino com Halteres',
      'db_incl': 'Supino Inclinado Halteres',
      'cable_fly': 'Crucifixo na Polia',
      'pec_deck': 'Pec Deck',
      'pushup': 'Flexão de Braço',
      'chest_dip': 'Mergulho no Banco',
      'sm_bench': 'Supino no Smith',

      // Back
      'pullup': 'Barra Fixa',
      'chinup': 'Barra Supinada',
      'lat_pulldown': 'Puxada Alta',
      'bent_row': 'Remada Curvada',
      'db_row': 'Remada Unilateral',
      'seated_row': 'Remada Sentada',
      'tbar_row': 'Remada T-Bar',
      'face_pull': 'Face Pull',
      'deadlift': 'Levantamento Terra',
      'rdl': 'Stiff (RDL)',
      'hyperextension': 'Hiperextensão',

      // Shoulders
      'ohp': 'Desenvolvimento Militar',
      'db_ohp': 'Desenvolvimento Halteres',
      'lat_raise': 'Elevação Lateral',
      'front_raise': 'Elevação Frontal',
      'rear_delt_fly': 'Crucifixo Invertido',
      'upright_row': 'Remada Alta',
      'arnold_press': 'Desenvolvimento Arnold',
      'shrug': 'Encolhimento',

      // Biceps
      'bb_curl': 'Rosca Direta',
      'db_curl': 'Rosca Halteres',
      'hammer_curl': 'Rosca Martelo',
      'preacher_curl': 'Rosca Scott',
      'cable_curl': 'Rosca na Polia',
      'concentration_curl': 'Rosca Concentrada',

      // Triceps
      'triceps_pushdown': 'Tríceps na Polia',
      'skull_crusher': 'Tríceps Francês',
      'close_grip': 'Supino Fechado',
      'triceps_extension': 'Tríceps Testa',
      'bench_dip': 'Mergulho no Banco',
      'kickback': 'Tríceps Coice',

      // Legs
      'squat': 'Agachamento',
      'front_squat': 'Agachamento Frontal',
      'leg_press': 'Leg Press 45°',
      'romanian_dl': 'Romanian Deadlift',
      'leg_curl': 'Mesa Flexora',
      'leg_ext': 'Cadeira Extensora',
      'bulgarian_split': 'Agachamento Búlgaro',
      'lunge': 'Afundo',
      'calf_raise': 'Elevação de Panturrilha',
      'goblet_squat': 'Agachamento Goblet',
      'hack_squat': 'Agachamento Hack',
      'hip_thrust': 'Elevação Pélvica',

      // Core
      'crunch': 'Crunch',
      'leg_raise': 'Elevação de Pernas',
      'plank': 'Prancha',
      'russian_twist': 'Torção Russa',
      'cable_crunch': 'Crunch na Polia',
      'ab_roller': 'Roda de Abdômen',
      'hanging_raise': 'Elevação de Pernas na Barra',

      // Cardio
      'treadmill': 'Esteira',
      'cycling': 'Bicicleta',
      'jump_rope': 'Pular Corda',
      'rowing': 'Remo',
      'swimming': 'Natação',
      'walking': 'Caminhada',
      'running': 'Corrida',
    },
  };

  // ===================================================================
  // EXERCISE NOTES (instructions)
  // ===================================================================

  static const Map<String, Map<String, String>> _exerciseNotes = {
    'en': {
      'bench_press': 'Lie on a flat bench, bar at nipple line',
      'incl_bench': 'Bench at 30-45°, focus on upper chest',
      'decl_bench': 'Decline bench, focus on lower chest',
      'db_bench': 'Greater range of motion than barbell',
      'db_incl': '',
      'cable_fly': 'High or medium pulley, squeeze at center',
      'pec_deck': 'Seated chest machine',
      'pushup': 'Vary hand width for different emphasis',
      'chest_dip': 'Lean forward to target chest',
      'sm_bench': '',
      'pullup': 'Pronated grip, hands shoulder-width',
      'chinup': 'Supinated grip, more biceps',
      'lat_pulldown': 'Pull bar to chest, elbows down',
      'bent_row': 'Torso at 45°, pull bar to abdomen',
      'db_row': 'Support knee and hand on bench',
      'seated_row': 'Pull cable to abdomen, squeeze shoulder blades',
      'tbar_row': '',
      'face_pull': 'Pull high cable toward face, great for posture',
      'deadlift': 'Bar on floor, straight back, lift with legs and back',
      'rdl': 'Straight legs, bar descending to shin',
      'hyperextension': 'Lower back and glutes',
      'ohp': 'Bar from front shoulders to overhead',
      'db_ohp': 'Seated or standing',
      'lat_raise': 'Dumbbells rising laterally to shoulder height',
      'front_raise': '',
      'rear_delt_fly': 'Machine or dumbbells, focus on rear deltoid',
      'upright_row': 'Bar rising close to body up to chin',
      'arnold_press': 'Dumbbells rotating during the movement',
      'shrug': 'Elevate shoulders, traps',
      'bb_curl': 'Straight or EZ bar',
      'db_curl': 'Alternating or simultaneous',
      'hammer_curl': 'Palms facing inward',
      'preacher_curl': 'Arms supported on Scott bench',
      'cable_curl': 'Low pulley, rope or bar',
      'concentration_curl': 'Seated, elbow resting on thigh',
      'triceps_pushdown': 'Rope or straight bar',
      'skull_crusher': 'Lying, bar descending to forehead',
      'close_grip': 'Hands close together, focus on triceps',
      'triceps_extension': 'Dumbbell behind head',
      'bench_dip': 'Bench behind, hands supported, lower with weight',
      'kickback': 'Torso inclined, fixed elbow',
      'squat': 'Bar on back, descend to parallel',
      'front_squat': 'Bar in front of shoulders',
      'leg_press': '',
      'romanian_dl': 'Focus on hamstrings and glutes',
      'leg_curl': 'Lying, flex legs',
      'leg_ext': 'Extend legs upward',
      'bulgarian_split': 'Back foot on bench, dumbbells in hands',
      'lunge': 'Long step, knee at 90°',
      'calf_raise': 'Standing or seated',
      'goblet_squat': 'Dumbbell or kettlebell in front of chest',
      'hack_squat': '',
      'hip_thrust': 'Bar on hips, glutes',
      'crunch': 'Basic, hands behind neck',
      'leg_raise': 'Lying, straight legs rising',
      'plank': 'Hold position, body straight',
      'russian_twist': 'Seated, twisting torso with weight',
      'cable_crunch': 'High pulley, pull toward floor',
      'ab_roller': 'Kneeling or standing',
      'hanging_raise': 'Hanging from bar, legs rising',
      'treadmill': 'Walking or running',
      'cycling': 'Stationary or outdoor',
      'jump_rope': '',
      'rowing': 'Rowing machine',
      'swimming': '',
      'walking': '',
      'running': 'Outdoor running or treadmill',
    },
    'pt': {
      'bench_press': 'Deite no banco reto, barra na linha do mamilo',
      'incl_bench': 'Banco a 30-45°, foco no peito superior',
      'decl_bench': 'Banco declinado, foco no peito inferior',
      'db_bench': 'Maior amplitude que barra',
      'db_incl': '',
      'cable_fly': 'Polia alta ou média, contração no centro',
      'pec_deck': 'Máquina de peito sentado',
      'pushup': 'Pode variar largura das mãos',
      'chest_dip': 'Tronco inclinado para frente foca peito',
      'sm_bench': '',
      'pullup': 'Pegada pronada, mãos na largura dos ombros',
      'chinup': 'Pegada supinada, mais bíceps',
      'lat_pulldown': 'Puxar barra até o peito, cotovelos para baixo',
      'bent_row': 'Tronco a 45°, barra até o abdômen',
      'db_row': 'Apoie joelho e mão no banco',
      'seated_row': 'Puxar polia até o abdômen, contrair escápulas',
      'tbar_row': '',
      'face_pull': 'Puxar polia alta em direção ao rosto, ótimo para postura',
      'deadlift': 'Barra no chão, costas retas, levantar com pernas e costas',
      'rdl': 'Pernas esticadas, barra descendo até canela',
      'hyperextension': 'Lombar e glúteos',
      'ohp': 'Barra da frente dos ombros até acima da cabeça',
      'db_ohp': 'Sentado ou em pé',
      'lat_raise': 'Halteres subindo lateralmente até altura dos ombros',
      'front_raise': '',
      'rear_delt_fly': 'Máquina ou halteres, foco no deltoide posterior',
      'upright_row': 'Barra subindo rente ao corpo até o queixo',
      'arnold_press': 'Halteres girando durante o movimento',
      'shrug': 'Elevar os ombros, trapézio',
      'bb_curl': 'Barra reta ou W',
      'db_curl': 'Alternada ou simultânea',
      'hammer_curl': 'Palmas viradas para dentro',
      'preacher_curl': 'Braços apoiados no banco Scott',
      'cable_curl': 'Polia baixa, corda ou barra',
      'concentration_curl': 'Sentado, cotovelo apoiado na coxa',
      'triceps_pushdown': 'Corda ou barra reta',
      'skull_crusher': 'Deitado, barra descendo até a testa',
      'close_grip': 'Mãos próximas, foco no tríceps',
      'triceps_extension': 'Halter atrás da cabeça',
      'bench_dip': 'Banco atrás, mãos apoiadas, descer com peso',
      'kickback': 'Tronco inclinado, cotovelo fixo',
      'squat': 'Barra nas costas, descer até paralelo',
      'front_squat': 'Barra na frente dos ombros',
      'leg_press': '',
      'romanian_dl': 'Foco em posterior e glúteo',
      'leg_curl': 'Deitado, flexionar pernas',
      'leg_ext': 'Pernas estendendo para cima',
      'bulgarian_split': 'Pé de trás no banco, halteres nas mãos',
      'lunge': 'Passo largo, joelho 90°',
      'calf_raise': 'Em pé ou sentado',
      'goblet_squat': 'Halter ou kettlebell na frente do peito',
      'hack_squat': '',
      'hip_thrust': 'Barra apoiada no quadril, glúteo',
      'crunch': 'Básico, mãos na nuca',
      'leg_raise': 'Deitado, pernas esticadas subindo',
      'plank': 'Manter posição, corpo reto',
      'russian_twist': 'Sentado, girando tronco com peso',
      'cable_crunch': 'Polia alta, puxar em direção ao chão',
      'ab_roller': 'Joelhos ou em pé',
      'hanging_raise': 'Pendurado na barra, pernas subindo',
      'treadmill': 'Caminhada ou corrida',
      'cycling': 'Ergométrica ou rua',
      'jump_rope': '',
      'rowing': 'Máquina de remo',
      'swimming': '',
      'walking': '',
      'running': 'Corrida ao ar livre ou esteira',
    },
  };

  // ===================================================================
  // CATEGORY NAMES
  // ===================================================================

  static const Map<String, Map<String, String>> _categoryNames = {
    'en': {
      'chest': 'Chest',
      'back': 'Back',
      'shoulders': 'Shoulders',
      'biceps': 'Biceps',
      'triceps': 'Triceps',
      'legs': 'Legs',
      'core': 'Core',
      'cardio': 'Cardio',
      'fullbody': 'Full Body',
    },
    'pt': {
      'chest': 'Peito',
      'back': 'Costas',
      'shoulders': 'Ombros',
      'biceps': 'Bíceps',
      'triceps': 'Tríceps',
      'legs': 'Pernas',
      'core': 'Abdômen',
      'cardio': 'Cardio',
      'fullbody': 'Corpo Inteiro',
    },
  };
}
