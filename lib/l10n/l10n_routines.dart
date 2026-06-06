/// ====================================================================
/// ABSTRACT MIXIN — Routines screen
/// ====================================================================
mixin RoutinesLocale {
  String get routinesTitle;
  String get routinesNew;
  String get routinesName;
  String get routinesNameHint;
  String get routinesCreate;
  String get routinesEdit;
  String get routinesDelete;
  String routinesDeleteConfirm(Object name);
  String get routinesDeleteContent;
  String get routinesEmptyTitle;
  String get routinesEmptySubtitle;
  String get routinesRename;
  String get routinesNewDay;
  String get routinesDayName;
  String get routinesDayNameHint;
  String get routinesAddDay;
  String get routinesDeleteDay;
  String get routinesDayEmpty;
  String get routinesDayEmptySubtitle;
  String get routinesNoExercises;
  String get routinesAddExercise;
  String get routinesRestTimeTitle;
}

/// ====================================================================
/// EN IMPLEMENTATION
/// ====================================================================
mixin RoutinesLocaleEn on RoutinesLocale {
  @override
  String get routinesTitle => 'Routines';

  @override
  String get routinesNew => 'New Routine';

  @override
  String get routinesName => 'Routine Name';

  @override
  String get routinesNameHint => 'Ex: Push Pull Legs';

  @override
  String get routinesCreate => 'Create';

  @override
  String get routinesEdit => 'Edit Routine';

  @override
  String get routinesDelete => 'Delete Routine';

  @override
  String routinesDeleteConfirm(Object name) {
    return 'Delete "$name"?';
  }

  @override
  String get routinesDeleteContent => 'All routine data will be lost.';

  @override
  String get routinesEmptyTitle => 'No routines yet';

  @override
  String get routinesEmptySubtitle => 'Create a routine to train faster';

  @override
  String get routinesRename => 'Rename';

  @override
  String get routinesNewDay => 'New Day';

  @override
  String get routinesDayName => 'Day Name';

  @override
  String get routinesDayNameHint => 'Ex: Push Day, Monday';

  @override
  String get routinesAddDay => 'Add Day';

  @override
  String get routinesDeleteDay => 'Delete Day';

  @override
  String get routinesDayEmpty => 'No days yet';

  @override
  String get routinesDayEmptySubtitle => 'Add days to your routine';

  @override
  String get routinesNoExercises => 'No exercises added';

  @override
  String get routinesAddExercise => 'Add Exercise';

  @override
  String get routinesRestTimeTitle => 'Rest Time';
}

/// ====================================================================
/// PT IMPLEMENTATION
/// ====================================================================
mixin RoutinesLocalePt on RoutinesLocale {
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
    return 'Excluir "$name"?';
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
}
