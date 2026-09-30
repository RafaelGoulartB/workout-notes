# Plano consolidado de qualidade — Workout Notes

Base: commit `25b100c`, branch `refactor/code-quality`. Junta três fontes:

- [Revisão externa](code_quality_review_2026-09-29.md) (achados A01–A24) e o [plano dela](code_quality_remediation_plan.md).
- A revisão feita pelo Claude Code em 29/09/2026 (dados, UI, serviços, build/nativo/testes).

## Decisões do dono do projeto

1. **O app é somente Android.** iOS, web e desktop saem do repositório e da documentação. Caminhos duplicados que só existiam para outras plataformas (voz de corrida em Dart + `flutter_tts`) podem ser removidos. As guardas `defaultTargetPlatform == android` continuam, porque os testes rodam no desktop.
2. **Sono v2 pode ser apagado**, inclusive dados existentes: o motor heurístico Viterbi para `audio-features-v2`, o `SleepInferenceService` e `tool/validate_sleep_stages.dart`.
3. **Não existem instalações abaixo da v37.** As migrações v2–v36 podem ser consolidadas: um banco < v37 é recriado ou recusado. As migrações v37+ ficam.
4. **O scanner de código de barras continua com o ML Kit empacotado.** Não trocar pelo Play Services.
5. Commits locais por fase, **sem** trailer `Co-Authored-By`.

## Onde as fontes divergem e o que vale

| Tema | Decisão |
|---|---|
| Remover dependências | Remover as que têm substituto trivial (`flutter_animate` → `TweenAnimationBuilder`/`FadeTransition`, `csv` → writer de ~15 linhas). Remover `flutter_tts` junto com a voz Dart (decisão 1). Manter o resto. |
| Apagar migrações | Consolidar só abaixo da v37 (decisão 3). A v37+ fica, com testes de upgrade das v53–v56. |
| Profiling em aparelho (A24) | Não dá para fazer daqui. Em troca: testes que contam consultas nos caminhos em lote e o estudo de armazenamento movido para `tool/benchmark`. As medições em aparelho ficam como tarefa manual do dono. |
| Busca local por substring (A23) | Condicional: só registrar um benchmark sintético. Sem FTS. |
| Checagens `_tableExists` | Remover as que as migrações v37+ já garantem, corrigindo os testes com esquema escrito à mão para usarem o esquema real. |

## Pacotes de trabalho

Cada pacote é um commit (ou poucos). Validação obrigatória em cada um: `flutter analyze` limpo e a suíte afetada verde. Nos pacotes nativos, rodar `:app:testDebugUnitTest`.

### Fase 0 — Emergência (feita)
- A01: teste do monitor de sono atualizado para `Planned wake-up`.
- Wake lock do `SleepAlarmRingingService`: um único lock não contado, com timeout, re-armado a cada chamada.

### Fase 1 — Onda paralela

**WP1 — Código morto em Dart**
- Widgets sem consumidor: `nutrition_charts.dart`, `collapsible_section.dart`, `workout_heatmap.dart`, `workout/stat_tile.dart`.
- Classes sem uso: `RunAchievementsSection` e `_RecentAchievementTile`, `ExerciseBests`, `RunStepChip`, `WorkoutSettingsScreen`, `ProgressScreen` (apontar o teste para `StrengthInsightsScreen`).
- `lib/navigation/` (`AiCoachNavigation`, `navigatorKey`): trocar por `MaterialPageRoute`.
- `analytics_repository.dart`: manter só os métodos usados.
- Métodos mortos dos repositórios de periodização, planos de corrida, corrida, configurações, sono, treino, nutrição, exercícios e corpo, conforme o inventário da revisão. Métodos usados só por testes saem junto com o teste. `addPhase` vira fixture de teste.
- `DatabaseHelper`: migrar todos os chamadores para os repositórios (`xxxRepo`) e apagar a camada de compatibilidade. A persistência do chat de IA vai para `AiChatRepository`.
- Serviços:
  - `AiWorkoutToolService` (`listRunPlans`, `runPlanDetail`, `runSchedule`, `_runSessionJson`).
  - `ExportService` (`exportToCsv`, `shareCsvExport`, `deleteBackupFile`) e o repo `exportWorkoutsCsvData`.
  - `SleepMonitorService.getMissionCapabilities` e `requestCameraPermission`.
  - `PaceCalculator` e os getters soltos listados.
  - `RunTrackingService.stop()`.
  - Gravação redundante `flutter.flutter.<key>` em `run_voice_settings_store`.
