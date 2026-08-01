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
  String get tabSleep => 'Sono';

  @override
  String get sleepTitle => 'Sono';

  @override
  String get sleepEmptyTitle => 'Nenhum sono registrado';

  @override
  String get sleepEmptySubtitle =>
      'Monitore suas noites para acompanhar duração, sono real e consistência.';

  @override
  String get sleepDuration => 'Horas de sono';

  @override
  String get sleepActualDuration => 'Sono real';

  @override
  String get sleepBedtime => 'Hora de dormir';

  @override
  String get sleepWakeTime => 'Hora de acordar';

  @override
  String get sleepDeleted => 'Registro de sono excluído';

  @override
  String get sleepDeleteConfirm => 'Excluir este registro de sono?';

  @override
  String get sleepSummary => 'Resumo';

  @override
  String get sleepLatest => 'Último registro';

  @override
  String get sleepAverage7Days => 'Média · 7 dias';

  @override
  String get sleepAverage30Days => 'Média · 30 dias';

  @override
  String get sleepActualAverage => 'Média de sono real';

  @override
  String get sleepMinimum => 'Mínimo · 30 dias';

  @override
  String get sleepMaximum => 'Máximo · 30 dias';

  @override
  String get sleepConsistency => 'Consistência';

  @override
  String get sleepEfficiency => 'Eficiência';

  @override
  String sleepDaysRecorded(Object count, Object total) {
    return '$count de $total dias registrados';
  }

  @override
  String get sleepNoActual => 'Sem sono real';

  @override
  String get sleepDailyChart => 'Últimos 7 dias';

  @override
  String get sleepTrendChart => 'Tendência · 30 dias';

  @override
  String get sleepChartRecorded => 'Horas registradas';

  @override
  String get sleepChartActual => 'Sono real';

  @override
  String get sleepHistory => 'Histórico';

  @override
  String sleepEntries(Object count) {
    return '$count registros';
  }

  @override
  String get sleepNeedTwoEntries =>
      'Adicione pelo menos 2 registros para ver a tendência.';

  @override
  String sleepLoadMore(Object count) {
    return 'Carregar mais $count registros';
  }

  @override
  String sleepLoadMoreCount(Object count) {
    return 'Carregar mais $count';
  }

  @override
  String get sleepDetails => 'Detalhes do sono';

  @override
  String get sleepDelete => 'Excluir registro';

  @override
  String sleepDurationValue(Object hours, Object minutes) {
    return '${hours}h ${minutes}min';
  }

  @override
  String get sleepGoalTitle => 'Meta de sono';

  @override
  String get sleepGoalTarget => 'Meta';

  @override
  String get sleepGoalReached => 'Meta atingida';

  @override
  String get sleepGoalMissed => 'Meta não atingida';

  @override
  String get sleepGoalInfo =>
      'Uma meta pessoal para comparar suas noites. Não é uma recomendação clínica.';

  @override
  String get sleepMetricSleep => 'Sono';

  @override
  String get sleepMetricTimeInBed => 'Tempo na cama';

  @override
  String get sleepGoalDialogTitle => 'Definir meta de sono';

  @override
  String get sleepGoalDialogDescription =>
      'Escolha quanto você quer dormir por noite.';

  @override
  String get sleepGoalSaved => 'Meta de sono salva';

  @override
  String sleepGoalCurrent(String duration) {
    return '$duration por noite';
  }

  @override
  String get sleepGoalBody =>
      'Esta meta compara sua última noite e destaca seu progresso.';

  @override
  String get sleepMonitorOpen => 'Abrir monitoramento';

  @override
  String sleepMonitorElapsed(String duration) {
    return 'Ativo há $duration';
  }

  @override
  String get sleepWeeklySummary => 'Resumo semanal';

  @override
  String get sleepAverageSleep => 'Sono médio';

  @override
  String get sleepRegularity => 'Regularidade';

  @override
  String get sleepRegularityInfo =>
      'Índice de consistência do app baseado na variação dos horários de dormir e acordar. Não é uma medição clínica.';

  @override
  String sleepNightsRecorded(Object count, Object total) {
    return '$count de $total noites registradas';
  }

  @override
  String get sleepScheduleChart => 'Horários da semana';

  @override
  String get sleepScheduleChartSubtitle =>
      'Do horário de dormir ao despertar nos últimos 7 dias';

  @override
  String get sleepScheduleNoTimes =>
      'Adicione os horários de dormir e acordar para ver sua rotina semanal.';

  @override
  String sleepScheduleSemantics(Object count) {
    return 'Gráfico semanal de horários com $count noites';
  }

  @override
  String get sleepDurationChart => 'Duração por noite';

  @override
  String get sleepDurationChartSubtitle =>
      'Duração registrada e sono real ou estimado';

  @override
  String get sleepChartActualOrEstimated => 'Real / estimado';

  @override
  String get sleepDurationChartSemantics =>
      'Gráfico semanal comparando a duração registrada ao sono real ou estimado';

  @override
  String get sleepPreviousWeek => 'Semana anterior';

  @override
  String get sleepNextWeek => 'Próxima semana';

  @override
  String get sleepNoRecordForDay => 'Nenhum registro de sono neste dia';

  @override
  String get sleepMonitorCta => 'Monitorar sono';

  @override
  String get sleepMonitorCtaSubtitle =>
      'Analise silêncio e ruído localmente durante a noite.';

  @override
  String get sleepMonitorOpenActive => 'Monitoramento em andamento';

  @override
  String sleepMonitorRecovered(Object count) {
    return '$count sessão(ões) de monitoramento recuperada(s).';
  }

  @override
  String get sleepMonitorTitle => 'Monitorar sono';

  @override
  String get sleepMonitorAndroidOnly =>
      'O monitoramento está disponível somente no Android.';

  @override
  String get sleepMonitorRunning => 'Monitoramento em andamento';

  @override
  String get sleepMonitorReady => 'Pronto para monitorar';

  @override
  String get sleepMonitorMicrophone => 'Permissão do microfone';

  @override
  String get sleepMonitorStart => 'Iniciar monitoramento';

  @override
  String sleepMonitorStartWithAlarm(String time) {
    return 'Iniciar e despertar às $time';
  }

  @override
  String get sleepMonitorFinish => 'Finalizar e ver resultado';

  @override
  String get sleepMonitorDiscard => 'Descartar sessão';

  @override
  String get sleepMonitorLocalProcessing =>
      'O áudio é processado localmente e não é gravado. Apenas métricas agregadas são mantidas.';

  @override
  String get sleepMonitorEstimateWarning =>
      'Os resultados são estimativas baseadas no ambiente e não constituem medição médica. Silêncio não significa necessariamente que você estava dormindo.';

  @override
  String get sleepMonitorMicrophoneDenied =>
      'A permissão do microfone é necessária para monitorar esta noite.';

  @override
  String get sleepMonitorNotificationsLimited =>
      'As notificações estão desativadas; o serviço pode ficar menos visível durante a tela bloqueada.';

  @override
  String get sleepMonitorAudioUnavailable =>
      'Não foi possível acessar o microfone. Verifique se outro app está usando-o.';

  @override
  String get sleepMonitorAlreadyActive =>
      'Já existe uma sessão de monitoramento ativa.';

  @override
  String get sleepMonitorImportError =>
      'Não foi possível importar a sessão. Ela será mantida para tentar novamente.';

  @override
  String get sleepMonitorGenericError =>
      'Não foi possível iniciar ou finalizar o monitoramento.';

  @override
  String get sleepMonitorWaitingSignal =>
      'Aguardando o primeiro segmento de sinal';

  @override
  String get sleepMonitorNoiseNow => 'Ruído relativo detectado';

  @override
  String get sleepMonitorQuietNow => 'Período silencioso estimado';

  @override
  String get sleepMonitorInvalidSignal => 'Sinal temporariamente indisponível';

  @override
  String get sleepAlarmSectionTitle => 'Seu horário de despertar';

  @override
  String get sleepAlarmTapToChange => 'Toque no relógio para alterar';

  @override
  String get sleepAlarmNext => 'Próximo alarme';

  @override
  String sleepAlarmIn(String duration) {
    return 'em $duration';
  }

  @override
  String get sleepAlarmSystemSound => 'Som de alarme do sistema + vibração';

  @override
  String get sleepAlarmSystemSoundBody =>
      'Usa o volume de alarmes e o modo Não Perturbe do aparelho.';

  @override
  String get sleepAlarmPreparation => 'Prepare o aparelho';

  @override
  String get sleepAlarmPreparationBody =>
      'Deixe-o carregando perto da cama e com o microfone desobstruído.';

  @override
  String sleepAlarmScheduledFor(String time) {
    return 'Despertador definido para $time';
  }

  @override
  String get sleepAlarmRemaining => 'Tempo até despertar';

  @override
  String get sleepAlarmChange => 'Alterar despertador';

  @override
  String get sleepAlarmInvalidWindow =>
      'Escolha um horário entre 1 minuto e 16 horas a partir de agora.';

  @override
  String get sleepAlarmExactPermission =>
      'Permita Alarmes e lembretes para o despertador tocar pontualmente.';

  @override
  String get sleepAlarmEnableExactPermission => 'Permitir alarmes exatos';

  @override
  String get sleepAlarmNotificationRequired =>
      'As notificações são necessárias para exibir e desligar o despertador.';

  @override
  String get sleepAlarmFullScreenLimited =>
      'A tela cheia está desativada. O som e a vibração continuarão em uma notificação destacada.';

  @override
  String get sleepAlarmEnableFullScreen => 'Permitir tela cheia';

  @override
  String get sleepAlarmScheduleFailed =>
      'Não foi possível programar o despertador.';

  @override
  String get sleepMonitorResultTitle => 'Resultado do monitoramento';

  @override
  String get sleepMonitorResultMissing => 'Resultado não encontrado.';

  @override
  String get sleepMonitorSource => 'Monitoramento';

  @override
  String get sleepMonitorTimeline => 'Linha do tempo da noite';

  @override
  String get sleepMonitorTimeMonitored => 'Tempo monitorado';

  @override
  String get sleepMonitorQuietPeriod => 'Período silencioso';

  @override
  String get sleepMonitorNoisyPeriod => 'Período com ruído';

  @override
  String get sleepMonitorNoiseEvents => 'Eventos de ruído';

  @override
  String get sleepMonitorSignalCoverage => 'Cobertura do sinal';

  @override
  String get sleepMonitorQuiet => 'Silêncio relativo';

  @override
  String get sleepMonitorNoise => 'Ruído relativo';

  @override
  String get sleepMonitorInvalid => 'Sinal inválido';

  @override
  String get sleepMonitorDataQuality => 'Qualidade dos dados do MVP';

  @override
  String get sleepMonitorDataAcceptable =>
      'Noite adequada para a próxima fase do MVP';

  @override
  String get sleepMonitorDataAcceptableBody =>
      'A duração e a cobertura da captura são suficientes para avaliar o monitor atual.';

  @override
  String get sleepMonitorDataInsufficient =>
      'A noite precisa de outra rodada de monitoramento';

  @override
  String get sleepMonitorDataInsufficientBody =>
      'Para avançar, registre pelo menos 4 horas, com 90% de cobertura da linha do tempo e 80% de sinal válido.';

  @override
  String get sleepMonitorCapturedSegments => 'Segmentos capturados';

  @override
  String get sleepMonitorTimelineCoverage => 'Cobertura da linha do tempo';

  @override
  String get sleepMonitorNoiseGraph => 'Ruído relativo ao longo da noite';

  @override
  String get sleepMonitorNoiseScore => 'Índice de ruído';

  @override
  String get sleepMonitorNoSegments =>
      'Nenhum segmento de sinal foi registrado';

  @override
  String get sleepMonitorNoSegmentsBody =>
      'Esta sessão não permite avaliar o MVP. Agora o monitor encerra com erro quando o microfone deixa de retornar dados, em vez de concluir uma noite vazia.';

  @override
  String get sleepMonitorAverageNoise => 'Ruído médio';

  @override
  String get sleepMonitorPeakNoise => 'Pico de ruído';

  @override
  String get sleepMonitorStartTime => 'Início';

  @override
  String get sleepMonitorEndTime => 'Fim';

  @override
  String get sleepMonitorThreshold => 'Limite de ruído';

  @override
  String get sleepMonitorExportDiagnostic => 'Exportar diagnóstico';

  @override
  String get sleepMonitorExportDiagnosticTitle => 'O que deve ser incluído?';

  @override
  String get sleepMonitorExportDiagnosticBody =>
      'O arquivo JSON poderá ser compartilhado para análise técnica. O áudio bruto nunca é armazenado e não pode ser exportado.';

  @override
  String get sleepMonitorExportTechnicalOnly =>
      'Somente dados técnicos (recomendado)';

  @override
  String get sleepMonitorExportTechnicalOnlyBody =>
      'Usa tempos relativos e exclui a data do sono, horários exatos, identificadores locais e seu comentário.';

  @override
  String get sleepMonitorExportWithPersonal => 'Incluir dados pessoais do sono';

  @override
  String get sleepMonitorExportWithPersonalBody =>
      'Também inclui data e horários exatos, identificadores locais, durações registradas e seu comentário pessoal sobre o sono.';

  @override
  String get sleepMonitorExportConfirm => 'Gerar e compartilhar';

  @override
  String get sleepMonitorExportSuccess =>
      'Diagnóstico gerado. Escolha onde compartilhar ou salvar.';

  @override
  String get sleepMonitorExportError =>
      'Não foi possível gerar o arquivo de diagnóstico.';

  @override
  String get sleepMonitorTimeInBed => 'Tempo na cama';

  @override
  String get sleepMonitorDeleteSession => 'Apagar sessão';

  @override
  String get sleepMonitorDeleteSessionBody =>
      'As métricas e a linha do tempo desta sessão serão apagadas. O registro de sono permanece.';

  @override
  String get sleepMonitorDiscardTitle => 'Descartar sessão?';

  @override
  String get sleepMonitorDiscardBody =>
      'A sessão em andamento e suas métricas serão apagadas.';

  @override
  String get sleepMonitorDigitalSilence => 'Silêncio digital';

  @override
  String get sleepInferenceTitle => 'Análise da noite';

  @override
  String get sleepInferenceSleptAt => 'Dormiu';

  @override
  String get sleepInferenceOnsetUnknown => 'Início não identificado';

  @override
  String get sleepInferencePreparation => 'Preparação';

  @override
  String get sleepInferenceSettling => 'Acomodação';

  @override
  String get sleepInferenceAwakenings => 'Acordou';

  @override
  String get sleepInferenceEstimatedSleep => 'Sono estimado';

  @override
  String get sleepInferenceConfidence => 'Confiança';

  @override
  String get sleepInferenceConfidenceLow => 'baixa';

  @override
  String get sleepInferenceConfidenceMedium => 'média';

  @override
  String get sleepInferenceInsufficient =>
      'Os dados desta noite não permitem calcular início do sono e despertares com segurança.';

  @override
  String get sleepInferenceEventsTitle => 'Eventos da noite';

  @override
  String get sleepInferencePeak => 'pico';

  @override
  String get sleepInferenceEventTransient => 'Atividade transitória';

  @override
  String get sleepInferenceEventProlonged => 'Atividade prolongada';

  @override
  String get sleepInferenceEventAwakening => 'Despertar';

  @override
  String get sleepInferenceEventFinalActivity =>
      'Atividade antes do encerramento';

  @override
  String get sleepInferenceReasonShort =>
      'Pico curto, sem duração suficiente para indicar despertar.';

  @override
  String get sleepInferenceReasonSustained =>
      'Atividade sonora sustentada sem retorno ao silêncio que caracterize despertar.';

  @override
  String get sleepInferenceReasonAwakening =>
      'Atividade sustentada seguida por retorno ao silêncio.';

  @override
  String get sleepInferenceReasonFinal =>
      'Atividade sustentada nos dez minutos finais.';

  @override
  String get sleepInferenceBlockerTooShort =>
      'Registre pelo menos quatro horas em uma sessão concluída.';

  @override
  String get sleepInferenceBlockerLowTimelineCoverage =>
      'A cobertura da linha do tempo ficou abaixo de 90%.';

  @override
  String get sleepInferenceBlockerLowSignalCoverage =>
      'A cobertura de sinal válido ficou abaixo de 80%.';

  @override
  String get sleepInferenceBlockerInvalidSegments =>
      'Mais de 20% do período contém sinal inválido.';

  @override
  String get sleepInferenceBlockerDigitalSilence =>
      'Mais de 20% do período contém silêncio digital do microfone.';

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
  String get workoutHomeSectionQuickActions => 'AÇÕES RÁPIDAS';

  @override
  String get workoutHomeSectionTools => 'FERRAMENTAS';

  @override
  String get workoutHomeSectionHistory => 'HISTÓRICO';

  @override
  String workoutHomeActiveBannerSubtitle(Object duration) {
    return '$duration decorridos · toque para continuar';
  }

  @override
  String get workoutHomeActiveBannerAction => 'Continuar';

  @override
  String get workoutHomeLastWorkout => 'Último treino';

  @override
  String workoutHomeLastWorkoutAgo(Object when) {
    return 'há $when';
  }

  @override
  String get workoutHomeLastWorkoutToday => 'Hoje';

  @override
  String get workoutHomeLastWorkoutYesterday => 'Ontem';

  @override
  String get workoutHomeEmptyTitle => 'Nenhum treino ainda';

  @override
  String get workoutHomeEmptySubtitle =>
      'Registre seu primeiro treino para começar a acompanhar seu progresso';

  @override
  String get workoutHomeEmptyCta => 'Começar primeiro treino';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get settingsAppearance => 'Aparência';

  @override
  String get settingsSectionAppearance => 'APARÊNCIA';

  @override
  String get settingsSectionWorkout => 'TREINO';

  @override
  String get settingsSectionNotifications => 'NOTIFICAÇÕES';

  @override
  String get settingsSectionData => 'DADOS';

  @override
  String get settingsAboutDescription =>
      'Um app completo para registrar treinos, rotinas, progresso, medidas corporais e exportar em CSV.';

  @override
  String get settingsAboutOk => 'OK';

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
      'Adiciona treinos, medidas e sono fictícios para testar o app';

  @override
  String get settingsGenerateTitle => 'Gerar Dados de Teste?';

  @override
  String get settingsGenerateContent =>
      'Isso vai adicionar treinos, medidas corporais e registros de sono fictícios nos últimos meses para testar gráficos e funcionalidades.\n\nUse \"Excluir Todo Histórico\" para remover depois.';

  @override
  String get settingsGenerate => 'Gerar';

  @override
  String settingsGenerateSuccess(Object count) {
    return '✅ $count treinos gerados!';
  }

  @override
  String settingsGenerateSuccessDetailed(
    Object routines,
    Object sleep,
    Object workouts,
  ) {
    return '✅ $workouts treinos, $routines rotinas e $sleep noites de sono gerados!';
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
  String get settingsExportOptionsTitle => 'Exportar backup';

  @override
  String get settingsExportShareOption => 'Compartilhar arquivo';

  @override
  String get settingsExportShareSubtitle =>
      'Abrir o compartilhamento do sistema';

  @override
  String get settingsExportSaveOption => 'Salvar no dispositivo';

  @override
  String get settingsExportSaveSubtitle =>
      'Escolha Downloads, Drive ou outro local';

  @override
  String get settingsExportSaveDialogTitle => 'Salvar backup JSON';

  @override
  String settingsExportSaveSuccess(Object path) {
    return 'Backup salvo com sucesso!\n$path';
  }

  @override
  String settingsExportSaveError(Object error) {
    return 'Não foi possível salvar o backup: $error';
  }

  @override
  String get settingsImportBackup => 'Importar Backup';

  @override
  String get settingsImportBackupSubtitle =>
      'Restaurar todos os dados de um backup JSON';

  @override
  String get settingsImportWarning =>
      'Isso vai substituir TODOS os seus dados atuais (treinos, exercícios, rotinas, medidas, configurações) pelos dados do backup.\n\nEsta ação não pode ser desfeita.';

  @override
  String get settingsImport => 'Importar';

  @override
  String settingsImportSuccess(Object count) {
    return '✅ $count registros importados! Reinicie o app para aplicar as alterações.';
  }

  @override
  String settingsImportError(Object error) {
    return 'Erro na importação: $error';
  }

  @override
  String get settingsNoBackupFile => 'Nenhum arquivo de backup selecionado';

  @override
  String get settingsImportPasteTitle => 'Colar backup';

  @override
  String get settingsImportPasteHint =>
      'Copie o conteúdo do arquivo .json e cole aqui';

  @override
  String get settingsImportPasteOption => 'Colar conteúdo do backup';

  @override
  String get settingsImportPasteSubtitle =>
      'Copie o JSON de outro dispositivo e cole aqui';

  @override
  String get settingsImportLocalOption => 'Backups salvos neste dispositivo';

  @override
  String get settingsImportPickFileOption =>
      'Selecionar arquivo do dispositivo';

  @override
  String get settingsImportPickFileSubtitle =>
      'Escolha um backup .json dos Downloads, Drive ou armazenamento';

  @override
  String settingsImportPickerError(Object error) {
    return 'Não foi possível abrir o seletor de arquivos: $error';
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
  String get progressCardio => 'Cardio';

  @override
  String get progressCardioSubtitle =>
      'Distância, pace e acompanhamento cardiovascular';

  @override
  String get progressCardioWeekly => 'Distância Semanal';

  @override
  String get progressCardioByModality => 'Distância por Modalidade';

  @override
  String get progressCardioPace => 'Tendência de Pace';

  @override
  String get progressCardioPRs => 'Recordes de Cardio';

  @override
  String progressCardioTotal(Object distance) {
    return 'Total: $distance neste mês';
  }

  @override
  String progressCardioAvgPace(Object pace) {
    return 'Pace médio: $pace';
  }

  @override
  String get progressCardioNoData => 'Nenhum treino cardio ainda';

  @override
  String get progressCardioNoDataCta => 'Iniciar treino cardio';

  @override
  String get progressFilterAll => 'Todos';

  @override
  String get progressFilterStrength => 'Força';

  @override
  String get progressFilterCardio => 'Cardio';

  @override
  String get progressSelectExercise => 'Selecione o exercício';

  @override
  String get cardioLongestDistance => 'Maior Distância';

  @override
  String get cardioLongestDuration => 'Maior Duração';

  @override
  String get cardioBestPace => 'Melhor Pace';

  @override
  String get settingsDistanceUnit => 'Unidade de Distância';

  @override
  String get settingsDistanceUnitKm => 'km';

  @override
  String get settingsDistanceUnitMi => 'mi (milhas)';

  @override
  String get workoutHomeCardioDistance => 'Dist. Cardio';

  @override
  String get workoutHomeCardioTime => 'Tempo Cardio';

  @override
  String get commonDistance => 'Distância';

  @override
  String get commonPace => 'Pace';

  @override
  String get commonTotal => 'Total';

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
  String get bodyTrackerSelectMeasurement => 'Selecionar Medida';

  @override
  String get bodyTrackerCustomize => 'Personalizar';

  @override
  String get bodyTrackerCustomizeTitle => 'Personalizar Medidas';

  @override
  String get bodyTrackerCustomizeSubtitle =>
      'Selecione as medidas que quer acompanhar';

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
  String get routinesEditDay => 'Editar Dia';

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
  String routinesEstimatedDuration(Object duration) {
    return 'Tempo estimado: $duration';
  }

  @override
  String get workoutEstimatedCalories => 'Calorias estimadas';

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
  String get exerciseFormSectionBasic => 'Básico';

  @override
  String get exerciseFormSectionDefaults => 'Padrões';

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
  String get workoutDetailEdit => 'Editar Treino';

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
  String get activeWorkoutCurrent => 'Atual';

  @override
  String get activeWorkoutLast => 'Último';

  @override
  String get activeWorkoutByMuscleGroup => 'Por grupo muscular';

  @override
  String get workoutStatsDensity => 'Densidade';

  @override
  String get workoutStatsKgPerMin => 'kg/min';

  @override
  String get workoutStatsEvolution => 'Evolução';

  @override
  String get workoutStatsHighlights => 'Destaques';

  @override
  String get workoutStatsTopSet => 'Top set';

  @override
  String get workoutStatsHighestVolume => 'Maior volume';

  @override
  String get workoutStatsAverageRpe => 'RPE médio';

  @override
  String get workoutStatsVsSimilarWorkout => 'vs treino parecido';

  @override
  String get workoutStatsMuscleVolume => 'Volume por grupo';

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
  String activeWorkoutSetLabel(Object number) {
    return 'Série $number';
  }

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
  String get notificationRestTimerTitle => 'Descanso';

  @override
  String get notificationRestCompleteTitle => 'Descanso Concluído';

  @override
  String get notificationRestCompleteBody =>
      'O tempo de descanso acabou - hora da próxima série!';

  @override
  String get notificationWorkoutTimerTitle => 'Treino ativo';

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

  @override
  String get routinesDayDashboard => 'Dashboard do Dia';

  @override
  String get routinesNoExercisesHint =>
      'Adicione exercícios para montar seu template';

  @override
  String get routinesDayDashboardSets => 'séries';

  @override
  String get routinesDayDashboardVolume => 'kg volume';

  @override
  String get routinesDayDashboardGroups => 'grupos';

  @override
  String get routinesWeeklyView => 'Visão Semanal';

  @override
  String get routinesPerDay => 'Por Dia';

  @override
  String routinesDaySets(Object count) {
    return '$count séries';
  }

  @override
  String routinesDayGroups(Object count) {
    return '$count grupos';
  }

  @override
  String routinesInsightMuscleGroups(Object count) {
    return '📋 $count grupos musculares na semana';
  }

  @override
  String get routinesInsightBalanced =>
      '⚖️ Semana equilibrada! Todos os grupos com volume similar.';

  @override
  String routinesInsightHighDiff(
    Object highest,
    Object highestSets,
    Object lowest,
    Object lowestSets,
  ) {
    return '💪 $highest (${highestSets}s) está muito acima de $lowest (${lowestSets}s). Considere redistribuir.';
  }

  @override
  String routinesInsightFocus(
    Object highest,
    Object lowest,
    Object lowestSets,
    Object pct,
  ) {
    return '📊 Foco em $highest ($pct% das séries). $lowest com ${lowestSets}s — volume menor.';
  }

  @override
  String routinesInsightAverage(Object avg, Object days) {
    return 'Média de $avg séries/dia em $days dias de treino.';
  }

  @override
  String routinesWeeklyVolume(Object volume) {
    return '${volume}kg volume';
  }

  @override
  String routinesWeeklyDays(Object count) {
    return '$count dias';
  }

  @override
  String get routinesNotes => 'Descrição';

  @override
  String get routinesNotesHint => 'Descrição opcional da rotina';

  @override
  String get reorderHint => 'Pressione e segure um exercício para reordenar';

  @override
  String get reorderMovedToTop => 'Movido para o topo';

  @override
  String get reorderMovedToBottom => 'Movido para o final';

  @override
  String get editWorkoutTitle => 'Editar Treino';

  @override
  String get editWorkoutDateTime => 'Data e Horário';

  @override
  String get editWorkoutStart => 'Início';

  @override
  String get editWorkoutEnd => 'Fim';

  @override
  String get editWorkoutDuration => 'Duração';

  @override
  String get editWorkoutChangeDate => 'Alterar Data';

  @override
  String get editWorkoutChangeStart => 'Alterar horário de início';

  @override
  String get editWorkoutChangeEnd => 'Alterar horário de fim';

  @override
  String get editWorkoutChangeStartDate => 'Alterar data e horário de início';

  @override
  String get editWorkoutChangeEndDate => 'Alterar data e horário de fim';

  @override
  String get editWorkoutSelectDate => 'Selecione a data';

  @override
  String get editWorkoutSelectTime => 'Selecione o horário';

  @override
  String get editWorkoutEndAfterStart =>
      'O horário de fim deve ser depois do início';

  @override
  String get editWorkoutInvalidRange => 'Intervalo de datas inválido';

  @override
  String get editWorkoutSaved => 'Treino atualizado';

  @override
  String get editWorkoutReorderHint =>
      'Pressione e segure um exercício para reordenar';

  @override
  String get editWorkoutAddExercise => 'Adicionar Exercício';

  @override
  String get progressGoals => 'Metas';

  @override
  String get progressGoalsSubtitle =>
      'Acompanhe e supere seus desafios pessoais';

  @override
  String get goalScopeAnaerobic => 'Força';

  @override
  String get goalScopeAerobic => 'Cardio';

  @override
  String get goalMetricVolume => 'Volume';

  @override
  String get goalMetricDays => 'Dias';

  @override
  String get goalMetricDistance => 'Distância';

  @override
  String get goalMetricTime => 'Tempo';

  @override
  String get goalPeriodWeekly => 'Semanal';

  @override
  String get goalPeriodMonthly => 'Mensal';

  @override
  String get goalCreateTitle => 'Nova Meta';

  @override
  String get goalEditTitle => 'Editar Meta';

  @override
  String get goalLabelTitle => 'Título (opcional)';

  @override
  String get goalTitleHint => 'Ex: Mês de hipertrofia';

  @override
  String get goalChooseMetric => 'Escolha a métrica';

  @override
  String get goalChoosePeriod => 'Periodicidade';

  @override
  String get goalTargetValue => 'Valor alvo';

  @override
  String get goalTargetHint => 'Valor numérico';

  @override
  String get goalCurrentProgress => 'Progresso atual';

  @override
  String goalDaysRemaining(num days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dias restantes',
      one: '1 dia restante',
    );
    return '$_temp0';
  }

  @override
  String get goalCompleted => 'Meta atingida! 🎉';

  @override
  String get goalKeepGoing => 'Continue firme!';

  @override
  String get goalHistory => 'Histórico';

  @override
  String get goalEmpty => 'Nenhuma meta criada';

  @override
  String get goalEmptySubtitle => 'Toque em + para criar sua primeira meta';

  @override
  String get goalDelete => 'Excluir meta';

  @override
  String get goalDeleteConfirm => 'Excluir esta meta?';

  @override
  String get goalDeleteMessage => 'Esta ação não pode ser desfeita.';

  @override
  String get goalPaused => 'Pausada';

  @override
  String get goalPausedBadge => 'PAUSADA';

  @override
  String goalAchievementRate(Object rate) {
    return '$rate% de sucesso';
  }

  @override
  String get goalGridAdd => 'Adicionar meta';

  @override
  String goalSuggestedTarget(Object value) {
    return 'Sugerido: $value';
  }

  @override
  String get goalPickScope => 'Sistema Energético';

  @override
  String get goalPickScopeSubtitle => 'Força ou Cardio?';

  @override
  String get goalStep1 => 'Escopo';

  @override
  String get goalStep2 => 'Métrica';

  @override
  String get goalStep3 => 'Detalhe';

  @override
  String get goalNoHistory => 'Sem períodos anteriores';

  @override
  String get goalNoHistoryHint =>
      'O histórico aparecerá após o primeiro ciclo ser concluído';

  @override
  String get goalResume => 'Retomar';

  @override
  String get goalPause => 'Pausar';

  @override
  String get goalSaved => 'Meta salva';

  @override
  String get goalDeleted => 'Meta excluída';

  @override
  String goalValueVolumeKg(Object value) {
    return '$value kg';
  }

  @override
  String goalValueDistance(Object value) {
    return '$value km';
  }

  @override
  String goalValueTime(Object value) {
    return '$value';
  }

  @override
  String goalValueDays(Object value) {
    return '$value dias';
  }

  @override
  String goalValueDaysShort(Object value) {
    return '${value}d';
  }

  @override
  String get goalMotivationNear => 'Falta pouco — você consegue!';

  @override
  String get goalMotivationMid => 'No ritmo certo. Continue!';

  @override
  String get goalMotivationEarly => 'Vamos começar! Cada treino conta.';

  @override
  String get goalMotivationDone => 'Incrível! Você bateu a meta!';

  @override
  String get goalContributingWorkouts => 'Treinos deste período';

  @override
  String get goalNoContributors => 'Nenhum treino no período ainda';

  @override
  String get progressPeriodWeek => 'Semana';

  @override
  String get progressPeriodMonth => 'Mês';

  @override
  String get progressPeriodYear => 'Ano';

  @override
  String get progressVolumeTypeWeight => 'Peso';

  @override
  String get progressVolumeTypeSets => 'Séries';

  @override
  String get progressVolumeTrend => 'Tendência';

  @override
  String get progressVolumeTrendLast12Weeks => 'Últimas 12 semanas';

  @override
  String get progressVolumeTrendLast12Months => 'Últimos 12 meses';

  @override
  String get progressVolumeTrendLast5Years => 'Últimos 5 anos';

  @override
  String get progressVolumeUnitSets => 'séries';

  @override
  String get progressVolumeUnitWeight => 'kg';

  @override
  String get progressVolumeViewPie => 'Pizza';

  @override
  String get progressVolumeViewList => 'Lista';

  @override
  String get progressVolumeTotal => 'Total';

  @override
  String get aiCoachSection => 'AI COACH';

  @override
  String get aiCoachEntry => 'Treinador IA';

  @override
  String get aiCoachEntrySubtitle => 'Converse com um personal trainer de IA.';

  @override
  String get aiCoachConfigureEntry => 'Configurar IA';

  @override
  String get aiCoachConfigureEntrySubtitle =>
      'Provedores, modelo, prompt do sistema.';

  @override
  String get aiChatTitle => 'Treinador IA';

  @override
  String get aiChatInputHint => 'Pergunte algo ao seu treinador…';

  @override
  String get aiChatInputHintDisabled => 'Configure um provedor para começar';

  @override
  String get aiChatNewChat => 'Nova conversa';

  @override
  String get aiChatHistory => 'Histórico';

  @override
  String get aiChatSettings => 'Configurações';

  @override
  String get aiChatChooseProvider => 'Trocar provedor';

  @override
  String get aiChatRetry => 'Tentar de novo';

  @override
  String get aiChatCopy => 'Copiar';

  @override
  String get aiChatCopied => 'Mensagem copiada';

  @override
  String get aiChatErrorGeneric => 'Algo deu errado.';

  @override
  String get aiChatErrorTimeout => 'A IA demorou demais para responder.';

  @override
  String get aiChatErrorNoProvider => 'Nenhum provedor de IA configurado.';

  @override
  String get aiChatErrorInvalidToken => 'Token de API inválido ou ausente.';

  @override
  String get aiChatErrorMissingModel =>
      'Selecione um modelo em Configurações → AI Coach.';

  @override
  String get aiChatErrorNotFound => 'Modelo ou endpoint não encontrado.';

  @override
  String get aiChatErrorInvalidResponse =>
      'A resposta do provedor de IA é inválida.';

  @override
  String get aiChatErrorRequest =>
      'Não foi possível concluir a solicitação à IA.';

  @override
  String get aiChatErrorUserMessage => 'Mensagem do usuário não encontrada.';

  @override
  String get aiChatProcessing => 'Processando…';

  @override
  String get aiChatWelcomeTitle => 'Olá! Sou o seu Treinador IA.';

  @override
  String get aiChatWelcomeSubtitle =>
      'Pergunte sobre seu progresso, peça uma análise do seu treino, ou peça sugestões de progressão.';

  @override
  String get aiChatSending => 'Enviando…';

  @override
  String aiChatReading(Object count) {
    return 'Lendo $count fonte(s)…';
  }

  @override
  String get aiChatFinalising => 'Finalizando…';

  @override
  String aiChatActiveModel(Object model, Object provider) {
    return '$provider • $model';
  }

  @override
  String aiChatNoModel(Object provider) {
    return '$provider • (sem modelo)';
  }

  @override
  String get aiToolApplied => 'Ferramenta aplicada';

  @override
  String get aiToolNoContent => '(sem conteúdo)';

  @override
  String get aiToolError => 'Erro';

  @override
  String get aiToolUnknown => 'desconhecido';

  @override
  String get aiToolListRecentWorkouts => 'Listando treinos recentes';

  @override
  String get aiToolGetWorkoutDetail => 'Detalhando treino';

  @override
  String get aiToolListExercises => 'Buscando exercícios';

  @override
  String get aiToolGetExerciseHistory => 'Histórico do exercício';

  @override
  String get aiToolGetExerciseRecords => 'Recordes pessoais';

  @override
  String get aiToolWeeklyVolume => 'Volume semanal';

  @override
  String get aiToolProgressTrend => 'Tendência de progressão';

  @override
  String get aiToolListRoutines => 'Listando rotinas';

  @override
  String get aiToolGetRoutineDetail => 'Detalhando rotina';

  @override
  String get aiToolBodyMeasurements => 'Medidas corporais';

  @override
  String get aiToolCardioSummary => 'Resumo de cardio';

  @override
  String get aiToolListGoals => 'Metas ativas';

  @override
  String get aiToolGoalHistory => 'Histórico da meta';

  @override
  String get aiToolProposeRoutineChange => 'Preparando proposta de rotina';

  @override
  String get aiChatPreparingProposal => 'Preparando prévia da rotina…';

  @override
  String get aiChatApplyingProposal => 'Aplicando alterações aprovadas…';

  @override
  String get aiRoutineProposalCreate => 'Nova rotina';

  @override
  String get aiRoutineProposalUpdate => 'Alterar rotina';

  @override
  String get aiRoutineProposalAwaiting => 'Aguardando aprovação';

  @override
  String get aiRoutineProposalApplying => 'Aplicando';

  @override
  String get aiRoutineProposalApplied => 'Aplicada';

  @override
  String get aiRoutineProposalRejected => 'Recusada';

  @override
  String get aiRoutineProposalStale => 'Desatualizada';

  @override
  String get aiRoutineProposalFailed => 'Falhou';

  @override
  String get aiRoutineProposalPreview =>
      'Revise as alterações antes de aplicar.';

  @override
  String get aiRoutineProposalApprove => 'Aprovar e aplicar';

  @override
  String get aiRoutineProposalReject => 'Recusar';

  @override
  String get aiRoutineProposalView => 'Ver rotina';

  @override
  String get aiRoutineProposalDetails => 'Ver detalhes';

  @override
  String get aiRoutineProposalHideDetails => 'Ocultar detalhes';

  @override
  String get aiRoutineProposalAdded => 'Adicionados';

  @override
  String get aiRoutineProposalRemoved => 'Removidos';

  @override
  String get aiRoutineProposalChanges => 'Alterações propostas';

  @override
  String aiRoutineProposalRemovalWarning(Object count) {
    return 'Esta proposta remove $count item(ns).';
  }

  @override
  String get aiRoutineProposalConfirmTitle => 'Aplicar remoções?';

  @override
  String aiRoutineProposalConfirmBody(Object count) {
    return '$count item(ns) serão removidos da rotina. Esta ação não pode ser desfeita automaticamente.';
  }

  @override
  String get aiRoutineProposalConfirmApply => 'Aplicar alterações';

  @override
  String get aiRoutineProposalStaleBody =>
      'A rotina mudou desde a prévia. Peça para a IA gerar uma nova proposta.';

  @override
  String get aiRoutineProposalRejectedBody => 'Nenhuma alteração foi aplicada.';

  @override
  String get aiRoutineProposalAppliedBody =>
      'Alterações aplicadas com sucesso.';

  @override
  String get aiRoutineProposalRetrySummary => 'Gerar resumo';

  @override
  String get aiProviderPickerTitle => 'Provedor e modelo';

  @override
  String get aiProviderPickerSearch => 'Buscar modelo';

  @override
  String get aiHistoryTitle => 'Histórico de conversas';

  @override
  String get aiHistoryEmpty => 'Nenhuma conversa ainda';

  @override
  String get aiHistoryEmptySubtitle =>
      'Comece uma nova conversa no chat do Treinador IA.';

  @override
  String get aiHistoryDeleteTitle => 'Apagar conversa?';

  @override
  String aiHistoryDeleteBody(Object title) {
    return 'Esta ação não pode ser desfeita. \"$title\" será removida.';
  }

  @override
  String get aiHistoryPinned => 'Fixadas';

  @override
  String get aiHistoryRecent => 'Recentes';

  @override
  String get aiHistoryActions => 'Ações da conversa';

  @override
  String get aiHistoryRename => 'Renomear';

  @override
  String get aiHistoryPin => 'Fixar';

  @override
  String get aiHistoryUnpin => 'Desafixar';

  @override
  String get aiHistoryRenameTitle => 'Renomear conversa';

  @override
  String get aiHistoryRenameLabel => 'Nome da conversa';

  @override
  String get aiHistoryRenameHint => 'Digite um nome';

  @override
  String get aiHistoryRenameRequired => 'Digite um nome para a conversa';

  @override
  String get aiHistoryActionError =>
      'Não foi possível atualizar a conversa. Tente novamente.';

  @override
  String get aiHistoryYesterday => 'ontem';

  @override
  String get aiCoachFabTooltip => 'Abrir Treinador IA';

  @override
  String get aiCoachConfigureBeforeChat =>
      'Configure um provedor de IA antes de abrir o chat.';

  @override
  String get aiSettingsTitle => 'Configurações do AI Coach';

  @override
  String get aiSettingsFabTitle => 'Mostrar botão do Treinador IA';

  @override
  String get aiSettingsFabSubtitle =>
      'Exibe o atalho do Treinador IA nas telas do app.';

  @override
  String get aiSettingsProvidersCard => 'Provedores';

  @override
  String get aiSettingsProvidersHelp =>
      'Adicione um endpoint compatível com OpenAI (OpenAI, Ollama, OpenRouter, Groq, LM Studio…).';

  @override
  String get aiSettingsAddProvider => 'Adicionar provedor';

  @override
  String get aiSettingsNoProviders => 'Nenhum provedor';

  @override
  String get aiSettingsNoProvidersSubtitle =>
      'Adicione um provedor para começar a usar o Treinador IA.';

  @override
  String get aiSettingsActivate => 'Ativar';

  @override
  String get aiSettingsEdit => 'Editar';

  @override
  String get aiSettingsRemove => 'Remover';

  @override
  String aiSettingsRemoveConfirmTitle(Object name) {
    return 'Remover $name?';
  }

  @override
  String get aiSettingsRemoveConfirmBody => 'O token será removido também.';

  @override
  String get aiSettingsBaseUrl => 'URL base';

  @override
  String get aiSettingsModel => 'Modelo';

  @override
  String aiSettingsModelValue(Object model) {
    return 'Modelo: $model';
  }

  @override
  String get aiSettingsProviderName => 'Nome';

  @override
  String get aiSettingsNameRequired => 'Informe um nome.';

  @override
  String get aiSettingsBaseUrlRequired => 'Informe uma URL base.';

  @override
  String get aiSettingsNoModelsEmpty => 'Nenhum modelo disponível';

  @override
  String get aiSettingsToken => 'Token de API';

  @override
  String get aiSettingsTokenHint => 'Vazio para manter o token atual';

  @override
  String get aiSettingsNameHint => 'OpenAI, Ollama local, OpenRouter…';

  @override
  String get aiSettingsBaseUrlHint => 'https://api.openai.com/v1';

  @override
  String get aiSettingsNewProvider => 'Novo provedor';

  @override
  String get aiSettingsEditProvider => 'Editar provedor';

  @override
  String get aiSettingsFetchModels => 'Buscar modelos';

  @override
  String aiSettingsNoModels(Object url) {
    return 'Nenhum modelo carregado. Toque em \"Buscar modelos\" para listar os disponíveis em $url.';
  }

  @override
  String get aiSettingsContextMode => 'Modo de contexto';

  @override
  String get aiSettingsContextModeHelp =>
      'Quantos dados são enviados à IA em cada turno. Mais contexto = respostas melhores, porém mais tokens.';

  @override
  String get aiSettingsContextModeMinimal => 'Mínimo';

  @override
  String get aiSettingsContextModeMinimalSubtitle =>
      'Apenas totais e streak. IA usa ferramentas para detalhes.';

  @override
  String get aiSettingsContextModeStandard => 'Padrão';

  @override
  String get aiSettingsContextModeStandardSubtitle =>
      'Resumo + metas + top exercícios. Bom equilíbrio.';

  @override
  String get aiSettingsContextModeFull => 'Completo';

  @override
  String get aiSettingsContextModeFullSubtitle =>
      'Tudo: categorias, tendência corporal, volume detalhado.';

  @override
  String get aiSettingsSystemPrompt => 'Prompt do sistema';

  @override
  String get aiSettingsSystemPromptHelp =>
      'Define a personalidade e o comportamento do Treinador IA.';

  @override
  String get aiSettingsRestoreDefault => 'Restaurar padrão';

  @override
  String get aiSettingsSaved => 'Salvo';

  @override
  String get aiSettingsAbout => 'Sobre';

  @override
  String get aiSettingsAboutBody =>
      'O Treinador IA envia um resumo dos seus dados a cada turno e tem acesso a 13 ferramentas de leitura. Não consegue editar seus dados. As conversas são salvas localmente.';

  @override
  String get sleepSettingsTitle => 'Configurações do sono';

  @override
  String get sleepSettingsGoalSection => 'META DE SONO';

  @override
  String get sleepSettingsMissionSection => 'MISSÃO DO DESPERTADOR';

  @override
  String get sleepMissionToggle => 'Missão por código de barras';

  @override
  String get sleepMissionToggleBody =>
      'Exige uma missão quando você escolher o alarme protegido.';

  @override
  String get sleepMissionNotConfigured => 'Nenhum código cadastrado';

  @override
  String sleepMissionConfigured(String format) {
    return 'Código cadastrado: $format';
  }

  @override
  String get sleepMissionScan => 'Ler código';

  @override
  String get sleepMissionReplace => 'Substituir código';

  @override
  String get sleepMissionRemove => 'Remover código';

  @override
  String get sleepMissionRemoveConfirm =>
      'Remover o código cadastrado? Alarmes protegidos já iniciados não serão alterados.';

  @override
  String get sleepMissionScanError =>
      'Não foi possível ler o código de barras.';

  @override
  String get sleepMissionCameraDenied =>
      'A permissão da câmera é necessária para ler a missão.';

  @override
  String get sleepMonitorModeSection => 'COMO MONITORAR';

  @override
  String get sleepMonitorModeAlarmNoMission => 'Monitorar + alarme sem missão';

  @override
  String get sleepMonitorModeAlarmWithMission =>
      'Monitorar + alarme com missão';

  @override
  String get sleepMonitorModeOnly => 'Somente monitorar, sem alarme';

  @override
  String get sleepMonitorModeAlarmNoMissionBody =>
      'O alarme tocará no horário escolhido e poderá ser desligado normalmente.';

  @override
  String get sleepMonitorModeAlarmWithMissionBody =>
      'Para desligar, leia o código cadastrado ou complete a emergência com 500 toques.';

  @override
  String get sleepMonitorModeOnlyBody =>
      'Monitora o ambiente sem programar despertador.';

  @override
  String get sleepMonitorModeMissionUnavailable =>
      'Configure uma missão por código de barras para liberar este modo.';

  @override
  String get sleepMonitorStartOnly => 'Iniciar somente monitoramento';

  @override
  String sleepMonitorStartWithMission(String time) {
    return 'Iniciar e despertar às $time com missão';
  }

  @override
  String get sleepMonitorProtectedStop => 'Parar somente o monitoramento';

  @override
  String get sleepMonitorProtectedStopBody =>
      'O despertador e a missão continuarão ativos para este horário.';

  @override
  String get sleepMonitorMissionPending => 'Missão pendente';

  @override
  String get sleepMonitorMissionReady => 'Missão configurada';

  @override
  String get sleepMissionFormatUnknown => 'código de barras';

  @override
  String get sleepMissionRemoved => 'Missão removida para novas sessões.';

  @override
  String get sleepMissionSaved => 'Código cadastrado com sucesso.';

  @override
  String get sleepMissionOpenSettings => 'Abrir configurações da câmera';

  @override
  String get aiEmptyTitle => 'Configure um provedor de IA';

  @override
  String get aiEmptySubtitle =>
      'Adicione um endpoint OpenAI-compatible (OpenAI, Ollama, OpenRouter…) para começar a usar o Treinador IA.';

  @override
  String get aiEmptyConfigure => 'Configurar provedor';
}
