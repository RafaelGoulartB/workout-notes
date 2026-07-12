# Plano completo de refatoração e manutenção do Workout Notes

## Status da implementação

### Concluído

- Formatação de `lib/` e `test/`, correções de estilo e verificação de formatação no CI.
- Operações compostas de treino centralizadas no repositório e protegidas por transações: criação, treino rápido, adição de exercício, importação de rotina e cópia de treino.
- Chaves estrangeiras SQLite ativadas em toda abertura de banco.
- SQL de recordes pessoais removido da tela de treino ativo e movido para `WorkoutRepository`.
- Modelos de resumo, recordes e melhores resultados de treino extraídos do widget de finalização.
- Conversão de datas de treino centralizada em `AppDateCodec`.
- Código morto do cabeçalho legado do chat de IA removido.

### Pendente

- Separar `DatabaseHelper` em conexão, schema, migrações e seed.
- Injetar dependências nos repositórios e remover o acoplamento implícito ao singleton.
- Tipar os principais resultados SQLite ainda representados por `Map<String, dynamic>`.
- Extrair controladores e widgets das telas grandes: treino ativo, configurações, rotina e dashboard.
- Criar editor de séries compartilhado entre treino ativo e rotina.
- Separar persistência e orquestração do módulo de IA.
- Consolidar configurações, tema, locale, erros e localização.
- Atualizar documentação arquitetural ao fim das alterações estruturais.

## Resumo

Refatorar o aplicativo preservando funcionalidades, UX, armazenamento local e arquitetura leve baseada em `setState`/`ChangeNotifier`. O foco será reduzir acoplamento, eliminar SQL da camada de interface, substituir mapas dinâmicos por modelos tipados, dividir arquivos com responsabilidades excessivas, consolidar componentes duplicados e tornar erros e operações compostas mais seguros.

Não serão adicionados testes. Os testes existentes serão preservados e continuarão no CI. A validação será feita com formatação, análise estática, testes existentes, build e smoke check manual.

## Escopo e premissas

- Preservar telas, navegação, banco existente e compatibilidade dos backups.
- Não introduzir Riverpod, Bloc, Provider ou geradores de código.
- Não redesenhar a interface nem adicionar funcionalidades.
- Não atualizar dependências apenas por estarem desatualizadas.
- Não alterar o schema SQLite quando a refatoração puder ser feita sem migração.
- Manter `Map<String, dynamic>` somente nas fronteiras inevitáveis: SQLite bruto, JSON de backup, payloads HTTP e schemas de tools da IA.
- Corrigir riscos encontrados, incluindo operações parciais, falhas silenciosas, uso inseguro de contexto assíncrono e duplicação de persistência.
- Preservar alterações locais e arquivos gerados que não pertençam à refatoração.

## 1. Normalização inicial do código

- Executar `dart format` em `lib/` e manter essa alteração isolada das refatorações estruturais.
- Converter os 136 imports relativos restantes para `package:workout_notes/...`.
- Ordenar imports de Dart, Flutter, pacotes externos e projeto.
- Remover comentários obsoletos, separadores decorativos e documentação que menciona arquitetura antiga.
- Remover `_buildProviderHeader` de `ai_chat_screen.dart`, atualmente mantido como código morto com `ignore: unused_element`.
- Migrar `RadioListTile` da configuração de IA para a API atual com `RadioGroup`, eliminando suppressões de depreciação.
- Corrigir os dois fluxos de `active_workout_screen.dart` que suprimem `use_build_context_synchronously`, capturando o contexto necessário antes do `await` ou verificando `context.mounted`.
- Remover `setState(() {})` redundantes após métodos que já atualizam o estado.
- Substituir textos de interface ainda escritos diretamente em português, como erros de reordenação e confirmação de remoção, por chaves ARB em inglês e português.
- Adicionar a `analysis_options.yaml`:
  - `always_use_package_imports`
  - `directives_ordering`
  - `unawaited_futures`
  - `depend_on_referenced_packages`
  - `cancel_subscriptions`
  - `close_sinks`
- Tratar explicitamente futures intencionalmente não aguardados com `unawaited(...)`.
- Adicionar ao CI uma verificação somente leitura de formatação: `dart format --output=none --set-exit-if-changed lib`.

