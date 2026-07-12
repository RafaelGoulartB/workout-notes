# Pendências de refatoração — Workout Notes

Este documento contém somente o trabalho estrutural que ainda falta. As
alterações já concluídas permanecem registradas no histórico Git.

## Infraestrutura SQLite

- Separar o conteúdo restante de `DatabaseHelper` em `DatabaseSchema`,
  `DatabaseMigrations` e `DatabaseSeed`.
- Migrar cada versão de banco para uma função nomeada e transacional, trocando
  `try/catch` vazios por verificações explícitas de tabelas, colunas e índices.
- Remover a fachada de domínio de `DatabaseHelper` após migrar os chamadores;
  `AppDatabase` deve ficar responsável somente pela conexão.
- Centralizar nomes de tabelas, colunas e chaves de configurações por domínio.

## Dependências e repositórios

- Concluir a migração de telas, widgets e serviços para as instâncias de
  `AppDependencies`/`AppDependenciesScope`.
- Remover construções implícitas de repositórios e os campos estáticos mutáveis
  de `WorkoutNotesApp`.
- Fazer todos os repositórios receberem `DatabaseProvider` explicitamente e
  remover o fallback temporário de `DatabaseProviderRegistry`.
- Dividir `WorkoutRepository` em repositórios de treino, entradas, séries e
  estatísticas; dividir `AnalyticsRepository` por assunto.
- Extrair `AiRoutineProposalRepository` e remover a persistência de propostas
  da fachada de banco e de serviços de orquestração.
- Reforçar a validação da restauração de backup antes de apagar dados, mantendo
  todo o fluxo em uma transação.

## Modelos e configuração

- Criar modelos imutáveis e conversores de linha para exercícios, categorias,
  treinos, entradas, séries, rotinas, medidas e relatórios.
- Substituir os `Map<String, dynamic>` usados internamente pela UI e por APIs
  de domínio; mantê-los somente em SQLite bruto, backup, HTTP e tools de IA.
- Introduzir `ExerciseType`, conversões centralizadas de booleanos SQLite e
  filtros/DTOs tipados para consultas e gráficos.
- Criar `AppSettings`, `AppPreferences` e controladores de preferências e
  configurações de treino; eliminar fontes duplicadas de tema, cor e locale.
- Remover leituras diretas de `SharedPreferences` de telas e serviços.

## Telas e componentes

- Extrair controladores, estado e widgets de `active_workout_screen.dart`,
  `routine_day_editor_screen.dart`, `settings_screen.dart` e
  `workout_home_screen.dart`.
- Criar o editor compartilhado de séries em `widgets/sets/` para treino ativo
  e rotina.
- Separar responsabilidades nas demais telas extensas: detalhe de treino,
  planejamento, edição, rotinas, medidas, progresso e gráficos.
- Criar componentes compartilhados apenas para repetições existentes:
  confirmação, feedback, estados de carregamento/erro, configurações, campos
  numéricos e formatadores de unidades.

## Erros, localização e IA

- Criar a hierarquia de exceções e `AppLogger`; substituir `catch (_) {}` por
  tratamento explícito, registro ou propagação adequada.
- Controlar operações concorrentes com estado `isBusy` e garantir descarte de
  timers, listeners e clientes conforme o ciclo de vida.
- Concluir a localização de textos visíveis, adotar `context.l10n` e
  centralizar formatação de datas, duração, volume, distância, ritmo e descanso.
- Dividir a orquestração de IA em controller, runner, builder de conversa e
  coordinator de propostas.
- Transformar as tools de IA em definições autocontidas e dividir os provedores
  de contexto, cache, parser, diff, snapshot e aplicação de propostas.
- Mover prompt e política fixa da IA para arquivos próprios.

## Documentação e validação final

- Atualizar README e o mapa completo de arquivos no `AGENTS.md` após a divisão
  definitiva dos módulos.
- Documentar a direção de dependências final, as fronteiras permitidas para
  mapas dinâmicos e a obrigatoriedade de transações para árvores de dados.
- Executar formatação, análise, testes existentes, build Android e os smoke
  checks de treino, rotina, configurações, backup e IA.
