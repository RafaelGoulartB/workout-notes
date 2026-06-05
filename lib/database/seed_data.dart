class SeedData {
  static const categories = [
    {'id': 'chest', 'name': 'Peito', 'color': 0xFFE53935, 'order_index': 0, 'energy_system': 'anaerobic'},
    {'id': 'back', 'name': 'Costas', 'color': 0xFF43A047, 'order_index': 1, 'energy_system': 'anaerobic'},
    {'id': 'shoulders', 'name': 'Ombros', 'color': 0xFFFB8C00, 'order_index': 2, 'energy_system': 'anaerobic'},
    {'id': 'biceps', 'name': 'Bíceps', 'color': 0xFF8E24AA, 'order_index': 3, 'energy_system': 'anaerobic'},
    {'id': 'triceps', 'name': 'Tríceps', 'color': 0xFF00ACC1, 'order_index': 4, 'energy_system': 'anaerobic'},
    {'id': 'legs', 'name': 'Pernas', 'color': 0xFF3949AB, 'order_index': 5, 'energy_system': 'anaerobic'},
    {'id': 'core', 'name': 'Abdômen', 'color': 0xFFFDD835, 'order_index': 6, 'energy_system': 'anaerobic'},
    {'id': 'cardio', 'name': 'Cardio', 'color': 0xFF6D4C41, 'order_index': 7, 'energy_system': 'aerobic'},
    {'id': 'fullbody', 'name': 'Corpo Inteiro', 'color': 0xFF546E7A, 'order_index': 8, 'energy_system': 'anaerobic'},
  ];

  static const exercises = [
    // === CHEST ===
    {'id': 'bench_press', 'name': 'Supino Reto', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Deite no banco reto, barra na linha do mamilo', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'incl_bench', 'name': 'Supino Inclinado', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Banco a 30-45°, foco no peito superior', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'decl_bench', 'name': 'Supino Declinado', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Banco declinado, foco no peito inferior', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'db_bench', 'name': 'Supino com Halteres', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Maior amplitude que barra', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 1.0},
    {'id': 'db_incl', 'name': 'Supino Inclinado Halteres', 'category_id': 'chest', 'type': 'weightReps', 'notes': '', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 1.0},
    {'id': 'cable_fly', 'name': 'Crucifixo na Polia', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Polia alta ou média, contração no centro', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'pec_deck', 'name': 'Pec Deck', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Máquina de peito sentado', 'equipment': 'Machine', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'pushup', 'name': 'Flexão de Braço', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Pode variar largura das mãos', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'chest_dip', 'name': 'Mergulho no Banco', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Tronco inclinado para frente foca peito', 'equipment': 'Bodyweight', 'default_rest_time': 90, 'weight_increment': 0},
    {'id': 'sm_bench', 'name': 'Supino no Smith', 'category_id': 'chest', 'type': 'weightReps', 'notes': '', 'equipment': 'Machine', 'default_rest_time': 90, 'weight_increment': 2.5},

    // === BACK ===
    {'id': 'pullup', 'name': 'Barra Fixa', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Pegada pronada, mãos na largura dos ombros', 'equipment': 'Bodyweight', 'default_rest_time': 120, 'weight_increment': 0},
    {'id': 'chinup', 'name': 'Barra Supinada', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Pegada supinada, mais bíceps', 'equipment': 'Bodyweight', 'default_rest_time': 120, 'weight_increment': 0},
    {'id': 'lat_pulldown', 'name': 'Puxada Alta', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Puxar barra até o peito, cotovelos para baixo', 'equipment': 'Cable', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'bent_row', 'name': 'Remada Curvada', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Tronco a 45°, barra até o abdômen', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'db_row', 'name': 'Remada Unilateral', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Apoie joelho e mão no banco', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 2.0},
    {'id': 'seated_row', 'name': 'Remada Sentada', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Puxar polia até o abdômen, contrair escápulas', 'equipment': 'Cable', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'tbar_row', 'name': 'Remada T-Bar', 'category_id': 'back', 'type': 'weightReps', 'notes': '', 'equipment': 'Barbell', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'face_pull', 'name': 'Face Pull', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Puxar polia alta em direção ao rosto, ótimo para postura', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'deadlift', 'name': 'Levantamento Terra', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Barra no chão, costas retas, levantar com pernas e costas', 'equipment': 'Barbell', 'default_rest_time': 180, 'weight_increment': 5.0},
    {'id': 'rdl', 'name': 'Stiff (RDL)', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Pernas esticadas, barra descendo até canela', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'hyperextension', 'name': 'Hiperextensão', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Lombar e glúteos', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},

    // === SHOULDERS ===
    {'id': 'ohp', 'name': 'Desenvolvimento Militar', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Barra da frente dos ombros até acima da cabeça', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'db_ohp', 'name': 'Desenvolvimento Halteres', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Sentado ou em pé', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 1.0},
    {'id': 'lat_raise', 'name': 'Elevação Lateral', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Halteres subindo lateralmente até altura dos ombros', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'front_raise', 'name': 'Elevação Frontal', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': '', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'rear_delt_fly', 'name': 'Crucifixo Invertido', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Máquina ou halteres, foco no deltoide posterior', 'equipment': 'Machine', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'upright_row', 'name': 'Remada Alta', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Barra subindo rente ao corpo até o queixo', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'arnold_press', 'name': 'Desenvolvimento Arnold', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Halteres girando durante o movimento', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 1.0},
    {'id': 'shrug', 'name': 'Encolhimento', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Elevar os ombros, trapézio', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 5.0},

    // === BICEPS ===
    {'id': 'bb_curl', 'name': 'Rosca Direta', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Barra reta ou W', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'db_curl', 'name': 'Rosca Halteres', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Alternada ou simultânea', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'hammer_curl', 'name': 'Rosca Martelo', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Palmas viradas para dentro', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'preacher_curl', 'name': 'Rosca Scott', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Braços apoiados no banco Scott', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'cable_curl', 'name': 'Rosca na Polia', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Polia baixa, corda ou barra', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'concentration_curl', 'name': 'Rosca Concentrada', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Sentado, cotovelo apoiado na coxa', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},

    // === TRICEPS ===
    {'id': 'triceps_pushdown', 'name': 'Tríceps na Polia', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Corda ou barra reta', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'skull_crusher', 'name': 'Tríceps Francês', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Deitado, barra descendo até a testa', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'close_grip', 'name': 'Supino Fechado', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Mãos próximas, foco no tríceps', 'equipment': 'Barbell', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'triceps_extension', 'name': 'Tríceps Testa', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Halter atrás da cabeça', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'bench_dip', 'name': 'Mergulho no Banco', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Banco atrás, mãos apoiadas, descer com peso', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'kickback', 'name': 'Tríceps Coice', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Tronco inclinado, cotovelo fixo', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},

    // === LEGS ===
    {'id': 'squat', 'name': 'Agachamento', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Barra nas costas, descer até paralelo', 'equipment': 'Barbell', 'default_rest_time': 180, 'weight_increment': 5.0},
    {'id': 'front_squat', 'name': 'Agachamento Frontal', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Barra na frente dos ombros', 'equipment': 'Barbell', 'default_rest_time': 180, 'weight_increment': 2.5},
    {'id': 'leg_press', 'name': 'Leg Press 45°', 'category_id': 'legs', 'type': 'weightReps', 'notes': '', 'equipment': 'Machine', 'default_rest_time': 120, 'weight_increment': 10.0},
    {'id': 'romanian_dl', 'name': 'Romanian Deadlift', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Foco em posterior e glúteo', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'leg_curl', 'name': 'Mesa Flexora', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Deitado, flexionar pernas', 'equipment': 'Machine', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'leg_ext', 'name': 'Cadeira Extensora', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Pernas estendendo para cima', 'equipment': 'Machine', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'bulgarian_split', 'name': 'Agachamento Búlgaro', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Pé de trás no banco, halteres nas mãos', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 2.0},
    {'id': 'lunge', 'name': 'Afundo', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Passo largo, joelho 90°', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 2.0},
    {'id': 'calf_raise', 'name': 'Elevação de Panturrilha', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Em pé ou sentado', 'equipment': 'Machine', 'default_rest_time': 60, 'weight_increment': 5.0},
    {'id': 'goblet_squat', 'name': 'Agachamento Goblet', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Halter ou kettlebell na frente do peito', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 2.0},
    {'id': 'hack_squat', 'name': 'Agachamento Hack', 'category_id': 'legs', 'type': 'weightReps', 'notes': '', 'equipment': 'Machine', 'default_rest_time': 120, 'weight_increment': 5.0},
    {'id': 'hip_thrust', 'name': 'Elevação Pélvica', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Barra apoiada no quadril, glúteo', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 5.0},

    // === CORE ===
    {'id': 'crunch', 'name': 'Crunch', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Básico, mãos na nuca', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'leg_raise', 'name': 'Elevação de Pernas', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Deitado, pernas esticadas subindo', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'plank', 'name': 'Prancha', 'category_id': 'core', 'type': 'timeOnly', 'notes': 'Manter posição, corpo reto', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'russian_twist', 'name': 'Torção Russa', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Sentado, girando tronco com peso', 'equipment': 'Dumbbell', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'cable_crunch', 'name': 'Crunch na Polia', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Polia alta, puxar em direção ao chão', 'equipment': 'Cable', 'default_rest_time': 45, 'weight_increment': 2.5},
    {'id': 'ab_roller', 'name': 'Roda de Abdômen', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Joelhos ou em pé', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'hanging_raise', 'name': 'Elevação de Pernas na Barra', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Pendurado na barra, pernas subindo', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},

    // === CARDIO ===
    {'id': 'treadmill', 'name': 'Esteira', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': 'Caminhada ou corrida', 'equipment': 'Treadmill', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'cycling', 'name': 'Bicicleta', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': 'Ergométrica ou rua', 'equipment': 'Stationary', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'jump_rope', 'name': 'Pular Corda', 'category_id': 'cardio', 'type': 'timeOnly', 'notes': '', 'equipment': 'Bodyweight', 'default_rest_time': 30, 'weight_increment': 0},
    {'id': 'rowing', 'name': 'Remo', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': 'Máquina de remo', 'equipment': 'Machine', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'swimming', 'name': 'Natação', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': '', 'equipment': 'Bodyweight', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'walking', 'name': 'Caminhada', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': '', 'equipment': 'Bodyweight', 'default_rest_time': 0, 'weight_increment': 0},
  ];
}