## 2. Separação da infraestrutura SQLite

### Estrutura

Criar:

- `lib/database/database_provider.dart`: interface com `Future<Database> get database`.
- `lib/database/app_database.dart`: singleton responsável somente por abrir e fornecer a conexão.
- `lib/database/database_schema.dart`: criação integral do schema atual.
- `lib/database/database_migrations.dart`: migrações incrementais por versão.
- `lib/database/database_seed.dart`: aplicação dos dados e configurações iniciais.

### Mudanças

- Retirar de `DatabaseHelper`:
  - instâncias de repositórios;
  - mais de cem métodos de delegação;
  - persistência de chats e propostas de IA;
  - seed e SQL de migração embutidos.
- Fazer `AppDatabase` implementar `DatabaseProvider`.
- Configurar `PRAGMA foreign_keys = ON` em `onConfigure`, garantindo a aplicação dos `ON DELETE CASCADE`.
- Manter nome, versão e schema atuais do banco.
- Não incrementar `_dbVersion`, pois a reorganização não altera tabelas ou colunas.
- Trocar `try/catch` vazio das migrações por verificações explícitas:
  - `PRAGMA table_info` para colunas;
  - `sqlite_master` para tabelas e índices;
  - `CREATE TABLE/INDEX IF NOT EXISTS` quando aplicável.
- Permitir que falhas reais de migração sejam registradas e propagadas, evitando bancos parcialmente migrados que parecem válidos.
- Manter cada migração em uma função nomeada, como `_migrateToV15`, executada em ordem dentro de uma transação.
- Mover constantes de nomes de tabelas, colunas e chaves de configuração para arquivos do domínio correspondente, evitando strings repetidas.

## 3. Injeção de dependências sem biblioteca externa

Criar `lib/app/app_dependencies.dart` com instâncias únicas de:

- `AppDatabase`;
- todos os repositórios;
- serviços de exportação, notificações, IA e mutação de rotinas;
- controladores globais de aparência, idioma e IA.

Criar `AppDependenciesScope extends InheritedWidget` apenas para disponibilizar dependências, sem assumir gerenciamento de estado.

Alterações de interface:

```dart
abstract interface class DatabaseProvider {
  Future<Database> get database;
}

abstract class BaseRepository {
  final DatabaseProvider databaseProvider;
  const BaseRepository(this.databaseProvider);
}
```

- Todos os repositórios receberão `DatabaseProvider` pelo construtor.
- Remover a dependência de `BaseRepository` em `DatabaseHelper.instance`.
- Telas e widgets obterão dependências no ponto de composição ou pelo `AppDependenciesScope`.
- Widgets reutilizáveis receberão somente a dependência específica que usam.
- Remover criações espalhadas como `WorkoutRepository()`, `GoalRepository()` e `SettingsRepository()`.
- Remover campos estáticos mutáveis de `WorkoutNotesApp`.
- Preservar singletons somente onde representam estado de aplicação genuinamente único, como o temporizador de descanso; mesmo nesses casos, a instância será criada e exposta por `AppDependencies`.

## 4. Modelos tipados para o domínio de treino

Criar modelos imutáveis com `fromRow`, `toRow` quando necessário, `copyWith` e enums para valores finitos:

- `ExerciseCategory`
- `Exercise`
- `Workout`
- `WorkoutListItem`
- `WorkoutDetail`
- `WorkoutExerciseEntry`
- `WorkoutSet`
- `Routine`
- `RoutineDay`
- `RoutineExercise`
- `PredefinedSet`
- `BodyMeasurement`
- DTOs tipados para relatórios e gráficos
- `AppSettings` tipado

Consolidar modelos já existentes:

- Usar uma única representação de exercício com séries; eliminar `_ExerciseWithSets` duplicado de `workout_detail_screen.dart`.
- Mover `WorkoutSummary`, `PR`, `CardioBests` e `ExerciseBests` de `finish_workout_sheet.dart` para `models/workout_summary.dart`.
- Mover `_ParsedSet` de `quick_add_screen.dart` para um modelo privado do fluxo ou `SetDraft`, caso seja reutilizado.
- Substituir strings de tipo de exercício por `ExerciseType`.
- Substituir inteiros SQLite usados como booleanos por conversões centralizadas.
- Centralizar conversões de data `yyyy-MM-dd` em `AppDateCodec`, evitando `toIso8601String().substring(0, 10)` espalhado.
- Não tipar internamente JSON arbitrário de APIs e tools; converter para modelos somente depois da validação da resposta.

