# Revisão de qualidade, simplicidade e performance — Workout Notes

Data: 29/09/2026. Base analisada: commit `25b100c`, com árvore de trabalho inicialmente limpa.

Ambiente de validação: Flutter 3.47.5 stable, Dart 3.13.4 e Java 25.0.3 no Linux.

## Parecer

O projeto tem uma base adequada para continuar com a arquitetura atual: SQLite, repositórios, `setState`, `ChangeNotifier` e serviços nativos. Não há evidência de que trocar a gestão de estado, acrescentar um framework ou reescrever o app traria benefício proporcional ao custo.

Os maiores ganhos prováveis estão em reduzir trabalho repetido nos caminhos frequentes, controlar memória no backup, retirar I/O da thread principal Android e tornar os critérios de dados consistentes. A limpeza de código deve acompanhar essas mudanças, em alterações pequenas e verificáveis.

A análise estática está limpa, mas a suíte Flutter está falhando. Há também uma inconsistência concreta entre metas e análises: as metas de força podem contabilizar séries não concluídas e treinos ainda abertos ou planejados. Isso merece correção antes de melhorias cosméticas.

Não foi medido tempo de abertura, memória, fluidez ou bateria em aparelho físico. Portanto, este relatório não afirma que o app esteja lento nem promete percentuais de ganho. Ele distingue problemas reproduzidos, estruturas de custo identificadas e melhorias condicionadas a medição.

## Escopo e evidências

Foram inspecionados inicialização, navegação, banco e migrações, repositórios, dashboards, busca e refeições de nutrição, metas, histórico e imagens da IA, backup/restauração, tracking Android e CI. A revisão combinou leitura direcionada, busca de referências, grafo de imports e execução de verificações. Não é uma prova de ausência de outros defeitos em todos os fluxos.

Inventário no início da revisão:

| Área | Arquivos | Linhas |
|---|---:|---:|
| Dart em `lib/` | 489 | 208.436 |
| Dart sem os três arquivos gerados de localização | 486 | 163.868 |
| Kotlin em `android/app/src/main/` | 52 | 10.139 |
| Dart em `test/`, incluindo suporte e estudo manual | 166 | 41.436 |

Existem 160 arquivos `*_test.dart`. Quantidade de linhas é um indicador de superfície de manutenção, não uma medida de desempenho ou um motivo isolado para dividir arquivos. Os arquivos gerados de localização não são alvo de limpeza manual.

Verificações executadas:

| Verificação | Resultado |
|---|---|
| `flutter analyze --no-pub` | Sem problemas; 1,4 s reportados pelo comando |
| `flutter test --no-pub --reporter expanded` | 1.263 testes passaram; 1 falhou; aproximadamente 55 s |
| Teste de sono isolado | Mesma falha reproduzida |
| `cd android && ./gradlew test --offline` | Falhou em dois testes de `flutter_local_notifications` |
| `cd android && ./gradlew :app:testDebugUnitTest --offline` | Passou; XMLs registram 90 testes, zero falhas |
| Experimento SQLite em memória | Confirmou divergência de elegibilidade das metas e diferença entre `SCAN` e busca por índice |
| Grafo de imports a partir de `lib/main.dart` e busca de referências | Quatro widgets sem consumidores; um wrapper antigo consumido apenas por teste |

A falha Gradle geral foi `Unsupported class file major version 69`, em testes da dependência usando Robolectric/ASM. O Java local reportou versão 25; o workflow configura Java 17. Essa falha não comprova um defeito no código Kotlin do app. O comando específico do app passou no mesmo ambiente. O build acionado pelo Gradle também recalculou versões de dependências vinculadas ao SDK no `pubspec.lock`; essa alteração incidental foi revertida. Os resultados descrevem o ambiente local, não uma validação hermética do lockfile com a versão de Flutter da CI.

Não foram executados novo build release, análise de tamanho do APK, estudo manual de armazenamento de longo prazo, captura de traces, inspeção visual nova em emulador ou medições em aparelho físico. Nenhum banco pessoal foi aberto: o experimento SQLite usou dados sintéticos em memória.

## Decisões existentes que vale preservar