- Sono v2 (decisão 2): ramo v1/v2 do `SleepStageEngine`, `SleepInferenceService` e `tool/validate_sleep_stages.dart`. Manter `SleepWakeEngine` e um status `legacy` para linhas antigas.
- Leituras das tabelas mortas `sleep_monitor_segments` e `sleep_stage_epochs` (o DROP entra no WP4).
- Chaves ARB sem uso (EN e PT, em paralelo). Depois, `flutter gen-l10n`.
- `ios/` e `web/`, e os `kIsWeb` redundantes.
- Parâmetros de construtor nunca passados.

**WP2 — Android nativo**
- A03: executor sequencial para I/O do spool de corrida (append, checkpoints, leitura e remoção), com flush explícito em pausa e parada.
- Helpers comuns em `common/`: `immutableFlag` (já é `minSdk` 24, então sai a checagem `>= M`), `NotificationChannels.ensure`, `AlarmRinger` (som + vibração) e conversores JSON.
- Remover `SleepStageModelGate`, `SleepSessionSpool.appendStage` e os casos do bridge sem chamador.
- Quebrar as linhas gigantes de `TraditionalAlarmRingingService`.

**WP3 — CI e build**
- A07: workflow de validação para PR/push (analyze, testes Flutter e `:app:testDebugUnitTest` com Java 17, Flutter pinado), com gatilhos que incluem `test/**` e `tool/**`.
- Release: `--target-platform android-arm,android-arm64`, `--obfuscate --split-debug-info` (símbolos como artefato).
- Limpar o boilerplate do `pubspec.yaml`.
- Tirar `android/build/reports` do git.

### Fase 2 — Onda paralela

**WP4 — Banco e repositórios**
- Consolidar migrações abaixo da v37 (decisão 3).
- v56:
  - DROP de `sleep_monitor_segments`, `sleep_stage_epochs` e `run_track_points` (depois de compactar as rotas legadas uma última vez) e de `phase_routine_links`, se não houver leitura viva.
  - Índices que faltam: `exercise_entries(exercise_id)`, `workouts(routine_id)`, `workouts(routine_day_id)`, `meal_log_items(food_id)`, `meal_log_items(food_variant_id)`, `routine_days(routine_id)`, `routine_exercises(routine_day_id)` e `predefined_sets(routine_exercise_id)`.
  - Remover os índices redundantes.
- A06: testes de upgrade v53, v54, v55 e v56, e um salto v37→56.
- Remover as guardas `_tableExists`/`_columnExists` garantidas pelas migrações.
- A18: trocar `substr`/`date(started_at)` por intervalos, testando perto da meia-noite.
- A02: elegibilidade das metas (série concluída, não aquecimento, treino encerrado), alinhada às análises.
- Transações:
  - A05: `addSavedMealToDate` atômico.
  - `createWorkout`, `importRoutineDayToWorkout`, `copyWorkoutToDate` e `addExerciseToWorkout` em transação ou batch.
  - `finishWorkout` sem N+1.
- A08 e N+1: `getDayMeals` com 2 consultas; `getSavedMeals` em lote; metas em lote; `getRoutineSuggestion`.
- Manutenção de rotas (`migrateLegacyRoutes`, `optimizeOldRoutes`, `backfillSmoothedElevation`, vacuum): roda uma vez via migração ou flag, não a cada abertura. `repairSleepEntriesFromSessions` idem.
- Helper compartilhado `test/support/test_db.dart` com o esquema real. Migrar os testes que escrevem `CREATE TABLE` à mão.

**WP5 — Backup (A04, A13)**
- Encode e decode fora do isolate da UI, com JSON compacto.
- Mídia processada arquivo a arquivo, com o tamanho validado antes de decodificar.
- Materialização com cleanup em qualquer falha.
- O formato continua legível pelos backups antigos.

### Fase 3 — Onda paralela

**WP6 — Desempenho e ciclo de vida da UI**
- A11: timers e listeners isolados em widgets pequenos (`ValueNotifier`) na home, no treino ativo e no monitor de sono. A notificação do treino atualiza por minuto ou por mudança de estado.
- A09 e A12: a home carrega em paralelo onde for independente e usa token de geração. Estados de erro com opção de repetir na home de treino, sono, nutrição, metas e periodização.
- Treino ativo:
  - Marcar ou adicionar uma série atualiza em memória, sem recarregar tudo.
  - O SQL da tela vai para o `WorkoutRepository`.
  - `_computeSummary` passa para um `WorkoutSummaryService`.