Novas assinaturas representativas:

```dart
Future<List<Exercise>> getExercises(ExerciseFilter filter);
Future<WorkoutDetail?> getWorkoutDetail(String id);
Future<List<RoutineDay>> getRoutineDays(String routineId);
Future<List<BodyMeasurement>> getMeasurements(MeasurementFilter filter);
Future<MonthlyReport> getMonthlyReport(YearMonth month);
```

## 5. Reorganização dos repositórios

### WorkoutRepository

Dividir o arquivo atual em:

- `workout_repository.dart`: treinos e consultas de detalhes;
- `workout_entry_repository.dart`: exercícios dentro do treino;
- `workout_set_repository.dart`: séries;
- `workout_stats_repository.dart`: comparações, recordes e estatísticas de conclusão.

Adicionar operações de domínio atômicas:

```dart
Future<String> createQuickWorkout(QuickWorkoutDraft draft);
Future<String> addExerciseWithPreviousSets(AddWorkoutExerciseCommand command);
Future<void> importRoutineDay(String workoutId, String routineDayId);
Future<String> copyWorkout(CopyWorkoutCommand command);
Future<WorkoutCompletionResult> completeWorkout(CompleteWorkoutCommand command);
```

- Executar criação de treino, entrada, séries e conclusão do quick add em uma única transação.
- Executar importação de rotina e cópia completa de treino em transações.
- Mover para o repositório o SQL atualmente presente em `active_workout_screen.dart` e `quick_add_screen.dart`.
- Evitar gerar UUIDs e inserir `exercise_entries` diretamente nas telas.
- Preservar rollback otimista de reordenação, mas devolver uma exceção de domínio compreensível.

### AnalyticsRepository

Dividir por assunto:

- `training_volume_repository.dart`
- `exercise_analytics_repository.dart`
- `cardio_analytics_repository.dart`
- `recovery_analytics_repository.dart`
- `dashboard_analytics_repository.dart`

- Retornar DTOs tipados em vez de estruturas aninhadas de mapas.
- Mover cálculos puros para classes de domínio, deixando SQL e agregação de dados no repositório.
- Centralizar definição de períodos semanais e mensais para evitar aproximações divergentes de 30, 31 ou 7 dias em consultas diferentes.
- Preservar as fórmulas e resultados exibidos atualmente.

### Outros repositórios

- Separar persistência de chats em `AiChatRepository`.
- Separar propostas em `AiRoutineProposalRepository`.
- Fazer `AiChatThread`, `AiChatMessage` e `AiRoutineProposal` cuidarem da conversão de linhas.
- Manter `ExportImportRepository` responsável apenas por serialização/restauração do banco.
- Fazer restauração validar versão, estrutura e tipos antes de apagar os dados atuais.
- Manter toda a restauração dentro de uma transação.
- Substituir o acesso direto a `settingsRepo` por dependências explícitas.

## 6. Configurações, tema e idioma

Criar:

- `lib/models/app_settings.dart`
- `lib/state/app_preferences_controller.dart`
- `lib/services/app_preferences.dart`
- `lib/constants/settings_keys.dart`

Responsabilidades:

- `AppPreferences`: wrapper tipado de `SharedPreferences` para cor, tema e locale.
- `SettingsRepository`: configurações SQLite do treino, notificações e unidades.
- `AppPreferencesController extends ChangeNotifier`: estado de tema, cor e locale.
- `WorkoutSettingsController extends ChangeNotifier`: carregamento e atualização das configurações de treino.

Correções:

- Eliminar a duplicação de `theme_mode` entre SharedPreferences e SQLite; tema ficará somente em `AppPreferences`.
- Definir uma fonte única para locale e cor.
- Remover chamadas diretas a `SharedPreferences.getInstance()` de telas e serviços.
- Centralizar valores padrão em `AppSettings.defaults`.
- Substituir mapa `_settings` e chaves de texto por propriedades tipadas.
- Fazer o controlador atualizar persistência primeiro e estado depois; em falha, preservar o valor anterior e expor erro localizado.
- Fazer `NotificationService` receber preferências e configurações no construtor.
- Atualizar locale das notificações por uma API explícita, sem reler SharedPreferences a cada mudança.