- `main.dart` já adia serviços que não são necessários ao primeiro frame.
- `MainShell` cria abas sob demanda e mantém estado em `IndexedStack`.
- `DatabaseHelper` compartilha o Future de abertura do SQLite, evitando conexões concorrentes.
- A busca local de alimentos já usa debounce; a busca remota é explícita e tem controle de frequência.
- Há agregações e carregamento em lote em rotinas, hidratação da busca de alimentos e resumos de sono. Essas soluções servem de modelo para outros caminhos.
- Rotas de corrida já têm armazenamento compacto, checksum, splits persistidos e manutenção em lotes limitados.
- O histórico de IA já tem paginação e persistência incremental. Não deve ser substituído por regravação integral.
- O diagnóstico de sono é opt-in e tem limites de retenção. Não há motivo para adicionar uma infraestrutura pesada de telemetria.
- O Android release já usa minificação e redução de recursos; a publicação gera AAB e APKs por ABI, com orçamento de 50 MiB por APK.
- A separação de treino ativo em tela, controller e ações de rotina e a aprovação explícita de propostas de IA devem permanecer.

## Critério de prioridade

**P1:** corrigir antes de uma rodada ampla de refatoração, por afetar confiabilidade, validação ou um caminho com risco relevante de custo. **P2:** melhoria concreta a executar em seguida. **P3:** otimização condicional ao crescimento ou profiling.

“Confirmado” significa observado no código ou reproduzido no comando descrito. “Risco” significa que o mecanismo existe, mas seu impacto em produção ainda precisa ser medido.

## Achados prioritários

### A01 — P1 — Teste Flutter desatualizado bloqueia a validação

**Confirmado.** [sleep_monitor_alarm_widget_test.dart](../test/sleep_monitor_alarm_widget_test.dart), linha 116, espera `Next alarm`. A tela usa `sleepMonitorReadyWakeTime`, cujo inglês é `Planned wake-up`, em [sleep_monitor_screen.dart](../lib/screens/workout/sleep_monitor_screen.dart), linha 285, e [app_en.arb](../lib/l10n/app_en.arb), linha 88.

O relatório anterior de UI/UX explica que a troca foi intencional: um horário planejado não deve sugerir que o alarme já foi configurado. Atualizar o contrato do teste e cobrir os estados antes/depois da ativação. Não restaurar o texto antigo apenas para passar. A execução isolada elimina a hipótese de ser somente uma falha de concorrência da suíte.

### A02 — P1 — Metas e análises contam conjuntos diferentes de treinos

**Confirmado por leitura e experimento SQL.** [goal_repository.dart](../lib/repositories/goal_repository.dart), a partir da linha 383, calcula volume sem exigir `s.is_complete = 1` nem `w.end_time IS NOT NULL`. Outros ramos e consultas de contribuições também deixam de aplicar esses filtros. [analytics_repository.dart](../lib/repositories/analytics_repository.dart), linhas 13–14, exige séries concluídas, sem aquecimento, e treinos encerrados.

Com um treino aberto e uma série desmarcada de 100 kg × 10, o SQL da meta retorna **1.000**, enquanto os critérios das análises retornam **0**. O teste atual de integração de metas cobre atividades cardio concluídas, mas não esse caso de força.

Definir explicitamente os critérios de realizado, planejado e em andamento; alinhar metas, contribuições e histórico. Usar um helper pequeno ou constantes de domínio onde isso eliminar divergência, sem criar um gerador genérico de SQL. Cobrir treino planejado, aberto, série desmarcada, aquecimento e duas sessões no mesmo dia. A regra de meta por dias também deve ficar explícita.

### A03 — P1 — Tracking de corrida faz I/O síncrono na thread principal Android

**Estrutura confirmada; impacto em aparelho não medido.** [RunTrackingService.kt](../android/app/src/main/kotlin/com/workoutnotes/workout_notes/run/RunTrackingService.kt), linha 766, registra GPS com `Looper.getMainLooper()`. `acceptPoint`, linha 900, chama `spool.appendPoint` e `persistLiveTotals`. O ticker na thread principal também persiste totais a cada cinco segundos. [RunActivitySpool.kt](../android/app/src/main/kotlin/com/workoutnotes/workout_notes/run/RunActivitySpool.kt), linhas 26–36, usa `writeText`, `appendText` e renomeação síncrona.

Uma sessão longa, armazenamento lento ou concorrência com outras operações pode atrasar callbacks e interação. O bridge também lê spools completos diretamente em chamadas de canal.

