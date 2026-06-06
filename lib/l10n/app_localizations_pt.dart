// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Workout Notes';

  @override
  String get tabWorkout => 'Treino';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonDelete => 'Excluir';

  @override
  String get commonSave => 'Salvar';

  @override
  String get commonDiscard => 'Descartar';

  @override
  String get commonKeepEditing => 'Continuar editando';

  @override
  String commonError(Object error) {
    return 'Erro: $error';
  }

  @override
  String get commonSearch => 'Buscar';

  @override
  String get commonAll => 'Todos';

  @override
  String get commonExercises => 'Exercícios';

  @override
  String get commonVolume => 'Volume';

  @override
  String get commonSets => 'Séries';

  @override
  String get commonReps => 'Repetições';

  @override
  String get commonCompleted => 'Concluído';

  @override
  String get commonInProgress => 'Em andamento';

  @override
  String get commonConfirmDelete => 'Tem certeza?';

  @override
  String get commonActionCannotBeUndone => 'Esta ação não pode ser desfeita.';

  @override
  String get accentColorRed => 'Vermelho';

  @override
  String get accentColorDarkOrange => 'Laranja Escuro';

  @override
  String get accentColorOrange => 'Laranja';

  @override
  String get accentColorAmber => 'Âmbar';

  @override
  String get accentColorDeepPurple => 'Roxo';

  @override
  String get accentColorDarkBlue => 'Azul Escuro';

  @override
  String get accentColorGraphite => 'Graphite';

  @override
  String get accentColorForestGreen => 'Verde Musgo';

  @override
  String get workoutHomeTitle => 'Treino';

  @override
  String get workoutHomeHistoryTooltip => 'Histórico';

  @override
  String get workoutHomeSettingsTooltip => 'Configurações';

  @override
  String get workoutHomeMonthWorkouts => 'Treinos no Mês';

  @override
  String get workoutHomeVolume => 'Volume';

  @override
  String get workoutHomeStreak => 'Sequência';

  @override
  String get workoutHomeDay => 'dia';

  @override
  String get workoutHomeDays => 'dias';

  @override
  String get workoutHomeNewWorkout => 'Novo Treino';

  @override
  String get workoutHomeStartNow => 'Começar agora';

  @override
  String get workoutHomeQuickAdd => 'Quick Add';

  @override
  String get workoutHomeQuickAddSubtitle => 'Adicionar rápido';

  @override
  String get workoutHomeNavigation => 'NAVEGAÇÃO';

  @override
  String get workoutHomeExercises => 'Exercícios';

  @override
  String get workoutHomeRoutines => 'Rotinas';

  @override
  String get workoutHomeProgress => 'Progresso';

  @override
  String get workoutHomeBodyMeasurements => 'Medidas';

  @override
  String get workoutHomeInProgress => 'EM ANDAMENTO';

  @override
  String get workoutHomeNoActiveWorkout => 'Nenhum treino em andamento';

  @override
  String get workoutHomeUpcoming => 'PRÓXIMOS TREINOS';

  @override
  String get workoutHomeCompleted => 'TREINOS CONCLUÍDOS';

  @override
  String get workoutHomeOngoing => 'Em andamento';

  @override
  String get workoutHomeContinueWorkout => 'Continuar Treino';

  @override
  String get workoutHomeDeleteWorkout => 'Excluir Treino';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get settingsAppearance => 'Aparência';

  @override
  String get settingsThemeColor => 'Cor do Tema';

  @override
  String get settingsThemeMode => 'Modo do Tema';

  @override
  String get settingsSystem => 'Sistema';

  @override
  String get settingsSystemSubtitle => 'Usar modo do dispositivo';

  @override
  String get settingsLight => 'Claro';

  @override
  String get settingsLightSubtitle => 'Forçar modo claro';

  @override
  String get settingsDark => 'Escuro';

  @override
  String get settingsDarkSubtitle => 'Forçar modo escuro';

  @override
  String get settingsUnits => 'Unidades';

  @override
  String get settingsUnitSystem => 'Sistema de Unidades';

  @override
  String get settingsUnitKgCm => 'kg / cm';

  @override
  String get settingsUnitLbsIn => 'lbs / in';

  @override
  String get settingsTimer => 'Temporizador';

  @override
  String get settingsDefaultRest => 'Descanso Padrão';

  @override
  String get settingsSeconds => 'segundos';

  @override
  String get settingsAutoStartRest => 'Auto-iniciar Timer';

  @override
  String get settingsAutoStartRestSubtitle =>
      'Iniciar automaticamente após cada série';

  @override
  String get settingsAutoStartWorkoutTimer => 'Timer de Treino Automático';

  @override
  String get settingsAutoStartWorkoutTimerSubtitle =>
      'Iniciar timer ao completar a 1ª série, parar ao finalizar a última';

  @override
  String get settingsNotifications => 'Notificações';

  @override
  String get settingsRestTimerNotif => 'Timer de Descanso';

  @override
  String get settingsRestTimerNotifSubtitle =>
      'Notificação do temporizador entre séries';

  @override
  String get settingsWorkoutTimerNotif => 'Timer de Treino';

  @override
  String get settingsWorkoutTimerNotifSubtitle =>
      'Notificação do cronômetro do treino ativo';

  @override
  String get settingsAlertOptions => 'Opções de alerta';

  @override
  String get settingsSound => 'Som';

  @override
  String get settingsRestSoundSubtitle =>
      'Tocar som ao iniciar e finalizar o descanso';

  @override
  String get settingsWorkoutSoundSubtitle => 'Tocar som ao iniciar o treino';

  @override
  String get settingsVibration => 'Vibração';

  @override
  String get settingsRestVibrationSubtitle =>
      'Vibrar ao iniciar e finalizar o descanso';

  @override
  String get settingsWorkoutVibrationSubtitle => 'Vibrar ao iniciar o treino';

  @override
  String get settingsDisplay => 'Tela';

  @override
  String get settingsKeepScreenOn => 'Manter Tela Ligada';

  @override
  String get settingsKeepScreenOnSubtitle => 'Durante o treino';

  @override
  String get settingsData => 'Dados';

  @override
  String get settingsExportBackup => 'Exportar Backup';

  @override
  String get settingsExportBackupSubtitle =>
      'JSON completo para salvar ou transferir';

  @override
  String get settingsGenerateTestData => 'Gerar Dados de Teste';

  @override
  String get settingsGenerateTestDataSubtitle =>
      'Adiciona treinos fictícios para testar o app';

  @override
  String get settingsGenerateTitle => 'Gerar Dados de Teste?';

  @override
  String get settingsGenerateContent =>
      'Isso vai adicionar treinos fictícios nos últimos meses para testar gráficos e funcionalidades.\n\nUse \"Excluir Todo Histórico\" para remover depois.';

  @override
  String get settingsGenerate => 'Gerar';

  @override
  String settingsGenerateSuccess(Object count) {
    return '✅ $count treinos gerados!';
  }

  @override
  String get settingsAbout => 'Sobre';

  @override
  String get settingsAboutSubtitle => 'Workout Notes v1.0';

  @override
  String get settingsDeleteAllHistory => 'Excluir Todo Histórico de Treinos';

  @override
  String get settingsDeleteHistoryTitle => 'Excluir Todo Histórico?';

  @override
  String get settingsDeleteHistoryContent =>
      'Todos os treinos, séries e exercícios registrados serão apagados. Esta ação não pode ser desfeita.';

  @override
  String get settingsDeleteEverything => 'Excluir Tudo';

  @override
  String get settingsDeleteHistorySuccess => 'Histórico excluído';

  @override
  String get settingsExportSuccess => '✅ Backup exportado!';

  @override
  String settingsExportError(Object error) {
    return 'Erro: $error';
  }

  @override
  String get settingsLanguage => 'Idioma / Language';

  @override
  String get settingsEnglish => 'English';

  @override
  String get settingsPortuguese => 'Português (Brasil)';

  @override
  String get settingsLanguageSubtitle => 'Idioma da interface do app';

  @override
  String get calendarTitle => 'Histórico';

  @override
  String get calendarSun => 'Dom';

  @override
  String get calendarMon => 'Seg';

  @override
  String get calendarTue => 'Ter';

  @override
  String get calendarWed => 'Qua';

  @override
  String get calendarThu => 'Qui';

  @override
  String get calendarFri => 'Sex';

  @override
  String get calendarSat => 'Sáb';

  @override
  String calendarNoWorkouts(Object date) {
    return 'Nenhum treino em $date';
  }

  @override
  String get calendarCreateWorkout => 'Criar Treino';

  @override
  String get calendarNoTime => 'Sem horário';

  @override
  String get calendarInProgress => 'Em andamento';

  @override
  String get calendarWorkoutCreated => '✅ Treino criado para este dia!';

  @override
  String get calendarSelectNewDate => 'Selecione a nova data';

  @override
  String get exportTitle => 'Exportar Dados';

  @override
  String get exportJsonBackup => 'Backup Completo (JSON)';

  @override
  String get exportJsonBackupSubtitle =>
      'Exporta todos os dados: treinos, exercícios, rotinas, medidas e configurações';

  @override
  String get exportCsv => 'Exportar CSV';

  @override
  String get exportCsvSubtitle =>
      'Exporta histórico de treinos (data, exercício, peso, reps) - filtrável por exercício e data';

  @override
  String get exportShareSummary => 'Compartilhar Resumo';

  @override
  String get exportShareSummarySubtitle =>
      'Gera um resumo de texto de um treino específico para compartilhar';

  @override
  String get exportTips => 'Dicas';

  @override
  String get exportTipsContent =>
      '• O backup JSON contém todos os dados do app\n• CSV é ideal para análise em Excel/Google Sheets\n• Os arquivos são salvos temporariamente e compartilhados via share sheet nativo';

  @override
  String get exportCsvDialogTitle => 'Exportar CSV';

  @override
  String get exportCsvExerciseLabel =>
      'Exercício (opcional - vazio exporta todos)';

  @override
  String get exportCsvExerciseHint => 'Deixe vazio para todos';

  @override
  String get exportCsvStartDate => 'Data início';

  @override
  String get exportCsvEndDate => 'Data fim';

  @override
  String get exportCsvButton => 'Exportar CSV';

  @override
  String get exportShareWorkoutTitle => 'Compartilhar Treino';

  @override
  String get exportNoWorkouts => 'Nenhum treino para compartilhar';

  @override
  String get exportSuccess => 'Backup exportado com sucesso!';

  @override
  String get exportCsvSuccess => 'CSV exportado com sucesso!';

  @override
  String exportError(Object error) {
    return 'Erro: $error';
  }

  @override
  String get progressTitle => 'Progresso';

  @override
  String progressMonthlyReport(Object month) {
    return 'RESUMO DE $month';
  }

  @override
  String get progressWorkouts => 'Treinos';

  @override
  String get progressSets => 'Séries';

  @override
  String get progressDays => 'Dias';

  @override
  String progressAverageFeeling(Object rating) {
    return 'Sentimento médio: $rating ★';
  }

  @override
  String progressVsLastMonth(Object delta) {
    return '$delta vs mês ant.';
  }

  @override
  String get progressStreak => 'Sequência';

  @override
  String get progressFrequency => 'Frequência & Consistência';

  @override
  String get progressVolumeGroups => 'Volume & Grupos Musculares';

  @override
  String get progressExerciseHistory => 'Histórico dos Exercícios';

  @override
  String get progressDurationEfficiency => 'Duração & Eficiência';

  @override
  String get progressRecovery => 'Recuperação & Bem-estar';

  @override
  String get progressBodyMeasurements => 'Medidas Corporais';

  @override
  String get progressBodyMeasurementsSubtitle =>
      'Veja tendências detalhadas, fotos e gráficos de composição corporal';

  @override
  String get progressBodyComposition => 'Evolução da Composição Corporal';

  @override
  String get progressYearHeatmap => 'Mapa de calor anual';

  @override
  String get progressWeeklyFrequency =>
      'Frequência semanal (últimas 12 semanas)';

  @override
  String get progressDayOfWeek => 'Dia da semana';

  @override
  String get progressTimeOfDay => 'Horário';

  @override
  String get progressMorning => 'Manhã';

  @override
  String get progressAfternoon => 'Tarde';

  @override
  String get progressEvening => 'Noite';

  @override
  String get progressDawn => 'Madrugada';

  @override
  String get progressNoData => 'Sem dados';

  @override
  String get progressVolumeByGroup => 'Volume por Grupo';

  @override
  String get progressEnergySystem => 'Sistema Energético';

  @override
  String get progressAerobic => 'Aeróbico';

  @override
  String get progressAnaerobic => 'Anaeróbico';

  @override
  String get progressTopExercises => 'Top Exercícios por Volume';

  @override
  String get progressNoExercises => 'Nenhum exercício cadastrado';

  @override
  String get progressTapForHistory =>
      'Toque em um exercício para ver o histórico completo';

  @override
  String get progressDuration => 'Duração dos Treinos';

  @override
  String progressAverage(Object avg) {
    return 'Média: ${avg}min';
  }

  @override
  String get progressDensity => 'Densidade (Volume por Minuto)';

  @override
  String progressDensityAverage(Object avg) {
    return 'Média: $avg kg/min';
  }

  @override
  String get progressWeekAbbreviation => 'S';

  @override
  String get progressBodyWeight => 'Peso Corporal';

  @override
  String get progressNoChartData => 'Nenhum dado disponível para este gráfico';

  @override
  String get progressHistoryTitle => 'Histórico de Treinos';

  @override
  String get progressHistoryDate => 'Data';

  @override
  String get progressHistorySetsReps => 'Séries × Reps';

  @override
  String get progressLoadError => 'Erro ao carregar dados';

  @override
  String progressHeatmapNoData(Object year) {
    return 'Nenhum dado para $year';
  }

  @override
  String get progressChartTitleProgress => 'Progresso';

  @override
  String get progressChartTitleVolumePerWorkout => 'Volume por Treino';

  @override
  String get progressChartTitleRepsPerWorkout => 'Repetições por Treino';

  @override
  String get progressRecoveryFeeling => 'Sentimento ao Longo do Tempo';

  @override
  String get progressRecoveryFeelingVsVolume => 'Sentimento vs Volume Médio';

  @override
  String get progressBodyWeightVsVolume => 'Peso Corporal vs Volume de Treino';

  @override
  String get progressVolumeByMonth => 'Volume por Mês';

  @override
  String get bodyTrackerTitle => 'Medidas Corporais';

  @override
  String get bodyTrackerWeight => 'Peso Corporal';

  @override
  String get bodyTrackerBodyFat => '% Gordura';

  @override
  String get bodyTrackerWaist => 'Cintura';

  @override
  String get bodyTrackerChest => 'Peito';

  @override
  String get bodyTrackerArm => 'Braço';

  @override
  String get bodyTrackerThigh => 'Coxa';

  @override
  String get bodyTrackerHip => 'Quadril';

  @override
  String get bodyTrackerAdd => 'Adicionar Medida';

  @override
  String bodyTrackerAddTitle(Object type) {
    return 'Adicionar $type';
  }

  @override
  String get bodyTrackerValue => 'Valor';

  @override
  String get bodyTrackerDate => 'Data';

  @override
  String get bodyTrackerComment => 'Comentário';

  @override
  String get bodyTrackerSave => 'Salvar';

  @override
  String get bodyTrackerSaved => '✅ Medida salva!';

  @override
  String get bodyTrackerDeleted => 'Medida excluída';

  @override
  String get bodyTrackerDeleteConfirm => 'Excluir esta medida?';

  @override
  String get bodyTrackerQuickMeasure => 'Medir Agora';

  @override
  String get bodyTrackerQuickMeasureSubtitle =>
      'Preencha as medidas que deseja registrar. Deixe em branco para pular.';

  @override
  String get bodyTrackerSaveAll => 'Salvar Medidas';

  @override
  String bodyTrackerAddSingle(Object type) {
    return 'Adicionar $type';
  }

  @override
  String get bodyTrackerEmptyTitle => 'Nenhuma medida ainda';

  @override
  String get bodyTrackerEmptySubtitle =>
      'Comece a registrar suas medidas corporais para acompanhar sua evolução ao longo do tempo.';

  @override
  String get bodyTrackerBodyMap => 'MAPA CORPORAL';

  @override
  String get bodyTrackerLastValue => 'Último';

  @override
  String get bodyTrackerCurrent => 'Atual';

  @override
  String get bodyTrackerAverage => 'Média';

  @override
  String get bodyTrackerMin => 'Mín';

  @override
  String get bodyTrackerMax => 'Máx';

  @override
  String get bodyTrackerTrendLine => 'Tendência';

  @override
  String get bodyTrackerHistory => 'Histórico';

  @override
  String get bodyTrackerEntries => 'registros';

  @override
  String get bodyTrackerNeedTwoMeasurements =>
      'Adicione pelo menos 2 medidas para ver o gráfico';

  @override
  String get bodyTrackerPhoto => 'Foto (opcional)';

  @override
  String get bodyTrackerCamera => 'Câmera';

  @override
  String get bodyTrackerGallery => 'Galeria';

  @override
  String get bodyTrackerInvalidValue => 'Valor inválido';

  @override
  String get bodyTrackerFasting => 'Jejum';

  @override
  String get bodyTrackerFasted => 'Em jejum';

  @override
  String get bodyTrackerQuickCommentHint => 'Anotação rápida (opcional)';

  @override
  String bodyTrackerSavedBatch(Object count) {
    return '✅ $count medidas salvas!';
  }

  @override
  String get bodyTrackerLeftAbbr => 'E';

  @override
  String get bodyTrackerRightAbbr => 'D';

  @override
  String get bodyTrackerLastLabel => 'Última: ';

  @override
  String get bodyTrackerMorning => 'Manhã';

  @override
  String get bodyTrackerAfternoon => 'Tarde';

  @override
  String get bodyTrackerEvening => 'Noite';

  @override
  String get bodyTrackerNight => 'Madrugada';

  @override
  String get bodyTrackerCalf => 'Panturrilha';

  @override
  String get bodyTrackerForearm => 'Antebraço';

  @override
  String get bodyTrackerNeck => 'Pescoço';

  @override
  String get bodyTrackerLeft => 'Esquerdo';

  @override
  String get bodyTrackerRight => 'Direito';

  @override
  String get bodyTrackerLeanMass => 'Massa Magra';

  @override
  String get bodyTrackerFatMass => 'Massa Gorda';

  @override
  String get bodyTrackerHealthy => 'Saudável';

  @override
  String get bodyTrackerModerate => 'Risco Moderado';

  @override
  String get bodyTrackerHigh => 'Risco Alto';

  @override
  String bodyTrackerAsymmetry(Object diff, Object largerSide, Object unit) {
    return 'Diferença: $diff $unit ($largerSide maior)';
  }

  @override
  String get bodyTrackerTrendComparison => 'Esquerda vs Direita';

  @override
  String bodyTrackerLoadMore(Object count) {
    return 'Carregar mais $count entradas';
  }

  @override
  String bodyTrackerLoadMoreCount(Object count) {
    return 'Carregar mais $count';
  }

  @override
  String get bodyTrackerWHR => 'RCQ';

  @override
  String get bodyTrackerEstimatedComposition => 'Composição Corporal Estimada';

  @override
  String get bodyTrackerTimeOfDay => 'Horário';

  @override
  String get bodyTrackerNotInformed => 'Não informado';

  @override
  String get commonOptional => 'opcional';

  @override
  String get routinesTitle => 'Rotinas';

  @override
  String get routinesNew => 'Nova Rotina';

  @override
  String get routinesName => 'Nome da Rotina';

  @override
  String get routinesNameHint => 'Ex: Push Pull Legs';

  @override
  String get routinesCreate => 'Criar';

  @override
  String get routinesEdit => 'Editar Rotina';

  @override
  String get routinesDelete => 'Excluir Rotina';

  @override
  String routinesDeleteConfirm(Object name) {
    return 'Excluir \"$name\"?';
  }

  @override
  String get routinesDeleteContent =>
      'Todos os dados da rotina serão perdidos.';

  @override
  String get routinesEmptyTitle => 'Nenhuma rotina ainda';

  @override
  String get routinesEmptySubtitle =>
      'Crie uma rotina para treinar mais rápido';

  @override
  String get routinesRename => 'Renomear';

  @override
  String get routinesNewDay => 'Novo Dia';

  @override
  String get routinesDayName => 'Nome do Dia';

  @override
  String get routinesDayNameHint => 'Ex: Push Day, Segunda-Feira';

  @override
  String get routinesAddDay => 'Adicionar Dia';

  @override
  String get routinesDeleteDay => 'Excluir Dia';

  @override
  String get routinesDayEmpty => 'Nenhum dia ainda';

  @override
  String get routinesDayEmptySubtitle => 'Adicione dias para sua rotina';

  @override
  String get routinesNoExercises => 'Nenhum exercício adicionado';

  @override
  String get routinesAddExercise => 'Adicionar Exercício';

  @override
  String get routinesRestTimeTitle => 'Tempo de Descanso';

  @override
  String get restTimerTitle => 'Temporizador';

  @override
  String get restTimerStop => 'Parar';

  @override
  String get restTimerComplete => 'CONCLUÍDO';

  @override
  String get restTimerPaused => 'PAUSADO';

  @override
  String get restTimerResting => 'DESCANSANDO';

  @override
  String get restTimerReady => 'PRONTO';

  @override
  String get restTimerResume => 'Continuar';

  @override
  String get restTimerPause => 'Pausar';

  @override
  String get restTimerStartRest => 'Iniciar descanso';

  @override
  String get exerciseLibraryTitle => 'Exercícios';

  @override
  String get exerciseLibraryFavorites => 'Favoritos';

  @override
  String get exerciseLibrarySearch => 'Buscar exercício...';

  @override
  String get exerciseLibraryAll => 'Todos';

  @override
  String get exerciseLibraryNoResults => 'Nenhum exercício encontrado';

  @override
  String get exerciseLibraryNoResultsHint =>
      'Tente alterar a busca ou adicione um novo';

  @override
  String get exerciseLibraryNew => 'Novo Exercício';

  @override
  String get exerciseLibraryAerobic => 'Aeróbico';

  @override
  String get exerciseLibraryAnaerobic => 'Anaeróbico';

  @override
  String get exerciseFormTitleNew => 'Novo Exercício';

  @override
  String get exerciseFormTitleEdit => 'Editar Exercício';

  @override
  String get exerciseFormName => 'Nome do Exercício';

  @override
  String get exerciseFormNameHint => 'Ex: Supino Inclinado';

  @override
  String get exerciseFormCategory => 'Grupo Muscular';

  @override
  String get exerciseFormType => 'Tipo';

  @override
  String get exerciseFormEquipment => 'Equipamento (opcional)';

  @override
  String get exerciseFormEquipmentHint => 'Barbell, Dumbbell, Machine...';

  @override
  String get exerciseFormWeightIncrement => 'Incremento de Peso (kg)';

  @override
  String get exerciseFormWeightIncrementHint => 'Ex: 2.5';

  @override
  String get exerciseFormDefaultRest => 'Descanso Padrão (segundos)';

  @override
  String get exerciseFormDefaultRestHint => 'Ex: 90';

  @override
  String get exerciseFormNotes => 'Instruções / Dicas (opcional)';

  @override
  String get exerciseFormNotesHint => 'Dicas de execução, forma correta...';

  @override
  String get exerciseFormNameRequired => 'Nome é obrigatório';

  @override
  String get exerciseFormSave => 'Salvar';

  @override
  String exerciseFormError(Object error) {
    return 'Erro: $error';
  }

  @override
  String get exerciseFormTypeWeightReps => 'Peso × Repetições';

  @override
  String get exerciseFormTypeDistanceTime => 'Distância × Tempo';

  @override
  String get exerciseFormTypeWeightDistance => 'Peso × Distância';

  @override
  String get exerciseFormTypeWeightTime => 'Peso × Tempo';

  @override
  String get exerciseFormTypeRepsDistance => 'Repetições × Distância';

  @override
  String get exerciseFormTypeRepsTime => 'Repetições × Tempo';

  @override
  String get exerciseFormTypeWeightOnly => 'Apenas Peso';

  @override
  String get exerciseFormTypeRepsOnly => 'Apenas Repetições';

  @override
  String get exerciseFormTypeDistanceOnly => 'Apenas Distância';

  @override
  String get exerciseFormTypeTimeOnly => 'Apenas Tempo';

  @override
  String get quickAddTitle => 'Quick Add';

  @override
  String get quickAddHint => 'Ex: Supino 80kg 3x10';

  @override
  String get quickAddSave => 'Salvar';

  @override
  String get quickAddAcceptedFormats => 'Formatos aceitos:';

  @override
  String quickAddSetsIdentified(Object count) {
    return '$count série(s) identificada(s)';
  }

  @override
  String get quickAddRecentExercises => 'Exercícios Recentes';

  @override
  String quickAddExerciseNotFound(Object name) {
    return 'Exercício \"$name\" não encontrado';
  }

  @override
  String get quickAddCreate => 'Criar';

  @override
  String quickAddSaved(Object count, Object name) {
    return '✅ $name • $count séries registradas';
  }

  @override
  String quickAddCreatedAndSaved(Object name) {
    return '✅ $name criado e registrado!';
  }

  @override
  String get quickAddFormatError => 'Formato: NomeExercício Peso [SériesxReps]';

  @override
  String get quickAddWeightNotFound =>
      'Peso não encontrado. Use: Nome Peso [SériesxReps]';

  @override
  String get quickAddNoSets => 'Nenhuma série identificada';

  @override
  String get exerciseDetailEdit => 'Editar';

  @override
  String get exerciseDetailHistory => 'Histórico';

  @override
  String get exerciseDetailCharts => 'Gráficos';

  @override
  String get exerciseDetailChart1RM => '1RM';

  @override
  String get exerciseDetailChartMaxWeight => 'Peso Máx.';

  @override
  String get exerciseDetailChartVolume => 'Volume';

  @override
  String get exerciseDetailChartTotalReps => 'Total Reps';

  @override
  String get workoutDetailContinue => 'Continuar Treino';

  @override
  String get workoutDetailDelete => 'Excluir Treino';

  @override
  String get workoutDetailDeleteConfirm => 'Excluir Treino?';

  @override
  String get workoutDetailEditDate => 'Alterar Data';

  @override
  String get workoutDetailShare => 'Compartilhar';

  @override
  String get workoutDetailNoSets => 'Nenhuma série';

  @override
  String get workoutDetailWeight => 'Peso';

  @override
  String get workoutDetailDateChanged => '✅ Data alterada!';

  @override
  String get workoutDetailKg => 'kg';

  @override
  String get workoutDetailViewExercise => 'Ver exercício';

  @override
  String get workoutDetailSelectDate => 'Selecione a nova data';

  @override
  String get workoutDetailCopy => 'Copiar Treino';

  @override
  String get workoutDetailCopyDateChanged => '✅ Treino copiado!';

  @override
  String get workoutDetailGoToWorkout => 'Ir para o treino';

  @override
  String workoutDetailDuration(Object min, Object sec) {
    return '${min}min ${sec}s';
  }

  @override
  String get activeWorkoutTitle => 'Treino';

  @override
  String get activeWorkoutFinishWorkout => 'Finalizar';

  @override
  String get activeWorkoutFinished => '💪 Treino finalizado!';

  @override
  String activeWorkoutFinishedWithPRs(Object count) {
    return '🎉 Treino finalizado! $count recorde(s) pessoal(is)!';
  }

  @override
  String get activeWorkoutAddExercise => 'Adicionar Exercício';

  @override
  String get activeWorkoutEmptyTitle => 'Nenhum exercício ainda';

  @override
  String get activeWorkoutEmptySubtitle =>
      'Adicione exercícios para começar seu treino';

  @override
  String get activeWorkoutImportRoutine => 'Importar de Rotina';

  @override
  String get activeWorkoutEditSet => 'Editar Série';

  @override
  String get activeWorkoutWarmup => 'Aquecimento';

  @override
  String get activeWorkoutRemoveExercise => 'Remover Exercício?';

  @override
  String activeWorkoutRemoveExerciseContent(Object name) {
    return 'Remover \"$name\" do treino?';
  }

  @override
  String activeWorkoutRemoved(Object name) {
    return '$name removido do treino';
  }

  @override
  String get activeWorkoutResetTimer => 'Resetar Timer?';

  @override
  String get activeWorkoutResetTimerContent =>
      'Isso vai limpar o tempo de início e fim do treino.';

  @override
  String get activeWorkoutReset => 'Resetar';

  @override
  String get activeWorkoutWeight => 'Peso (kg)';

  @override
  String get activeWorkoutReps => 'Repetições';

  @override
  String get activeWorkoutDistance => 'Distância (km)';

  @override
  String get activeWorkoutTime => 'Tempo';

  @override
  String get activeWorkoutTimerDuration => 'Duração';

  @override
  String get activeWorkoutTimerStartLabel => 'Iniciado em';

  @override
  String get activeWorkoutTimerTitle => 'Timer';

  @override
  String get activeWorkoutNoRoutineFound =>
      'Nenhuma rotina encontrada. Crie uma primeiro!';

  @override
  String get activeWorkoutNoRoutineDays => 'Esta rotina não tem dias.';

  @override
  String get activeWorkoutRoutineImported =>
      '✅ Exercícios importados da rotina!';

  @override
  String get activeWorkoutSelectRoutine => 'Selecione a Rotina';

  @override
  String get activeWorkoutBack => 'Voltar';

  @override
  String get activeWorkoutStart => 'Iniciar';

  @override
  String get activeWorkoutStartTimerTooltip => 'Iniciar cronômetro do treino';

  @override
  String activeWorkoutSetsSummary(Object completed, Object total) {
    return '$completed/$total séries';
  }

  @override
  String get activeWorkoutOK => 'OK';

  @override
  String get activeWorkoutRemove => 'Remover';

  @override
  String get activeWorkoutCustom => 'Personalizado';

  @override
  String get activeWorkoutCustomTime => 'Tempo Personalizado';

  @override
  String get activeWorkoutSelectDay => 'Selecione o dia para importar';

  @override
  String get activeWorkoutAddSet => 'Adicionar Série';

  @override
  String get activeWorkoutCompleted => 'Treino Concluído!';

  @override
  String get activeWorkoutSummarySubtitle =>
      'Ótimo trabalho! Aqui está o resumo:';

  @override
  String get activeWorkoutPersonalRecords => 'Novos Recordes Pessoais';

  @override
  String get activeWorkoutHowWasWorkout => 'Como foi o treino?';

  @override
  String get activeWorkoutCommentHint => 'Observação do treino (opcional)...';

  @override
  String get activeWorkoutFeeling1 => 'Ruim';

  @override
  String get activeWorkoutFeeling2 => 'Ok';

  @override
  String get activeWorkoutFeeling3 => 'Bom';

  @override
  String get activeWorkoutFeeling4 => 'Ótimo';

  @override
  String get activeWorkoutFeeling5 => 'Excelente!';

  @override
  String get workoutDetailSetNumber => '#';

  @override
  String get workoutDetailRpe => 'RPE';

  @override
  String get notificationRestChannelName => 'Timer de Descanso';

  @override
  String get notificationRestChannelDesc =>
      'Notificações do temporizador de descanso entre séries';

  @override
  String get notificationWorkoutChannelName => 'Timer de Treino';

  @override
  String get notificationWorkoutChannelDesc =>
      'Notificações do temporizador de treino ativo';

  @override
  String get exportServiceBackupText => 'Workout Notes - Backup de Treinos';

  @override
  String get exportServiceCsvText => 'Workout Notes - Exportação de Treinos';

  @override
  String get exportServiceCsvHeaderDate => 'Data';

  @override
  String get exportServiceCsvHeaderExercise => 'Exercício';

  @override
  String get exportServiceCsvHeaderCategory => 'Categoria';

  @override
  String get exportServiceCsvHeaderWeight => 'Peso';

  @override
  String get exportServiceCsvHeaderReps => 'Repetições';

  @override
  String get exportServiceCsvHeaderDistance => 'Distância';

  @override
  String get exportServiceCsvHeaderTime => 'Tempo (s)';

  @override
  String get exportServiceCsvHeaderWarmup => 'Aquecimento';

  @override
  String get exportServiceCsvHeaderRpe => 'RPE';

  @override
  String get exportServiceCsvHeaderSetNote => 'Nota';

  @override
  String get exportServiceCsvHeaderWorkoutNote => 'Observação do Treino';

  @override
  String get exportServiceCsvYes => 'Sim';

  @override
  String get exportServiceCsvNo => 'Não';

  @override
  String exportServiceWorkoutSummary(Object date) {
    return '🏋️ Treino - $date\n';
  }

  @override
  String exportServiceWorkoutNote(Object note) {
    return '📝 $note\n';
  }

  @override
  String get noticePermissionTitle => 'Permissão do Timer';

  @override
  String get noticePermissionBody =>
      'Este app precisa de permissão de notificação para alertar quando o descanso entre séries terminar.';
}