## 7. Refatoração das telas grandes

### Treino ativo

Transformar `active_workout_screen.dart` em uma tela de composição e criar:

- `active_workout_controller.dart`
- `active_workout_state.dart`
- `workout_timer_card.dart`
- `active_workout_progress.dart`
- `workout_volume_comparison.dart`
- `routine_picker_sheet.dart`
- `exercise_rest_time_sheet.dart`

O controlador será responsável por:

- inicialização e carregamento;
- timer do treino;
- pausa e retomada;
- exercícios e séries;
- reordenação;
- integração com o timer de descanso;
- importação de rotina;
- conclusão e exclusão.

A tela continuará usando `ListenableBuilder`/`AnimatedBuilder`, sem nova biblioteca de estado.

Mover cálculo de resumo e consultas de recordes para `WorkoutCompletionService`. A interface receberá um `WorkoutCompletionResult` pronto para exibição.

### Editor de rotina

Criar:

- `routine_day_editor_controller.dart`
- `routine_day_state.dart`
- `routine_exercise_card.dart`
- `routine_day_summary.dart`

Extrair do editor:

- carregamento e alterações de exercícios;
- reordenação;
- descanso;
- CRUD de séries predefinidas;
- edição e exclusão do dia.

### Editor compartilhado de séries

Criar em `widgets/sets/`:

- `set_editor_sheet.dart`
- `set_editor_fields.dart`
- `numeric_stepper_field.dart`
- `set_draft.dart`

O editor será configurado por `ExerciseType` e aceitará peso, repetições, distância, tempo, aquecimento, RPE e comentário. Ele substituirá os controles quase duplicados de treino ativo e rotina, mantendo diferenças por configuração.

### Configurações

Dividir `settings_screen.dart` em:

- `workout_settings_controller.dart`
- `appearance_settings_section.dart`
- `workout_settings_section.dart`
- `notification_settings_section.dart`
- `data_settings_section.dart`
- `ai_settings_section.dart`
- `about_settings_section.dart`
- `settings_components.dart`

Mover exportação, compartilhamento, salvamento, importação e exclusão de dados para `BackupService`. A tela ficará responsável apenas por confirmação, seleção de arquivo e feedback.

### Dashboard

Dividir `workout_home_screen.dart` em:

- `workout_dashboard_controller.dart`
- `workout_dashboard_state.dart`
- `dashboard_header.dart`
- `active_workout_banner.dart`
- `dashboard_stats.dart`
- `dashboard_navigation_grid.dart`
- `workout_list_section.dart`
- `workout_list_card.dart`

Manter o temporizador visual no controlador e cancelar o `Timer` em `dispose`.

### Demais arquivos grandes

- `workout_detail_screen.dart`: extrair cabeçalho, métricas, destaques, distribuição e lista de exercícios.
- `future_workout_planner_screen.dart`: separar calendário/listagem, formulário e ações de planejamento.
- `edit_workout_screen.dart`: extrair editor de horário, comentário, sensação e exercícios.
- `routines_screen.dart`: separar listagem, formulário e dashboard de rotina.
- `body_tracker_dialogs.dart`: um arquivo por diálogo/formulário.
- `body_tracker_screen.dart`: controlador tipado e widgets de histórico/filtros.
- `progress_screen.dart`: manter somente navegação das seções e coordenação de carregamento.
- `volume_charts.dart` e demais arquivos extensos de gráficos: um arquivo por gráfico público, com componentes visuais compartilhados em `chart_components.dart`.
- Não dividir arquivos apenas por quantidade de linhas; cada extração deverá estabelecer uma responsabilidade e API clara.

## 8. Tratamento de erros e operações assíncronas

Criar uma hierarquia pequena:

```dart
sealed class AppException implements Exception {}
final class DatabaseException extends AppException {}
final class ValidationException extends AppException {}
final class ImportException extends AppException {}
final class AiException extends AppException {}
```