- A10: `initialize()` compartilhado (Future em andamento) em `RunTrackingService` e no monitor de sono.
  - O AI Coach carrega sob demanda.
  - `NotificationService` também é lazy.
  - O flag de migração do token no Keystore evita a leitura a cada abertura.
  - Sai o trio redundante de setters no `main.dart`.
- Canais de notificação: mudar som ou vibração cria um canal com ID versionado e apaga o antigo.
- A19: `cacheWidth` nas miniaturas.
- A20: ownership dos `http.Client`.
- A21: busca do histórico de IA no SQLite, com lista sob demanda.
- Biblioteca de exercícios com slivers e o filtro fora do `build`.
- `setState` depois de `await` sem `mounted` (5 lugares).
- Os 3 textos fixos no monitor de sono.

**WP7 — Utilitários compartilhados**
- `lib/utils/date_utils.dart` (`dayOf`, `mondayOf`, `addDays`, `dateKey`) no lugar dos cerca de 14 cálculos de segunda-feira, 18 helpers de dia e 92 `substring(0,10)`. Usar `DateTime(y, m, d - n)` para ficar seguro com horário de verão.
- Formatadores de pace e duração unificados em `RunFormatters`, com um helper `paceOf`.
- `ai_tool_math.dart` para os helpers repetidos nos serviços de IA.

**WP8 — Kit de UI**
- `run_ui.dart` vira `lib/widgets/ui/`, com nomes `App*`.
- Unificar:
  - Cards e headers de seção.
  - Divisores.
  - Heatmap genérico.
  - Painter tracejado das faixas de semana.
  - Cores de macros (`NutritionMacroColors`).
  - `showConfirmDialog` genérico.
  - `_StatusChip` e `_MetricChip`.
  - Anéis.
  - Banners de sessão ativa.
- Remover `flutter_animate`.

### Fase 4 — Onda paralela, arquivos disjuntos

**WP9 — Divisão de arquivos gigantes**
- `run_plan_composer.dart`: config, outline, planejador de semanas e construtores de sessão como partes; os tipos de template saem para `models/`, o que quebra o ciclo de imports.
- `settings_screen.dart`: uma tela por categoria; o backup vai para um serviço.
- `nutrition_progress_screen.dart`: um controller mais os widgets em `widgets/nutrition/progress/`.
- `ai_tool_registry.dart`: tabela `AiToolSpec` e `ai_tool_hints.dart` com regex estáticas. O catálogo continua completo e estável.
- `run_tracking_service.dart`: o simulador de debug fica atrás de uma interface.
- `nutrition_repository.dart`: dividir por seção.
- `RunFitnessAnalytics`: separar em fitness, carga e calendário.

**WP10 — Voz de corrida só nativa**
- Remover `RunVoiceCoach` Dart, os motores Dart de intervalos e passos, e `flutter_tts`.
- O anúncio de teste nas configurações passa a usar um método nativo.

**WP11 — Localização (A22) e tipagem (A17)**
- Resumo de proposta aplicada no idioma do usuário.
- Títulos genéricos, fallbacks e erros de backup localizados.
- Modelos tipados nos caminhos que foram tocados.

### Fase 5 — Sequencial, no fim

**WP12 — Organização**
- Dividir `lib/screens/workout/` por módulo: `nutrition/`, `sleep/`, `planning/`, `ai/`, `body/`, `settings/`, `alarms/`.
- Trocar os imports relativos por `package:`.
- Lints mais rígidos, mais `dart fix --apply`: `unawaited_futures`, `prefer_const_constructors`, `prefer_const_declarations`, `unnecessary_lambdas`, `unnecessary_breaks`, `cancel_subscriptions`, `close_sinks`, `avoid_dynamic_calls` e `always_use_package_imports`.
- Mover `test/long_term_storage_study.dart` para `tool/benchmark/`.
- Atualizar `CLAUDE.md` e `AGENTS.md` (só Android, sono v2 removido, sem `restageSleepStageEpochs`, l10n gerado não commitado, número de ferramentas da IA).

## Fora de escopo, com motivo
- Trocar o ML Kit (decisão 4).
- Trocar a gestão de estado, reescrever o app ou criar DI ou cache global (as duas revisões concordam).
- Profiling em aparelho físico (A24): é tarefa manual. O protocolo está no plano externo.
- FTS na busca de alimentos (A23): só com benchmark que justifique.