Usar um executor sequencial dedicado para persistência e leitura pesada. Preservar ordem de pontos, escrita atômica, flush em pausa/parada e recuperação após encerramento do processo. A frequência de checkpoint deve continuar sendo uma decisão de durabilidade: não aumentar o intervalo arbitrariamente para economizar I/O. Validar com StrictMode em desenvolvimento e traces; a documentação Android recomenda essa ferramenta para identificar I/O na thread principal. [Referência Android](https://developer.android.com/reference/android/os/StrictMode).

### A04 — P1 — Backup pode criar picos de memória e bloquear o isolate da interface

**Estrutura confirmada; pico real não medido.** [export_service.dart](../lib/services/export_service.dart), linha 160, monta todo o backup, converte para JSON indentado e depois UTF-8. A restauração faz `jsonDecode` integral, linha 248. [backup_media_service.dart](../lib/services/backup_media_service.dart), linhas 21–43 e 70–132, usa base64 síncrono e mantém todas as mídias decodificadas antes de gravá-las. Os limites permitem até 50 MiB por arquivo e 500 MiB de mídia total.

Bytes, base64, JSON, objetos decodificados e saída podem coexistir. Um limite de 500 MiB de mídia não é um limite de 500 MiB de RAM. As checagens de tamanho na restauração acontecem depois de decodificar o base64.

Separar duas correções: processamento CPU fora do isolate da UI, seguindo o precedente de [base64_encoder.dart](../lib/utils/base64_encoder.dart), e redução do volume simultâneo em memória. Processar mídias por arquivo, validar tamanho codificado antes da decodificação e considerar escrita incremental. Um isolate sozinho não resolve a memória e pode introduzir cópias. Manter leitura dos backups existentes; uma mudança de formato exige versionamento e testes. JSON compacto pode reduzir saída, mas não substitui o controle de memória.

### A05 — P1 — Adicionar refeição salva não é uma operação atômica

**Confirmado por fluxo de código; falha intermediária não injetada nesta revisão.** [nutrition_repository.dart](../lib/repositories/nutrition_repository.dart), linha 1384, cria a seção e adiciona ingredientes em sequência. Cada `addMealLogItem` tem sua própria transação; não existe uma transação externa cobrindo a ação inteira.

Se uma gravação falhar no meio, parte da refeição pode permanecer salva. Uma nova tentativa pode repetir os ingredientes já adicionados. A replicação de dias, no mesmo repositório, já possui transação única e executor explícito.

Resolver alimentos/conversões em lote e aplicar os itens válidos em uma transação. Preservar o retorno de itens adicionados/ignorados e distinguir alimento ausente de falha de gravação. Testar rollback após falha no segundo ingrediente e resultado de uma nova tentativa.

### A06 — P1 — Migrações 53, 54 e 55 não têm testes explícitos de upgrade

**Lacuna confirmada na busca dos testes.** A versão atual é 55. [database_migrations_wellness.dart](../lib/database/migrations/database_migrations_wellness.dart), linhas 588, 597 e 606, adiciona equipamento/voltas, `routine_day_id` e medicação. Existem testes dedicados até v52, mas não chamadas explícitas exercitando as transições v53–v55. Testes de repositório e schemas de suporte não equivalem a testar o upgrade de um banco existente.

Adicionar os testes previstos em `AGENTS.md`: criação nova, upgrade, reexecução idempotente, preservação de dados, índices e cascatas. Incluir um salto de uma versão anterior para 55. Não apagar migrações antigas durante limpeza.

### A07 — P1 — CI valida tarde e deixa mudanças de testes sem execução automática

**Confirmado.** [release-android.yml](../.github/workflows/release-android.yml), linhas 3–21, dispara em push para `main` com filtro de caminhos, sem `test/**` e `tool/**`. Não há workflow de validação de PR entre os workflows existentes, e os testes Kotlin do app não são executados.

Criar validação de PR/push que cubra Dart, testes e Android, sem publicar release. Executar `:app:testDebugUnitTest` com Java 17; usar um comando dirigido ao app evita transformar testes internos de todos os plugins no contrato de qualidade do projeto. Continuar analisando e testando no release. Fixar uma versão de Flutter suportada para tornar o baseline reproduzível e atualizar o pin em mudanças explícitas.

## Custos nos caminhos de uso frequente

### A08 — P2 — Nutrição ainda possui consultas por refeição e por item

**Confirmado.** `getDayMeals`, linha 981, faz uma consulta de logs e uma consulta de itens para cada refeição. `getSavedMeals`, linha 1363, chama `_savedMealWithItems` para cada modelo; cada chamada consulta itens e recalcula totais com outras leituras. `addSavedMealToDate` busca detalhes de cada alimento, e `_detailsFor`, linha 1686, consulta porções por variante.

O custo cresce com o número de refeições/ingredientes. Usar duas consultas para o diário, agrupando itens por `meal_log_id`. Para refeições salvas, carregar itens, variantes e porções em lote e reutilizar o cálculo existente. `_hydrateResults`, linha 2017, já mostra o padrão adequado. Preservar ordenação, `null` nutricional, porções e itens removidos. Medir quantidade de queries; apenas envolver tudo em `Future.wait` não elimina os round trips SQLite.

### A09 — P2 — A tela inicial faz várias leituras sequenciais e carrega histórico detalhado

**Confirmado; impacto não medido.** [workout_home_screen.dart](../lib/screens/workout/workout_home_screen.dart), linha 132, espera atividades ativas, stamps, até um ano de atividades cardio sem limite de quantidade, snapshots de força/corrida, treinos recentes e categorias. Parte das leituras é independente; o usuário precisa primeiro de poucas informações acionáveis.

Separar dados essenciais de cartões complementares, reutilizar dados já obtidos no mesmo carregamento e usar projeções leves para marcas/estatísticas. Revisar dependências antes de paralelizar: SQLite continua sendo compartilhado. Evitar cache global por padrão; se necessário, usar cache local ao carregamento com invalidação nas mutações. Usar token de geração ou Future compartilhado para impedir que um reload antigo sobrescreva o novo. Metas também executam uma consulta por objetivo e sete períodos no detalhe; só agregar esse caminho se o profiling mostrar custo relevante.

### A10 — P2 — Inicialização de serviços repete reconciliação e manutenção

**Confirmado.** `RunTrackingService.initialize` é chamado pelo `initState` da home e por `main.dart`; telas também o chamam. `_initialized` evita duplicar a assinatura do canal, mas não evita repetir capacidades, estado, recuperação e `_maintainRouteStorage`. O monitor de sono tem padrão semelhante. A home inicia a corrida antes da rotina de inicialização adiada terminar, portanto a ordem comentada em `main.dart` não coordena todos os chamadores.

Compartilhar o Future de inicialização em andamento e separar assinatura única, atualização leve, reconciliação e manutenção. Garantir novas tentativas após erro e refresh no retorno ao app. Agendar manutenção limitada sem competir com o primeiro uso. Considerar carregar o histórico de IA quando o usuário abrir o recurso, mantendo recuperação durável de corrida, sono e alarmes independente dessa decisão.

### A11 — P2 — Eventos e timers reconstruem a home inteira, inclusive quando oculta

**Confirmado.** [workout_home_screen.dart](../lib/screens/workout/workout_home_screen.dart), linhas 95–115, executa `setState` da tela inteira por evento de corrida/bike e a cada segundo do treino ativo. O timer respeita a aba selecionada, mas os listeners de corrida/bike continuam reconstruindo uma home montada no `IndexedStack`. Abrir uma rota sobre a home também não cancela esses listeners.

Isolar relógio/banner em widgets pequenos com listeners próprios e suspender atualização puramente visual quando a tela não está visível. Manter tracking, voz e persistência ativos. Rever animações contínuas nessa mesma região. Medir rebuilds antes/depois; não substituir o `IndexedStack` por uma solução que perca estado. A recomendação de localizar rebuilds está nas [boas práticas Flutter](https://docs.flutter.dev/perf/best-practices).

### A12 — P2 — Falhas de carregamento podem parecer ausência de dados

**Confirmado.** As homes de treino e sono encerram loading em `catch` sem feedback. A home de nutrição também mantém aparência de carregamento concluído após erro. `GoalsSection` substitui falhas por progresso vazio. A raiz de carregamento de `periodization_home_screen.dart`, linha 96, tem awaits fora de um tratamento global de erro. A persistência de chat captura falhas silenciosamente.

Adotar estados claros de carregando/dados/vazio/erro usando os padrões atuais. Preservar dados anteriores em refresh malsucedido, mostrar erro discreto com repetir e distinguir “sem registros” de “não foi possível ler”. Em persistência do chat, indicar que a conversa não foi salva e permitir retry. Não transformar todos os `catch` em alertas: limpeza opcional e fallback de plugin ausente têm necessidades diferentes.

### A13 — P2 — Restauração inválida pode deixar diretório de mídia órfão

**Risco identificado por fluxo de controle; não reproduzido em teste nesta revisão.** `materializeForRestore`, em [backup_media_service.dart](../lib/services/backup_media_service.dart), grava as mídias e depois chama `_rewriteMediaReferences`, fora do bloco que descarta o diretório em caso de erro de escrita. Referência `backup-media://` inexistente pode lançar após os arquivos terem sido criados. O chamador ainda não recebeu o diretório para descartá-lo.

Validar referências antes de gravar e cobrir toda a materialização com cleanup em falha. Testar um manifest válido com referência de foto inexistente e confirmar que não restam arquivos, nem alterações de preferências/banco. Essa correção reduz acúmulo de armazenamento em tentativas malsucedidas.

## Limpeza e manutenção

### A14 — P2 — Quatro widgets não têm consumidores

**Confirmado no checkout analisado.** O grafo de imports e as buscas em `lib/` e `test/` não encontraram import ou uso externo dos seguintes arquivos:

| Arquivo | Linhas |
|---|---:|
| [collapsible_section.dart](../lib/widgets/collapsible_section.dart) | 114 |
| [workout_heatmap.dart](../lib/widgets/workout_heatmap.dart) | 209 |
| [nutrition_charts.dart](../lib/widgets/nutrition/nutrition_charts.dart) | 556 |
| [stat_tile.dart](../lib/widgets/workout/stat_tile.dart) | 59 |
| **Total** | **938** |

Remover em uma alteração isolada, verificar referências novamente e executar análise/testes. O ganho esperado é clareza e menor superfície de manutenção. Não contabilizar essas 938 linhas como redução garantida no APK: ausência de imports e eliminação de código no build já podem evitar que elas sejam incluídas.

`progress_screen.dart` também não é alcançável pelo app, mas é um wrapper deliberado de compatibilidade com um teste próprio. Só retirar esse contrato e o teste juntos após confirmar que não existe fluxo suportado que precise dele.

### A15 — P2 — Camada de compatibilidade e APIs sem uso prolongam complexidade

**Confirmado parcialmente; cada remoção requer verificação individual.** [database_helper.dart](../lib/database/database_helper.dart) tem 903 linhas e muitas delegações para repositórios. Algumas APIs aparecem apenas na declaração: exemplos são `getSleepDashboardStats`, `getDailyNutritionSummary` e `getAiChatThreads`. Há métodos de domínio sem chamador em produção, como `getCardioMonthlyDistance`, `getPaceTrend`, `getCardioPRs` e `getMonthlyCardioStats`. Outros sobrevivem em testes ou no estudo manual de armazenamento.

Migrar consumidores para o repositório ao tocar cada feature e retirar wrappers sem consumidores. Separar métodos usados só em estudo/teste de contratos de produção antes de excluir. Não otimizar os loops de `getWeeklyVolume`/`getMonthlyVolume` como se fossem um gargalo atual da UI: não foi encontrado consumidor de produção além das delegações. Fazer inventário por símbolo incluindo testes, ferramentas e tear-offs; análise de imports não detecta todo dead code público.

### A16 — P2 — Alguns arquivos concentram responsabilidades demais

**Confirmado como custo de manutenção; não implica custo de runtime.** Exemplos: `run_plan_composer.dart` (3.251 linhas), `periodization_repository.dart` (2.622), `nutrition_progress_screen.dart` (2.546), `nutrition_repository.dart` (2.396), `ai_tool_registry.dart` (2.186), `sleep_monitor_screen.dart` (1.773), `nutrition_settings_screen.dart` (1.666).

Dividir pela responsabilidade que muda: cálculos versus carregamento versus apresentação; cache de alimentos versus diário versus refeições salvas; composição de plano versus política de progressão. Há telas grandes que já contêm controllers/widgets privados, como o editor de fase: preservar esse desenho, extraindo apenas fronteiras úteis. Não adotar um teto rígido de linhas nem criar dezenas de arquivos triviais. Manter catálogo, execução, labels e testes da IA sincronizados.

### A17 — P2 — Mapas dinâmicos ainda atravessam limites de domínio e UI

**Confirmado.** Workouts, rotinas e parte das análises retornam `Map<String, dynamic>`; consumers dependem de nomes de colunas e casts. Áreas mais novas já usam modelos tipados, oferecendo um padrão local.

Introduzir modelos pequenos nos retornos alterados durante A02/A08/A09, mantendo mapas no limite SQLite/JSON. Remover campos/chaves redundantes ao tipar esses caminhos. Não converter todos os repositórios de uma vez e não criar DTO separado de um modelo já apropriado.

## Melhorias adicionais de leveza e usabilidade

### A18 — P2 — Filtros de datas de corrida dificultam uso dos índices existentes

**Confirmado por experimento de plano de consulta.** Metas usam `substr(ra.started_at, 1, 10)` no `WHERE`; periodização usa `date(started_at)`. O schema tem índices sobre `started_at` e `(activity_type, started_at)`, não sobre essas expressões.

Em uma tabela sintética com o índice atual, o filtro `substr(...)` resultou em `SCAN run_activities`; o filtro `started_at >= ? AND started_at < ?` resultou em `SEARCH ... USING INDEX`. Isso evidencia a possibilidade de melhorar o plano, não um tempo de execução medido no app. [Planejamento SQLite](https://www.sqlite.org/queryplanner.html) e [índices de expressão](https://www.sqlite.org/expridx.html).

Preferir intervalo de timestamps quando semanticamente equivalente. Antes disso, alinhar dia local, UTC e representação dos timestamps: uma troca textual ingênua pode alterar o dia contabilizado. Testar registros perto da meia-noite. Só acrescentar índice composto/expressão após `EXPLAIN QUERY PLAN` e benchmark demonstrarem necessidade; cada índice também custa escrita e espaço.

### A19 — P2 — Miniaturas da IA não limitam resolução de decodificação

**Estrutura confirmada; memória não medida.** [ai_message_bubble.dart](../lib/widgets/ai/ai_message_bubble.dart), linha 193, apresenta imagens de 104–260 px com `Image.file` sem `cacheWidth/cacheHeight`. [ai_chat_input_bar.dart](../lib/widgets/ai/ai_chat_input_bar.dart), linha 246, faz o mesmo em miniaturas de 64 px. O picker já reduz as imagens para até 1.600 px: preservar essa boa decisão.

Decodificar miniaturas na resolução necessária, considerando densidade de pixels, e manter imagem maior para a visualização com zoom. Verificar memória num histórico com várias fotos. Não reduzir indiscriminadamente a imagem enviada para análise de rótulo, pois isso pode comprometer legibilidade.

### A20 — P2 — Clientes HTTP não têm contrato claro de encerramento

**Confirmado como lacuna de ownership; vazamento não medido.** `AiService` e `OpenFoodFactsGateway` criam `http.Client`, mas não expõem `close/dispose`. Homes e detalhes de nutrição criam gateways próprios; o editor de refeição salva cria outro ao abrir a busca. O contrato `NutritionGateway` não define ciclo de vida.

Definir quem possui o client: compartilhado por serviço duradouro ou local à tela. Fechar apenas clients criados pela própria instância, sem fechar fakes/clients injetados de outro proprietário. Não criar um container de DI para resolver isso. Cobrir abertura/fechamento repetido e evitar fechar um gateway enquanto uma rota filha o utiliza.

### A21 — P2 — Busca do histórico de IA só procura conversas já carregadas

**Confirmado.** [ai_chat_threads.dart](../lib/state/ai_chat_threads.dart), linhas 5–22, carrega inicialmente 100 conversas. [ai_chat_history_screen.dart](../lib/screens/workout/ai_chat_history_screen.dart), linha 325, filtra apenas a lista em memória. Há botão de carregar mais, mas uma conversa antiga não é encontrada até que suas páginas sejam carregadas. O contador também usa o tamanho da lista carregada. A lista constrói todos os cards das páginas carregadas com `ListView(children: ...)`.

Buscar no SQLite com paginação para a consulta ativa, ou informar explicitamente a abrangência limitada até implementar a busca completa. Usar lista/slivers sob demanda ao carregar muitas páginas. Preservar pinned, seleção e estado; não desfazer a paginação existente. Testar localizar uma conversa fora da primeira página.

### A22 — P2 — Parte do conteúdo visível ainda força português no locale inglês

**Confirmado no código.** [ai_chat_persistence.dart](../lib/state/ai_chat_persistence.dart), linha 113, instrui o resumo após aplicar proposta a responder em português brasileiro incondicionalmente. Os títulos genéricos persistidos usam `Nova conversa`/`Conversa`. `ExportService.getBackupsPathDescription` retorna `(indisponível)` como fallback, e erros de formato do backup contêm texto português.

Passar a preferência de idioma pelos caminhos existentes e usar códigos de erro traduzidos pela UI. Traduzir títulos genéricos na apresentação sem mudar títulos escritos pelo usuário. Atualizar EN/PT e testes dos fluxos efetivamente alterados. Não traduzir schemas, identificadores ou conteúdo pessoal, nem ampliar `TextSanitizer`.

### A23 — P3 — Busca local de alimentos usa scans por substring

**Confirmado como estrutura; gargalo não medido.** `searchLocalFoods`, em [nutrition_repository.dart](../lib/repositories/nutrition_repository.dart), linha 42, usa `%termo%`, `LOWER(brand)` e ranking por expressão. O limite de 30 resultados não garante leitura de somente 30 linhas. Os índices convencionais atuais não resolvem toda essa busca por substring.

O debounce e a hidratação em lote já reduzem custo. Medir com biblioteca grande antes de mudar. Se necessário, considerar busca por prefixo com fallback ou índice de pesquisa apropriado, preservando a semântica esperada e a compatibilidade SQLite Android. FTS não deve ser acrescentado sem comprovar o benefício e decidir como manter seu índice sincronizado.

### A24 — P1, como pré-requisito — Falta baseline reproduzível de performance do app

**Lacuna na validação atual.** Há [performance_optimizations_test.dart](../test/performance_optimizations_test.dart) e [long_term_storage_study.dart](../test/long_term_storage_study.dart). O primeiro verifica comportamento; o segundo é manual, tem timeout de 45 minutos e mede banco/exportação em ambiente de teste. São úteis, mas não medem frames, RAM ou energia do app no Android. Não foi localizado diretório `integration_test` nesta revisão.

Usar esses recursos existentes para registrar banco pequeno e grande e complementar com aparelho físico em profile. A documentação Flutter recomenda esse ambiente para avaliar desempenho. [Profiling Flutter](https://docs.flutter.dev/perf/ui-performance). Registrar baseline antes de A03/A04/A08/A09/A11/A19/A23 e comparar no mesmo aparelho, dados e versão.

## O que não recomendo nesta rodada

Não recomendo migração para Riverpod/Bloc, reescrita do app, substituição de SQLite, abstração genérica de todos os repositórios ou cache global sem invalidação. Também não recomendo remover features/dependências utilizadas para baixar o número de pacotes: todas as dependências diretas declaradas tiveram imports encontrados em fontes, testes ou ferramentas.

Não remover serviços Android ou adaptar a coleta de GPS/sono apenas para diminuir consumo sem validar precisão e recuperação. Não eliminar migrations, dados históricos ou compatibilidade de backups como se fossem dead code. A pasta local `build/` tinha 2,8 GiB, mas isso é espaço de desenvolvimento, não o tamanho instalado do app.

Não alterar as decisões deliberadas do wire de IA: catálogo completo por rodada, prefixo estático e truncamento somente na transmissão. Não acrescentar streaming nem rastreamento de custo/tokens como parte de limpeza.

O algoritmo legado `_findOnset` de sono possui loops aninhados, mas o caminho bedside atual evita essa busca. Otimizá-lo sem confirmar que participa de um custo real teria prioridade menor que os itens acima. Da mesma forma, comparar semanas iniciadas no domingo na nutrição e na segunda em outros domínios é uma revisão de convenção/UX, não um bug presumido.

## Ordem recomendada

1. Restabelecer validação, cobrir migrações e medir baseline.
2. Corrigir elegibilidade de metas, atomicidade de refeição e cleanup da restauração.
3. Tratar I/O Android, memória de backup e queries da nutrição.
4. Reduzir inicialização repetida e rebuilds; melhorar feedback e busca.
5. Remover código sem uso e simplificar as fronteiras efetivamente tocadas.
6. Executar otimizações condicionais somente quando a medição justificar.

O [plano de correção](code_quality_remediation_plan.md) relaciona todos os 24 achados a entregas, dependências e critérios de aceite. Esta revisão adicionou somente documentação; não aplicou as correções.