- Repositórios propagam erros tipados e não exibem UI.
- Controladores convertem erros em estado.
- Telas mostram `SnackBar` ou diálogo com mensagens localizadas.
- Criar `AppLogger` usando `dart:developer`, sem adicionar dependência.
- Substituir `catch (_) {}` por uma destas decisões explícitas:
  - registrar e continuar quando o dado for opcional;
  - retornar um resultado parcial identificado;
  - propagar quando a operação principal falhar.
- Preservar catches tolerantes apenas na leitura de dados externos antigos, registrando o descarte.
- Capturar `ScaffoldMessengerState` antes de operações demoradas quando necessário.
- Verificar `mounted`/`context.mounted` após cada `await` que anteceda interação com widget.
- Impedir chamadas concorrentes de salvar, importar, concluir ou aplicar proposta por meio de estado `isBusy`.
- Garantir cancelamento de timers, listeners e clientes que possuam ciclo de vida.
- Fazer `AiService` implementar `close()` para fechar o `http.Client` quando ele for criado internamente.

## 9. Localização e formatação

- Criar extensão:

```dart
extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
```

- Substituir as centenas de chamadas repetidas a `AppLocalizations.of(context)!`.
- Adicionar ao ARB todas as mensagens de erro, confirmação e fallback ainda literais.
- Manter o catálogo dinâmico de nomes de exercícios separado do ARB, pois as traduções são resolvidas por chave vinda do banco.
- Renomear esse catálogo para deixar clara sua função e usar somente `Locale.languageCode`, evitando comparações inconsistentes entre `pt` e `pt_BR`.
- Centralizar:
  - formatação de duração;
  - peso e volume;
  - distância e ritmo;
  - datas e meses;
  - tempo de descanso.
- Remover implementações duplicadas como `_formatVolume`, `_formatDistance`, `_formatMinutes` e `_formatRestTime` das telas.
- Passar unidade e locale explicitamente aos formatadores, sem depender de `Intl.defaultLocale` dentro da camada de domínio.
- Regenerar `app_localizations*.dart` somente por `flutter gen-l10n`; não editar os arquivos gerados manualmente.

## 10. Organização do módulo de IA

### Estado e orquestração

Dividir `AiChatService` em:

- `AiChatController extends ChangeNotifier`: somente estado público e comandos da UI;
- `AiTurnRunner`: execução de um turno e limite de rodadas;
- `AiConversationBuilder`: prompt, contexto e compactação;
- `AiChatRepository`: threads e mensagens;
- `AiRoutineProposalCoordinator`: aprovação/rejeição e resumo posterior.

Preservar fluxo, limite de tools, recuperação de turnos interrompidos e ausência de streaming.

### Tools

Substituir o grande registro central por definições autocontidas:

```dart
abstract interface class AiToolDefinition {
  String get name;
  Map<String, dynamic> get schema;
  String label(AppLocalizations l10n);
  Future<AiToolResult> execute(Map<String, dynamic> arguments);
}
```

- Criar uma definição por tool ou por domínio pequeno.
- Registrar as definições em um mapa imutável por nome.
- Colocar schema, validação de argumentos, label e execução juntos.
- Criar parsers reutilizáveis para aliases inglês/português.
- Manter os resultados em JSON somente na fronteira enviada ao modelo.

### Contexto e propostas

- Dividir `AiContextService` em provedores de contexto de treino, rotinas, metas e medidas.
- Representar indisponibilidade parcial no metadata em vez de silenciosamente retornar mapas vazios.
- Manter cache de 60 segundos, mas encapsulá-lo em `AiContextCache`.
- Dividir `AiRoutineMutationService` em:
  - parser/validador da proposta;
  - gerador de diff;
  - verificador de snapshot;
  - aplicador transacional.
- Manter aprovação explícita, bloqueio de proposta obsoleta e transação única.
- Mover prompt padrão e política fixa para arquivos próprios em `ai/prompts/`.

## 11. Componentes e utilitários compartilhados

Criar componentes reutilizáveis apenas onde já existe repetição:

