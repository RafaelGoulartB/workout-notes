class SeedData {
  static const categories = [
    {'id': 'chest', 'name': 'Peito', 'locale_key': 'chest', 'color': 0xFFE53935, 'order_index': 0, 'energy_system': 'anaerobic'},
    {'id': 'back', 'name': 'Costas', 'locale_key': 'back', 'color': 0xFF43A047, 'order_index': 1, 'energy_system': 'anaerobic'},
    {'id': 'shoulders', 'name': 'Ombros', 'locale_key': 'shoulders', 'color': 0xFFFB8C00, 'order_index': 2, 'energy_system': 'anaerobic'},
    {'id': 'biceps', 'name': 'Bíceps', 'locale_key': 'biceps', 'color': 0xFF8E24AA, 'order_index': 3, 'energy_system': 'anaerobic'},
    {'id': 'triceps', 'name': 'Tríceps', 'locale_key': 'triceps', 'color': 0xFF00ACC1, 'order_index': 4, 'energy_system': 'anaerobic'},
    {'id': 'legs', 'name': 'Pernas', 'locale_key': 'legs', 'color': 0xFF3949AB, 'order_index': 5, 'energy_system': 'anaerobic'},
    {'id': 'core', 'name': 'Abdômen', 'locale_key': 'core', 'color': 0xFFFDD835, 'order_index': 6, 'energy_system': 'anaerobic'},
    {'id': 'cardio', 'name': 'Cardio', 'locale_key': 'cardio', 'color': 0xFFE53935, 'order_index': 7, 'energy_system': 'aerobic'},
    {'id': 'fullbody', 'name': 'Corpo Inteiro', 'locale_key': 'fullbody', 'color': 0xFF546E7A, 'order_index': 8, 'energy_system': 'anaerobic'},
    {'id': 'forearms', 'name': 'Antebraço', 'locale_key': 'forearms', 'color': 0xFF8D6E63, 'order_index': 9, 'energy_system': 'anaerobic'},
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

    {'id': 'db_fly', 'name': 'Crucifixo com Halteres', 'locale_key': 'db_fly', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Deitado no banco, halteres abertos e fechando no centro', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'pullover', 'name': 'Pullover', 'locale_key': 'pullover', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Deitado no banco, halter atrás da cabeça', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 2.0},

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

    {'id': 'straight_arm_pulldown', 'name': 'Puxada Braço Reto', 'locale_key': 'straight_arm_pulldown', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Polia alta, braços esticados puxando até a coxa', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'good_morning', 'name': 'Good Morning', 'locale_key': 'good_morning', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Barra nas costas, tronco inclinando para frente', 'equipment': 'Barbell', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'inverted_row', 'name': 'Remada Invertida', 'locale_key': 'inverted_row', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Barra baixa, puxar o peito até a barra', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},

    // === SHOULDERS ===
    {'id': 'ohp', 'name': 'Desenvolvimento Militar', 'locale_key': 'ohp', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Barra da frente dos ombros até acima da cabeça', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'db_ohp', 'name': 'Desenvolvimento Halteres', 'locale_key': 'db_ohp', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Sentado ou em pé', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 1.0},
    {'id': 'lat_raise', 'name': 'Elevação Lateral', 'locale_key': 'lat_raise', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Halteres subindo lateralmente até altura dos ombros', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'front_raise', 'name': 'Elevação Frontal', 'locale_key': 'front_raise', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': '', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'rear_delt_fly', 'name': 'Crucifixo Invertido', 'locale_key': 'rear_delt_fly', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Máquina ou halteres, foco no deltoide posterior', 'equipment': 'Machine', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'upright_row', 'name': 'Remada Alta', 'locale_key': 'upright_row', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Barra subindo rente ao corpo até o queixo', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'arnold_press', 'name': 'Desenvolvimento Arnold', 'locale_key': 'arnold_press', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Halteres girando durante o movimento', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 1.0},
    {'id': 'shrug', 'name': 'Encolhimento', 'locale_key': 'shrug', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Elevar os ombros, trapézio', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 5.0},

    {'id': 'cable_lat_raise', 'name': 'Elevação Lateral na Polia', 'locale_key': 'cable_lat_raise', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Polia baixa, elevar lateralmente', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'machine_ohp', 'name': 'Desenvolvimento na Máquina', 'locale_key': 'machine_ohp', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Máquina de ombro sentado', 'equipment': 'Machine', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'landmine_press', 'name': 'Desenvolvimento com Barra no Chão', 'locale_key': 'landmine_press', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Barra apoiada no chão, pressionar em ângulo', 'equipment': 'Barbell', 'default_rest_time': 90, 'weight_increment': 2.5},

    // === BICEPS ===
    {'id': 'bb_curl', 'name': 'Rosca Direta', 'locale_key': 'bb_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Barra reta ou W', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'db_curl', 'name': 'Rosca Halteres', 'locale_key': 'db_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Alternada ou simultânea', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'hammer_curl', 'name': 'Rosca Martelo', 'locale_key': 'hammer_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Palmas viradas para dentro', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'preacher_curl', 'name': 'Rosca Scott', 'locale_key': 'preacher_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Braços apoiados no banco Scott', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'cable_curl', 'name': 'Rosca na Polia', 'locale_key': 'cable_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Polia baixa, corda ou barra', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'concentration_curl', 'name': 'Rosca Concentrada', 'locale_key': 'concentration_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Sentado, cotovelo apoiado na coxa', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},

    {'id': 'incline_curl', 'name': 'Rosca Inclinada', 'locale_key': 'incline_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Banco inclinado a 45°, braços pendurados para trás', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'reverse_curl', 'name': 'Rosca Inversa', 'locale_key': 'reverse_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Barra com pegada pronada, foco no braquial', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'spider_curl', 'name': 'Rosca Spider', 'locale_key': 'spider_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Banco inclinado, braços pendurados na vertical', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},

    // === TRICEPS ===
    {'id': 'triceps_pushdown', 'name': 'Tríceps na Polia', 'locale_key': 'triceps_pushdown', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Corda ou barra reta', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'skull_crusher', 'name': 'Tríceps Francês', 'locale_key': 'skull_crusher', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Deitado, barra descendo até a testa', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'close_grip', 'name': 'Supino Fechado', 'locale_key': 'close_grip', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Mãos próximas, foco no tríceps', 'equipment': 'Barbell', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'triceps_extension', 'name': 'Tríceps Testa', 'locale_key': 'triceps_extension', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Halter atrás da cabeça', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'bench_dip', 'name': 'Mergulho no Banco', 'locale_key': 'bench_dip', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Banco atrás, mãos apoiadas, descer com peso', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'kickback', 'name': 'Tríceps Coice', 'locale_key': 'kickback', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Tronco inclinado, cotovelo fixo', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},

    {'id': 'overhead_cable_ext', 'name': 'Tríceps Polia Alta', 'locale_key': 'overhead_cable_ext', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Corda ou barra atrás da cabeça, estender acima', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'single_pushdown', 'name': 'Tríceps Polia Unilateral', 'locale_key': 'single_pushdown', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Cada braço de cada vez, maior foco', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'diamond_pushup', 'name': 'Flexão Diamante', 'locale_key': 'diamond_pushup', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Mãos juntas formando um diamante, foco no tríceps', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},

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

    {'id': 'adductor_machine', 'name': 'Máquina de Adutor', 'locale_key': 'adductor_machine', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Fechar as pernas contra a resistência', 'equipment': 'Machine', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'abductor_machine', 'name': 'Máquina de Abdutor', 'locale_key': 'abductor_machine', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Abrir as pernas contra a resistência', 'equipment': 'Machine', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'seated_calf', 'name': 'Panturrilha Sentado', 'locale_key': 'seated_calf', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Joelhos a 90°, elevar os calcanhares', 'equipment': 'Machine', 'default_rest_time': 60, 'weight_increment': 5.0},
    {'id': 'glute_bridge', 'name': 'Ponte de Glúteo', 'locale_key': 'glute_bridge', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Deitado, joelhos flexionados, elevar o quadril', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'step_up', 'name': 'Step Up', 'locale_key': 'step_up', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Subir em um banco ou caixa, halteres nas mãos', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 2.0},
    {'id': 'nordic_curl', 'name': 'Flexão Nórdica', 'locale_key': 'nordic_curl', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Joelhos no chão, pés presos, descer controlado', 'equipment': 'Bodyweight', 'default_rest_time': 90, 'weight_increment': 0},
    {'id': 'reverse_lunge', 'name': 'Afundo Reverso', 'locale_key': 'reverse_lunge', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Passo para trás em vez de frente', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 2.0},

    // === CORE ===
    {'id': 'crunch', 'name': 'Crunch', 'locale_key': 'crunch', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Básico, mãos na nuca', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'leg_raise', 'name': 'Elevação de Pernas', 'locale_key': 'leg_raise', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Deitado, pernas esticadas subindo', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'plank', 'name': 'Prancha', 'locale_key': 'plank', 'category_id': 'core', 'type': 'timeOnly', 'notes': 'Manter posição, corpo reto', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'russian_twist', 'name': 'Torção Russa', 'locale_key': 'russian_twist', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Sentado, girando tronco com peso', 'equipment': 'Dumbbell', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'cable_crunch', 'name': 'Crunch na Polia', 'locale_key': 'cable_crunch', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Polia alta, puxar em direção ao chão', 'equipment': 'Cable', 'default_rest_time': 45, 'weight_increment': 2.5},
    {'id': 'ab_roller', 'name': 'Roda de Abdômen', 'locale_key': 'ab_roller', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Joelhos ou em pé', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'hanging_raise', 'name': 'Elevação de Pernas na Barra', 'locale_key': 'hanging_raise', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Pendurado na barra, pernas subindo', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},

    {'id': 'side_plank', 'name': 'Prancha Lateral', 'locale_key': 'side_plank', 'category_id': 'core', 'type': 'timeOnly', 'notes': 'Corpo reto de lado, antebraço no chão', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'bicycle_crunch', 'name': 'Abdominal Bicicleta', 'locale_key': 'bicycle_crunch', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Deitado, joelho ao cotovelo oposto alternado', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'reverse_crunch', 'name': 'Reverse Crunch', 'locale_key': 'reverse_crunch', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Elevar o quadril do chão contraindo o abdômen', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'dead_bug', 'name': 'Dead Bug', 'locale_key': 'dead_bug', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Braço e perna opostos estendendo simultaneamente', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'pallof_press', 'name': 'Pallof Press', 'locale_key': 'pallof_press', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Polia lateral, empurrar para frente sem girar o tronco', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},

    // === CARDIO ===
    {'id': 'treadmill', 'name': 'Esteira', 'locale_key': 'treadmill', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': 'Caminhada ou corrida', 'equipment': 'Treadmill', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'cycling', 'name': 'Bicicleta', 'locale_key': 'cycling', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': 'Ergométrica ou rua', 'equipment': 'Stationary', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'jump_rope', 'name': 'Pular Corda', 'locale_key': 'jump_rope', 'category_id': 'cardio', 'type': 'timeOnly', 'notes': '', 'equipment': 'Bodyweight', 'default_rest_time': 30, 'weight_increment': 0},
    {'id': 'rowing', 'name': 'Remo', 'locale_key': 'rowing', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': 'Máquina de remo', 'equipment': 'Machine', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'swimming', 'name': 'Natação', 'locale_key': 'swimming', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': '', 'equipment': 'Bodyweight', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'walking', 'name': 'Caminhada', 'locale_key': 'walking', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': '', 'equipment': 'Bodyweight', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'running', 'name': 'Corrida', 'locale_key': 'running', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': 'Corrida ao ar livre ou esteira', 'equipment': 'Bodyweight', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'elliptical', 'name': 'Elíptico', 'locale_key': 'elliptical', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': '', 'equipment': 'Machine', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'stair_climber', 'name': 'Escada', 'locale_key': 'stair_climber', 'category_id': 'cardio', 'type': 'timeOnly', 'notes': 'Simulador de escada', 'equipment': 'Machine', 'default_rest_time': 0, 'weight_increment': 0},
    {'id': 'burpee', 'name': 'Burpee', 'locale_key': 'burpee', 'category_id': 'cardio', 'type': 'weightReps', 'notes': 'Agachar, pular para trás, flexão, voltar e saltar', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'battle_ropes', 'name': 'Corda de Batalha', 'locale_key': 'battle_ropes', 'category_id': 'cardio', 'type': 'timeOnly', 'notes': 'Ondular as cordas alternadamente ou simultaneamente', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},

    // === FULLBODY ===
    {'id': 'kettlebell_swing', 'name': 'Kettlebell Swing', 'locale_key': 'kettlebell_swing', 'category_id': 'fullbody', 'type': 'weightReps', 'notes': 'Balanço com kettlebell, cadeia posterior + cardio', 'equipment': 'Kettlebell', 'default_rest_time': 90, 'weight_increment': 2.0},
    {'id': 'thruster', 'name': 'Thruster', 'locale_key': 'thruster', 'category_id': 'fullbody', 'type': 'weightReps', 'notes': 'Agachamento frontal + desenvolvimento acima da cabeça', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'clean_press', 'name': 'Clean and Press', 'locale_key': 'clean_press', 'category_id': 'fullbody', 'type': 'weightReps', 'notes': 'Arranque do chão até os ombros + desenvolvimento', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'turkish_getup', 'name': 'Turkish Get-Up', 'locale_key': 'turkish_getup', 'category_id': 'fullbody', 'type': 'weightReps', 'notes': 'Levantar do chão com peso acima da cabeça, cada lado', 'equipment': 'Kettlebell', 'default_rest_time': 90, 'weight_increment': 2.0},
    {'id': 'snatch', 'name': 'Snatch (Arranco)', 'locale_key': 'snatch', 'category_id': 'fullbody', 'type': 'weightReps', 'notes': 'Levantamento olímpico do chão até acima da cabeça em um movimento', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 2.5},
    {'id': 'bear_crawl', 'name': 'Bear Crawl', 'locale_key': 'bear_crawl', 'category_id': 'fullbody', 'type': 'distanceTime', 'notes': 'Engatinhar em quatro apoios, joelhos fora do chão', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'devils_press', 'name': "Devil's Press", 'locale_key': 'devils_press', 'category_id': 'fullbody', 'type': 'weightReps', 'notes': 'Burpee + desenvolvimento com halteres', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 1.0},
    {'id': 'man_maker', 'name': 'Man Maker', 'locale_key': 'man_maker', 'category_id': 'fullbody', 'type': 'weightReps', 'notes': 'Burpee + remada + desenvolvimento com halteres', 'equipment': 'Dumbbell', 'default_rest_time': 90, 'weight_increment': 1.0},
    {'id': 'wall_ball', 'name': 'Wall Ball', 'locale_key': 'wall_ball', 'category_id': 'fullbody', 'type': 'weightReps', 'notes': 'Agachar e arremessar bola medicinal na parede', 'equipment': 'Medicine Ball', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'burpee_full', 'name': 'Burpee Completo', 'locale_key': 'burpee_full', 'category_id': 'fullbody', 'type': 'weightReps', 'notes': 'Agachar, flexão, pular e bater palma acima da cabeça', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},

    // === FOREARMS ===
    {'id': 'wrist_curl', 'name': 'Rosca de Punho', 'locale_key': 'wrist_curl', 'category_id': 'forearms', 'type': 'weightReps', 'notes': 'Antebraços apoiados no banco ou coxas, flexionar punhos', 'equipment': 'Barbell', 'default_rest_time': 45, 'weight_increment': 1.0},
    {'id': 'reverse_wrist_curl', 'name': 'Rosca de Punho Invertida', 'locale_key': 'reverse_wrist_curl', 'category_id': 'forearms', 'type': 'weightReps', 'notes': 'Antebraços apoiados, palmas para baixo, estender punhos', 'equipment': 'Barbell', 'default_rest_time': 45, 'weight_increment': 1.0},
    {'id': 'farmer_walk', 'name': "Farmer's Walk", 'locale_key': 'farmer_walk', 'category_id': 'forearms', 'type': 'distanceTime', 'notes': 'Caminhar segurando pesos pesados em cada mão', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 2.0},
    {'id': 'pinch_grip', 'name': 'Pinch Grip Hold', 'locale_key': 'pinch_grip', 'category_id': 'forearms', 'type': 'timeOnly', 'notes': 'Segurar anilhas juntas apenas com a pinça dos dedos', 'equipment': 'Plates', 'default_rest_time': 60, 'weight_increment': 1.0},

    // === ADDITIONAL CHEST ===
    {'id': 'cable_crossover', 'name': 'Crossover na Polia', 'locale_key': 'cable_crossover', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Polias altas, puxar para frente e baixo, contrair no centro', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'parallel_dip', 'name': 'Dips nas Paralelas', 'locale_key': 'parallel_dip', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Tronco inclinado para frente foca peito; reto foca tríceps', 'equipment': 'Bodyweight', 'default_rest_time': 90, 'weight_increment': 0},
    {'id': 'decline_pushup', 'name': 'Flexão Declinada', 'locale_key': 'decline_pushup', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Pés elevados, mãos no chão, foco no peitoral superior', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'floor_press', 'name': 'Supino no Solo', 'locale_key': 'floor_press', 'category_id': 'chest', 'type': 'weightReps', 'notes': 'Deitado no chão, amplitude reduzida, protege ombros', 'equipment': 'Barbell', 'default_rest_time': 90, 'weight_increment': 2.5},

    // === ADDITIONAL BACK ===
    {'id': 'seal_row', 'name': 'Remada Cavalinho', 'locale_key': 'seal_row', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Deitado de bruços em banco elevado, remada com barra', 'equipment': 'Barbell', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'vbar_pulldown', 'name': 'Puxada Alta Triângulo', 'locale_key': 'vbar_pulldown', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Pegada neutra com triângulo, puxar até o peito', 'equipment': 'Cable', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'renegade_row', 'name': 'Remada Renegada', 'locale_key': 'renegade_row', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Em posição de prancha, remar um halter de cada vez', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 2.0},
    {'id': 'superman', 'name': 'Superman', 'locale_key': 'superman', 'category_id': 'back', 'type': 'weightReps', 'notes': 'Deitado de bruços, elevar braços e pernas simultaneamente', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},

    // === ADDITIONAL SHOULDERS ===
    {'id': 'db_rear_delt_fly', 'name': 'Crucifixo Invertido Halteres', 'locale_key': 'db_rear_delt_fly', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Tronco inclinado, halteres abrindo lateralmente para deltoide posterior', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'cable_rear_delt_fly', 'name': 'Crucifixo Invertido na Polia', 'locale_key': 'cable_rear_delt_fly', 'category_id': 'shoulders', 'type': 'weightReps', 'notes': 'Polias altas cruzadas, puxar para trás e lateral', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 1.0},

    // === ADDITIONAL BICEPS ===
    {'id': 'cable_rope_curl', 'name': 'Rosca Corda na Polia', 'locale_key': 'cable_rope_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Polia baixa com corda, pegada neutra', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'bayesian_curl', 'name': 'Rosca Bayesian', 'locale_key': 'bayesian_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Polia alta, de costas, braços estendidos para trás', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'drag_curl', 'name': 'Rosca Arrastada', 'locale_key': 'drag_curl', 'category_id': 'biceps', 'type': 'weightReps', 'notes': 'Barra rente ao corpo, cotovelos indo para trás', 'equipment': 'Barbell', 'default_rest_time': 60, 'weight_increment': 1.0},

    // === ADDITIONAL TRICEPS ===
    {'id': 'triceps_parallel_dip', 'name': 'Tríceps na Paralela', 'locale_key': 'triceps_parallel_dip', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Tronco reto, cotovelos para trás, foco total no tríceps', 'equipment': 'Bodyweight', 'default_rest_time': 90, 'weight_increment': 0},
    {'id': 'cable_kickback', 'name': 'Tríceps Coice na Polia', 'locale_key': 'cable_kickback', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Polia baixa, cotovelo fixo, estender o braço para trás', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 1.0},
    {'id': 'tate_press', 'name': 'Tate Press', 'locale_key': 'tate_press', 'category_id': 'triceps', 'type': 'weightReps', 'notes': 'Deitado, halteres juntos acima do peito, cotovelos abrindo para os lados', 'equipment': 'Dumbbell', 'default_rest_time': 60, 'weight_increment': 1.0},

    // === ADDITIONAL LEGS ===
    {'id': 'sumo_squat', 'name': 'Agachamento Sumô', 'locale_key': 'sumo_squat', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Pés bem afastados, pontas para fora, ênfase em adutores e glúteos', 'equipment': 'Barbell', 'default_rest_time': 120, 'weight_increment': 5.0},
    {'id': 'seated_leg_curl', 'name': 'Cadeira Flexora', 'locale_key': 'seated_leg_curl', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Sentado, flexionar as pernas contra a resistência', 'equipment': 'Machine', 'default_rest_time': 90, 'weight_increment': 2.5},
    {'id': 'pistol_squat', 'name': 'Pistol Squat', 'locale_key': 'pistol_squat', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Agachamento unilateral, uma perna estendida à frente', 'equipment': 'Bodyweight', 'default_rest_time': 90, 'weight_increment': 0},
    {'id': 'wall_sit', 'name': 'Wall Sit', 'locale_key': 'wall_sit', 'category_id': 'legs', 'type': 'timeOnly', 'notes': 'Costas na parede, joelhos 90°, manter posição isométrica', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},
    {'id': 'box_jump', 'name': 'Box Jump', 'locale_key': 'box_jump', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Salto pliométrico sobre caixa, aterrissar suavemente', 'equipment': 'Bodyweight', 'default_rest_time': 90, 'weight_increment': 0},
    {'id': 'glute_kickback', 'name': 'Coice de Glúteo na Polia', 'locale_key': 'glute_kickback', 'category_id': 'legs', 'type': 'weightReps', 'notes': 'Polia baixa, estender a perna para trás, foco no glúteo', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},

    // === ADDITIONAL CORE ===
    {'id': 'mountain_climbers', 'name': 'Mountain Climbers', 'locale_key': 'mountain_climbers', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Em posição de prancha, alternar joelhos em direção ao peito', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'flutter_kicks', 'name': 'Flutter Kicks', 'locale_key': 'flutter_kicks', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Deitado, pernas esticadas, alternar batidas curtas para cima e baixo', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
    {'id': 'woodchopper', 'name': 'Woodchopper', 'locale_key': 'woodchopper', 'category_id': 'core', 'type': 'weightReps', 'notes': 'Polia alta, girar tronco diagonalmente como se cortasse lenha', 'equipment': 'Cable', 'default_rest_time': 60, 'weight_increment': 2.5},
    {'id': 'l_sit', 'name': 'L-Sit', 'locale_key': 'l_sit', 'category_id': 'core', 'type': 'timeOnly', 'notes': 'Apoiado nas mãos, pernas esticadas à frente formando um L', 'equipment': 'Bodyweight', 'default_rest_time': 60, 'weight_increment': 0},

    // === ADDITIONAL CARDIO ===
    {'id': 'hiit', 'name': 'HIIT', 'locale_key': 'hiit', 'category_id': 'cardio', 'type': 'timeOnly', 'notes': 'Treino intervalado de alta intensidade (genérico)', 'equipment': 'Bodyweight', 'default_rest_time': 30, 'weight_increment': 0},
    {'id': 'jumping_jacks', 'name': 'Polichinelos', 'locale_key': 'jumping_jacks', 'category_id': 'cardio', 'type': 'weightReps', 'notes': 'Abrir e fechar pernas e braços simultaneamente saltando', 'equipment': 'Bodyweight', 'default_rest_time': 30, 'weight_increment': 0},
    {'id': 'sprint', 'name': 'Sprint / Tiro', 'locale_key': 'sprint', 'category_id': 'cardio', 'type': 'distanceTime', 'notes': 'Corrida curta em máxima velocidade', 'equipment': 'Bodyweight', 'default_rest_time': 120, 'weight_increment': 0},
    {'id': 'skater_jumps', 'name': 'Skater Jumps', 'locale_key': 'skater_jumps', 'category_id': 'cardio', 'type': 'weightReps', 'notes': 'Salto lateral de uma perna para a outra, tocando o pé atrás', 'equipment': 'Bodyweight', 'default_rest_time': 45, 'weight_increment': 0},
  ];
}

