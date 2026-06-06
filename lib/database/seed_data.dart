class SeedData {
  static const categories = [
    {'id': 'chest', 'name': 'Peito', 'locale_key': 'chest', 'color': 0xFFE53935, 'order_index': 0, 'energy_system': 'anaerobic'},
    {'id': 'back', 'name': 'Costas', 'locale_key': 'back', 'color': 0xFF43A047, 'order_index': 1, 'energy_system': 'anaerobic'},
    {'id': 'shoulders', 'name': 'Ombros', 'locale_key': 'shoulders', 'color': 0xFFFB8C00, 'order_index': 2, 'energy_system': 'anaerobic'},
    {'id': 'biceps', 'name': 'Bíceps', 'locale_key': 'biceps', 'color': 0xFF8E24AA, 'order_index': 3, 'energy_system': 'anaerobic'},
    {'id': 'triceps', 'name': 'Tríceps', 'locale_key': 'triceps', 'color': 0xFF00ACC1, 'order_index': 4, 'energy_system': 'anaerobic'},
    {'id': 'legs', 'name': 'Pernas', 'locale_key': 'legs', 'color': 0xFF3949AB, 'order_index': 5, 'energy_system': 'anaerobic'},
    {'id': 'core', 'name': 'Abdômen', 'locale_key': 'core', 'color': 0xFFFDD835, 'order_index': 6, 'energy_system': 'anaerobic'},
    {'id': 'cardio', 'name': 'Cardio', 'locale_key': 'cardio', 'color': 0xFF6D4C41, 'order_index': 7, 'energy_system': 'aerobic'},
    {'id': 'fullbody', 'name': 'Corpo Inteiro', 'locale_key': 'fullbody', 'color': 0xFF546E7A, 'order_index': 8, 'energy_system': 'anaerobic'},
  ];

  static const exercises = [
    // === CHEST ===
    {'id': 'bench_press', 'name': 'Supino Reto', 'locale_key': 'bench_press', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Deite no banco reto, barra na linha do mamilo', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'incl_bench', 'name': 'Supino Inclinado', 'locale_key': 'incl_bench', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Banco a 30-45°, foco no peito superior', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'decl_bench', 'name': 'Supino Declinado', 'locale_key': 'decl_bench', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Banco declinado, foco no peito inferior', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'db_bench', 'name': 'Supino com Halteres', 'locale_key': 'db_bench', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Maior amplitude que barra', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 1.0},
    {'id': 'db_incl', 'name': 'Supino Inclinado Halteres', 'locale_key': 'db_incl', 'category_id': 'chest', 'type': 'weightReps', 'notes': '', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 1.0},
    {'id': 'cable_fly', 'name': 'Crucifixo na Polia', 'locale_key': 'cable_fly', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Polia alta ou média, contração no centro', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'pec_deck', 'name': 'Pec Deck', 'locale_key': 'pec_deck', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Máquina de peito sentado', 'equipment': 'Machine', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'pushup', 'name': 'Flexão de Braço', 'locale_key': 'pushup', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Pode variar largura das mãos', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'chest_dip', 'name': 'Mergulho no Banco', 'locale_key': 'chest_dip', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Tronco inclinado para frente foca peito', 'equipment': 'Bodyweight', 'default_rest_time': 90, 'weight_increment': 0},
    {'id': 'sm_bench', 'name': 'Supino no Smith', 'locale_key': 'sm_bench', 'category_id': 'chest', 'type': 'weightReps', 'notes': '', 'equipment': 'Machine', 'default_rest_time': 90, 'weight_increment': 2.5},

    // === BACK ===
    {'id': 'pullup', 'name': 'Barra Fixa', 'locale_key': 'pullup', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Pegada pronada, mãos na largura dos ombros', 'equipment': 'Bodyweight', 'default_rest_time': 120, 'weight_increment': 0},
    {'id': 'chinup', 'name': 'Barra Supinada', 'locale_key': 'chinup', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Pegada supinada, mais bíceps', 'equipment': 'Bodyweight', 'default_rest_time': 120, 'weight_increment': 0},
    {'id': 'lat_pulldown', 'name': 'Puxada Alta', 'locale_key': 'lat_pulldown', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Puxar barra até o peito, cotovelos para baixo', 'equipment': 'Cable', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'bent_row', 'name': 'Remada Curvada', 'locale_key': 'bent_row', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Tronco a 45°, barra até o abdômen', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'db_row', 'name': 'Remada Unilateral', 'locale_key': 'db_row', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Apoie joelho e mão no banco', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 2.0},
    {'id': 'seated_row', 'name': 'Remada Sentada', 'locale_key': 'seated_row', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Puxar polia até o abdômen, contrair escápulas', 'equipment': 'Cable', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'tbar_row', 'name': 'Remada T-Bar', 'locale_key': 'tbar_row', 'category_id': 'back', 'type': 'weightReps', 'notes': '', 'equipment': 'Barbell', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'face_pull', 'name': 'Face Pull', 'locale_key': 'face_pull', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Puxar polia alta em direção ao rosto, ótimo para postura', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'deadlift', 'name': 'Levantamento Terra', 'locale_key': 'deadlift', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Barra no chão, costas retas, levantar com pernas e costas', 'equipment': 'Barbell', 'default_rest_time': 180, 'weight_increment': 5.0},
    {'id': 'rdl', 'name': 'Stiff (RDL)', 'locale_key': 'rdl', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Pernas esticadas, barra descendo até canela', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'hyperextension', 'name': 'Hiperextensão', 'locale_key': 'hyperextension', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Lombar e glúteos', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},

    // === SHOULDERS ===
    {'id': 'ohp', 'name': 'Desenvolvimento Militar', 'locale_key': 'ohp', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Barra da frente dos ombros até acima da cabeça', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'db_ohp', 'name': 'Desenvolvimento Halteres', 'locale_key': 'db_ohp', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Sentado ou em pé', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 1.0},
    {'id': 'lat_raise', 'name': 'Elevação Lateral', 'locale_key': 'lat_raise', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Halteres subindo lateralmente até altura dos ombros', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'front_raise', 'name': 'Elevação Frontal', 'locale_key': 'front_raise', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': '', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'rear_delt_fly', 'name': 'Crucifixo Invertido', 'locale_key': 'rear_delt_fly', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Máquina ou halteres, foco no deltoide posterior', 'equipment': 'Machine', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'upright_row', 'name': 'Remada Alta', 'locale_key': 'upright_row', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Barra subindo rente ao corpo até o queixo', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'arnold_press', 'name': 'Desenvolvimento Arnold', 'locale_key': 'arnold_press', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Halteres girando durante o movimento', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 1.0},
    {'id': 'shrug', 'name': 'Encolhimento', 'locale_key': 'shrug', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Elevar os ombros, trapézio', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 5.0},

    // === BICEPS ===
    {'id': 'bb_curl', 'name': 'Rosca Direta', 'locale_key': 'bb_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Barra reta ou W', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'db_curl', 'name': 'Rosca Halteres', 'locale_key': 'db_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Alternada ou simultânea', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'hammer_curl', 'name': 'Rosca Martelo', 'locale_key': 'hammer_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Palmas viradas para dentro', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'preacher_curl', 'name': 'Rosca Scott', 'locale_key': 'preacher_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Braços apoiados no banco Scott', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'cable_curl', 'name': 'Rosca na Polia', 'locale_key': 'cable_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Polia baixa, corda ou barra', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'concentration_curl', 'name': 'Rosca Concentrada', 'locale_key': 'concentration_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Sentado, cotovelo apoiado na coxa', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},

    // === TRICEPS ===
    {'id': 'triceps_pushdown', 'name': 'Tríceps na Polia', 'locale_key': 'triceps_pushdown', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Corda ou barra reta', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'skull_crusher', 'name': 'Tríceps Francês', 'locale_key': 'skull_crusher', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Deitado, barra descendo até a testa', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'close_grip', 'name': 'Supino Fechado', 'locale_key': 'close_grip', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Mãos próximas, foco no tríceps', 'equipment': 'Barbell', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'triceps_extension', 'name': 'Tríceps Testa', 'locale_key': 'triceps_extension', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Halter atrás da cabeça', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'bench_dip', 'name': 'Mergulho no Banco', 'locale_key': 'bench_dip', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Banco atrás, mãos apoiadas, descer com peso', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'kickback', 'name': 'Tríceps Coice', 'locale_key': 'kickback', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Tronco inclinado, cotovelo fixo', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},

    // === LEGS ===
    {'id': 'squat', 'name': 'Agachamento', 'locale_key': 'squat', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Barra nas costas, descer até paralelo', 'equipment': 'Barbell', 'default_rest_time': 180, 'weight_increment': 5.0},
    {'id': 'front_squat', 'name': 'Agachamento Frontal', 'locale_key': 'front_squat', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Barra na frente dos ombros', 'equipment': 'Barbell', 'default_rest_time': 180, 'weight_increment': 2.5},
    {'id': 'leg_press', 'name': 'Leg Press 45°', 'locale_key': 'leg_press', 'category_id': 'legs', 'type': 'weightReps', 'notes': '', 'equipment': 'Machine', 'default_rest_time': 120, 'weight_increment': 10.0},
    {'id': 'romanian_dl', 'name': 'Romanian Deadlift', 'locale_key': 'romanian_dl', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Foco em posterior e glúteo', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'leg_curl', 'name': 'Mesa Flexora', 'locale_key': 'leg_curl', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Deitado, flexionar pernas', 'equipment': 'Machine', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'leg_ext', 'name': 'Cadeira Extensora', 'locale_key': 'leg_ext', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Pernas estendendo para cima', 'equipment': 'Machine', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'bulgarian_split', 'name': 'Agachamento Búlgaro', 'locale_key': 'bulgarian_split', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Pé de trás no banco, halteres nas mãos', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 2.0},
    {'id': 'lunge', 'name': 'Afundo', 'locale_key': 'lunge', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Passo largo, joelho 90°', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 2.0},
    {'id': 'calf_raise', 'name': 'Elevação de Panturrilha', 'locale_key': 'calf_raise', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Em pé ou sentado', 'equipment': 'Machine', 'default_rest_time': 60, 'weight_increment': 5.0},
    {'id': 'goblet_squat', 'name': 'Agachamento Goblet', 'locale_key': 'goblet_squat', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Halter ou kettlebell na frente do peito', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 2.0},
    {'id': 'hack_squat', 'name': 'Agachamento Hack', 'locale_key': 'hack_squat', 'category_id': 'legs', 'type': 'weightReps', 'notes': '', 'equipment': 'Machine', 'default_rest_time': 120, 'weight_increment': 5.0},
    {'id': 'hip_thrust', 'name': 'Elevação Pélvica', 'locale_key': 'hip_thrust', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Barra apoiada no quadril, glúteo', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 5.0},

    // === CORE ===
    {'id': 'crunch', 'name': 'Crunch', 'locale_key': 'crunch', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Básico, mãos na nuca', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'leg_raise', 'name': 'Elevação de Pernas', 'locale_key': 'leg_raise', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Deitado, pernas esticadas subindo', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'plank', 'name': 'Prancha', 'locale_key': 'plank', 'category_id': 'core', 'type': 'timeOnly', 'notes': 'Manter posição, corpo reto', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'russian_twist', 'name': 'Torção Russa', 'locale_key': 'russian_twist', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Sentado, girando tronco com peso', 'equipment': 'Dumbbell', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'cable_crunch', 'name': 'Crunch na Polia', 'locale_key': 'cable_crunch', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Polia alta, puxar em direção ao chão', 'equipment': 'Cable', 'default_rest_time': 45, 'weight_increment': 2.5},
    {'id': 'ab_roller', 'name': 'Roda de Abdômen', 'locale_key': 'ab_roller', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Joelhos ou em pé', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'hanging_raise', 'name': 'Elevação de Pernas na Barra', 'locale_key': 'hanging_raise', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Pendurado na barra, pernas subindo', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},

    // === CARDIO ===
    {'id': 'treadmill', 'name': 'Esteira', 'locale_key': 'treadmill', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': 'Caminhada ou corrida', 'equipment': 'Treadmill', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'cycling', 'name': 'Bicicleta', 'locale_key': 'cycling', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': 'Ergométrica ou rua', 'equipment': 'Stationary', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'jump_rope', 'name': 'Pular Corda', 'locale_key': 'jump_rope', 'category_id': 'cardio', 'type': 'timeOnly', 'notes': '', 'equipment': 'Bodyweight', 'default_rest_time': 30, 'weight_increment': 0},
    {'id': 'rowing', 'name': 'Remo', 'locale_key': 'rowing', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': 'Máquina de remo', 'equipment': 'Machine', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'swimming', 'name': 'Natação', 'locale_key': 'swimming', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': '', 'equipment': 'Bodyweight', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'walking', 'name': 'Caminhada', 'locale_key': 'walking', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': '', 'equipment': 'Bodyweight', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'running', 'name': 'Corrida', 'locale_key': 'running', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': 'Corrida ao ar livre ou esteira', 'equipment': 'Bodyweight', 'default_rest_time': 0, 'weight_increment': 0},
  ];
}