- `ConfirmationDialog`
- helper central de `SnackBar` para sucesso/erro;
- `SettingsCard`, `SettingsSectionHeader` e tiles em `widgets/settings/`;
- `AppLoadingState` e `AppErrorState`;
- seletores de duração e descanso;
- formatadores de unidade;
- modelos de filtro e paginação.

Consolidar componentes redundantes:

- cabeçalhos privados de seção com aparência equivalente;
- chips de estatística equivalentes;
- toggles segmentados repetidos nos gráficos;
- campos numéricos de peso/repetição/distância/tempo;
- cards de exercícios usados em detalhe, rotina e treino, mantendo variantes por parâmetros.

Evitar um arquivo genérico `utils.dart`; cada utilitário ficará no domínio correspondente.

## 12. Documentação e convenções

- Atualizar `AGENTS.md` para refletir que o app é somente workout e não possui mais módulo de notas.
- Corrigir as seções conflitantes sobre entrada do AI Coach e ferramentas de mutação por proposta.
- Documentar a nova direção de dependências:
  - UI → controller → repository/service → database provider.
- Documentar quais mapas dinâmicos são permitidos.
- Documentar que operações que criam uma árvore de dados devem ser transacionais.
- Atualizar o mapa de arquivos do README/AGENTS.
- Remover referências a `DatabaseHelper` como façade de domínio.
- Registrar decisões arquiteturais novas sem remover o histórico útil.

## 13. Ordem de implementação

1. Formatação, imports, lints, código morto e localização literal.
2. `DatabaseProvider`, `AppDatabase`, schema, migrations e seed.
3. `AppDependencies` e injeção nos repositórios.
4. Extração de repositórios de chat/propostas e remoção da façade de compatibilidade.
5. Modelos tipados e conversores SQLite.
6. Refatoração dos repositórios e operações transacionais.
7. Preferências/configurações tipadas.
8. Editor compartilhado de séries.
9. Treino ativo e editor de rotina.
10. Configurações e dashboard.
11. Detalhes, planejamento, progresso, medidas e demais telas grandes.
12. Divisão do módulo de IA.
13. Limpeza final de suppressões, catches vazios, imports e documentação.

Cada etapa deverá terminar compilável antes da próxima. Adaptadores temporários poderão existir durante a migração, mas serão removidos na etapa imediatamente posterior; não permanecerão na versão final.

## 14. Validação e cenários de aceitação

Não serão criados novos arquivos ou casos de teste.

Após cada etapa:

- `dart format --output=none --set-exit-if-changed lib`
- `flutter analyze --no-pub`
- testes existentes afetados pela alteração, sem modificar sua cobertura;
- ao final, `flutter test --no-pub`;
- build Android debug ou release conforme ambiente disponível.

Smoke checks manuais finais:

- iniciar, pausar, retomar, reordenar e concluir treino;
- adicionar, editar, concluir e excluir séries de todos os tipos;
- importar dia de rotina e confirmar cópia das séries;
- criar treino rápido e verificar que não ficam registros parciais em caso de erro;
- criar e editar rotina e séries predefinidas;
- abrir dashboard, calendário, progresso, metas e medidas;
- alterar tema, cor, idioma, unidades e notificações;
- exportar, importar e restaurar backup existente;
- abrir histórico e detalhe de treino;
- configurar provedor de IA, trocar modelo e enviar mensagem;
- executar tools de leitura;
- criar, rejeitar e aprovar proposta de rotina;
- fechar e reabrir o app confirmando persistência.

## Critérios de conclusão

- Nenhuma tela ou widget executa SQL ou acessa diretamente a conexão.
- `AppDatabase` contém somente infraestrutura de conexão.
- Não existe ciclo entre banco e repositórios.
- Repositórios são instâncias únicas e recebem dependências explicitamente.
- Dados SQLite usados pela UI são tipados.
- Operações compostas são transacionais.
- Não há `catch (_) {}` para falhas operacionais importantes.
- Não há suppressões manuais de `unused_element`, depreciação ou contexto assíncrono.
- Não há strings visíveis ao usuário fora do sistema de localização.
- Os principais arquivos deixam de misturar persistência, regras, estado e composição visual.
- A duplicação entre editores de séries é eliminada.
- Formatação e análise estática passam sem alterações ou avisos.
- A suíte existente e o build continuam passando.
