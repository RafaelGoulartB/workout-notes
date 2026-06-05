/// ====================================================================
/// ABSTRACT MIXIN — Common / App-wide strings
/// ====================================================================
mixin CommonLocale {
  String get appTitle;
  String get tabWorkout;

  String get commonCancel;
  String get commonDelete;
  String get commonSave;
  String get commonDiscard;
  String get commonKeepEditing;
  String commonError(Object error);
  String get commonSearch;
  String get commonAll;
  String get commonExercises;
  String get commonVolume;
  String get commonSets;
  String get commonReps;
  String get commonCompleted;
  String get commonInProgress;
  String get commonConfirmDelete;
  String get commonActionCannotBeUndone;

  String get accentColorRed;
  String get accentColorDarkOrange;
  String get accentColorOrange;
  String get accentColorAmber;
  String get accentColorDeepPurple;
  String get accentColorDarkBlue;
  String get accentColorGraphite;
  String get accentColorForestGreen;

  String get noticePermissionTitle;
  String get noticePermissionBody;
}

/// ====================================================================
/// EN IMPLEMENTATION
/// ====================================================================
mixin CommonLocaleEn on CommonLocale {
  @override
  String get appTitle => 'Workout Notes';

  @override
  String get tabWorkout => 'Workout';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDiscard => 'Discard';

  @override
  String get commonKeepEditing => 'Keep editing';

  @override
  String commonError(Object error) {
    return 'Error: $error';
  }

  @override
  String get commonSearch => 'Search';

  @override
  String get commonAll => 'All';

  @override
  String get commonExercises => 'Exercises';

  @override
  String get commonVolume => 'Volume';

  @override
  String get commonSets => 'Sets';

  @override
  String get commonReps => 'Reps';

  @override
  String get commonCompleted => 'Completed';

  @override
  String get commonInProgress => 'In progress';

  @override
  String get commonConfirmDelete => 'Are you sure?';

  @override
  String get commonActionCannotBeUndone => 'This action cannot be undone.';

  @override
  String get accentColorRed => 'Deep Red';

  @override
  String get accentColorDarkOrange => 'Dark Orange';

  @override
  String get accentColorOrange => 'Orange';

  @override
  String get accentColorAmber => 'Amber';

  @override
  String get accentColorDeepPurple => 'Deep Purple';

  @override
  String get accentColorDarkBlue => 'Dark Blue';

  @override
  String get accentColorGraphite => 'Graphite';

  @override
  String get accentColorForestGreen => 'Forest Green';

  @override
  String get noticePermissionTitle => 'Rest Timer Permission';

  @override
  String get noticePermissionBody =>
      'This app needs notification permission to alert you when rest time is over during workouts.';
}

/// ====================================================================
/// PT IMPLEMENTATION
/// ====================================================================
mixin CommonLocalePt on CommonLocale {
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
  String get noticePermissionTitle => 'Permissão do Timer';

  @override
  String get noticePermissionBody =>
      'Este app precisa de permissão de notificação para alertar quando o descanso entre séries terminar.';
}
