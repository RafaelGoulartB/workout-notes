/// ====================================================================
/// ABSTRACT MIXIN — Settings screen
/// ====================================================================
mixin SettingsLocale {
  String get settingsTitle;
  String get settingsAppearance;
  String get settingsThemeColor;
  String get settingsThemeMode;
  String get settingsSystem;
  String get settingsSystemSubtitle;
  String get settingsLight;
  String get settingsLightSubtitle;
  String get settingsDark;
  String get settingsDarkSubtitle;
  String get settingsUnits;
  String get settingsUnitSystem;
  String get settingsUnitKgCm;
  String get settingsUnitLbsIn;
  String get settingsTimer;
  String get settingsDefaultRest;
  String get settingsSeconds;
  String get settingsAutoStartRest;
  String get settingsAutoStartRestSubtitle;
  String get settingsAutoStartWorkoutTimer;
  String get settingsAutoStartWorkoutTimerSubtitle;
  String get settingsNotifications;
  String get settingsRestTimerNotif;
  String get settingsRestTimerNotifSubtitle;
  String get settingsWorkoutTimerNotif;
  String get settingsWorkoutTimerNotifSubtitle;
  String get settingsAlertOptions;
  String get settingsSound;
  String get settingsRestSoundSubtitle;
  String get settingsWorkoutSoundSubtitle;
  String get settingsVibration;
  String get settingsRestVibrationSubtitle;
  String get settingsWorkoutVibrationSubtitle;
  String get settingsDisplay;
  String get settingsKeepScreenOn;
  String get settingsKeepScreenOnSubtitle;
  String get settingsData;
  String get settingsExportBackup;
  String get settingsExportBackupSubtitle;
  String get settingsGenerateTestData;
  String get settingsGenerateTestDataSubtitle;
  String get settingsGenerateTitle;
  String get settingsGenerateContent;
  String get settingsGenerate;
  String settingsGenerateSuccess(Object count);
  String get settingsAbout;
  String get settingsAboutSubtitle;
  String get settingsDeleteAllHistory;
  String get settingsDeleteHistoryTitle;
  String get settingsDeleteHistoryContent;
  String get settingsDeleteEverything;
  String get settingsDeleteHistorySuccess;
  String get settingsExportSuccess;
  String settingsExportError(Object error);
  String get settingsLanguage;
  String get settingsEnglish;
  String get settingsPortuguese;
  String get settingsLanguageSubtitle;
}

/// ====================================================================
/// EN IMPLEMENTATION
/// ====================================================================
mixin SettingsLocaleEn on SettingsLocale {
  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsThemeColor => 'Theme Color';

  @override
  String get settingsThemeMode => 'Theme Mode';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsSystemSubtitle => 'Follow device setting';

  @override
  String get settingsLight => 'Light';

  @override
  String get settingsLightSubtitle => 'Force light mode';

  @override
  String get settingsDark => 'Dark';

  @override
  String get settingsDarkSubtitle => 'Force dark mode';

  @override
  String get settingsUnits => 'Units';

  @override
  String get settingsUnitSystem => 'Unit System';

  @override
  String get settingsUnitKgCm => 'kg / cm';

  @override
  String get settingsUnitLbsIn => 'lbs / in';

  @override
  String get settingsTimer => 'Timer';

  @override
  String get settingsDefaultRest => 'Default Rest';

  @override
  String get settingsSeconds => 'seconds';

  @override
  String get settingsAutoStartRest => 'Auto-start Rest Timer';

  @override
  String get settingsAutoStartRestSubtitle =>
      'Start automatically after each set';

  @override
  String get settingsAutoStartWorkoutTimer => 'Auto-start Workout Timer';

  @override
  String get settingsAutoStartWorkoutTimerSubtitle =>
      'Start timer after 1st set, stop after last set';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsRestTimerNotif => 'Rest Timer';

  @override
  String get settingsRestTimerNotifSubtitle => 'Notification between sets';

  @override
  String get settingsWorkoutTimerNotif => 'Workout Timer';

  @override
  String get settingsWorkoutTimerNotifSubtitle =>
      'Active workout notification';

  @override
  String get settingsAlertOptions => 'Alert options';

  @override
  String get settingsSound => 'Sound';

  @override
  String get settingsRestSoundSubtitle =>
      'Play sound when rest starts and ends';

  @override
  String get settingsWorkoutSoundSubtitle => 'Play sound when workout starts';

  @override
  String get settingsVibration => 'Vibration';

  @override
  String get settingsRestVibrationSubtitle =>
      'Vibrate when rest starts and ends';

  @override
  String get settingsWorkoutVibrationSubtitle =>
      'Vibrate when workout starts';

  @override
  String get settingsDisplay => 'Display';

  @override
  String get settingsKeepScreenOn => 'Keep Screen On';

  @override
  String get settingsKeepScreenOnSubtitle => 'During workout';

  @override
  String get settingsData => 'Data';

  @override
  String get settingsExportBackup => 'Export Backup';

  @override
  String get settingsExportBackupSubtitle =>
      'Full JSON backup to save or transfer';

  @override
  String get settingsGenerateTestData => 'Generate Test Data';

  @override
  String get settingsGenerateTestDataSubtitle =>
      'Adds fictional workouts to test the app';

  @override
  String get settingsGenerateTitle => 'Generate Test Data?';

  @override
  String get settingsGenerateContent =>
      'This will add fictional workouts from recent months to test charts and features.\n\nUse "Delete All History" to remove them later.';

  @override
  String get settingsGenerate => 'Generate';

  @override
  String settingsGenerateSuccess(Object count) {
    return '✅ $count workouts generated!';
  }

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAboutSubtitle => 'Workout Notes v1.0';

  @override
  String get settingsDeleteAllHistory => 'Delete All Workout History';

  @override
  String get settingsDeleteHistoryTitle => 'Delete All History?';

  @override
  String get settingsDeleteHistoryContent =>
      'All workouts, sets and registered exercises will be deleted. This action cannot be undone.';

  @override
  String get settingsDeleteEverything => 'Delete Everything';

  @override
  String get settingsDeleteHistorySuccess => 'History deleted';

  @override
  String get settingsExportSuccess => '✅ Backup exported!';

  @override
  String settingsExportError(Object error) {
    return 'Error: $error';
  }

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsEnglish => 'English';

  @override
  String get settingsPortuguese => 'Português (Brasil)';

  @override
  String get settingsLanguageSubtitle => 'App interface language';
}

/// ====================================================================
/// PT IMPLEMENTATION
/// ====================================================================
mixin SettingsLocalePt on SettingsLocale {
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
      'Isso vai adicionar treinos fictícios nos últimos meses para testar gráficos e funcionalidades.\n\nUse "Excluir Todo Histórico" para remover depois.';

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
}
