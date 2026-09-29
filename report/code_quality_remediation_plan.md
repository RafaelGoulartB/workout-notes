# Plano de correção — qualidade e leveza do Workout Notes

Base: [revisão de 29/09/2026](code_quality_review_2026-09-29.md), commit `25b100c`.

Objetivo: reduzir custo nos fluxos frequentes, manter dados confiáveis e tornar o código mais simples sem trocar a arquitetura ou perder recursos. Este documento é um plano; nenhuma das correções abaixo foi implementada nesta revisão.

## Estratégia de execução

Trabalhar em mudanças pequenas, com um problema concreto por entrega. Corrigir comportamento e proteção contra regressão antes de extrair grandes blocos de código. Aproveitar cada alteração para reduzir mapas dinâmicos, wrappers e duplicação na fronteira envolvida.

Manter `setState`, `ChangeNotifier`, repositórios e SQLite. Não introduzir pacote de estado, DI, cache persistente, índice extra ou novo formato de backup sem uma necessidade demonstrada. Alterações de schema exigem criação nova, migration, incremento de versão e teste de upgrade conforme `AGENTS.md`.

## Sequência de entregas

Estimativas em dias de trabalho de uma pessoa familiarizada com o projeto. São faixas de planejamento, sem prazo assumido; profiling, dispositivo disponível e falhas descobertas podem mudar o esforço. Não incluem uma reescrita dos arquivos grandes.

| Entrega | Achados | Esforço inicial | Dependência |
|---|---|---:|---|
| 1. Validação e baseline | A01, A06, A07, A24 | 2–4 dias | Nenhuma |
| 2. Consistência e integridade | A02, A05, A13 | 2–4 dias | 1 |
| 3. Leituras em lote e home | A08, A09, A18 | 2–4 dias | 1; A02 antes de A18 nas metas |
| 4. Persistência Android | A03 | 2–4 dias | 1; aparelho para validação |
| 5. Memória de backup e imagens | A04, A19 | 2–4 dias | 1; A13 antes de alterar restauração |
| 6. Ciclo de vida e feedback | A10, A11, A12, A20 | 2–4 dias | 1; coordenar com 3 e 4 |
| 7. Histórico e idiomas | A21, A22 | 1–3 dias | 1 |
| 8. Limpeza e simplificação dirigida | A14, A15, A16, A17 | 2–5 dias | Inventário em 1; modelos podem entrar em 2/3 |
| 9. Busca local, se necessária | A23 | 1–3 dias de investigação/primeira solução | Benchmark da entrega 3 |

As entregas são limites de revisão, não justificativa para esperar que uma etapa inteira termine antes de corrigir um defeito pequeno. A remoção dos quatro widgets pode ocorrer logo após restabelecer a validação. A investigação de performance começa na entrega 1 e acompanha as demais.

## 1. Restabelecer validação e registrar o baseline

- [ ] **A01:** atualizar o teste para `Planned wake-up`/localização equivalente e verificar a distinção entre horário planejado e alarme ativo.
- [ ] **A06:** adicionar testes v53, v54 e v55 de criação/upgrade, repetição e preservação de dados; testar salto de versão para 55.
- [ ] **A07:** adicionar workflow de validação de PR, com caminhos de testes incluídos, Flutter pinado e Java 17. Rodar análise, testes Flutter e `:app:testDebugUnitTest`; deixar publicação no workflow de release.
- [ ] **A24:** registrar cenários pequeno/grande e medições de app/banco. Reutilizar o estudo de armazenamento em job manual/agendado, após avaliar seu custo; ele não precisa executar a cada PR.

Aceite: suíte Flutter inteira passa; 90 testes Kotlin do app continuam passando ou a nova contagem é registrada; cada migração tem cobertura explícita. Uma alteração somente em `test/` dispara validação. Existe um registro de aparelho, modo de build, versão, dados e métricas antes das otimizações.

## 2. Corrigir consistência e integridade

- [ ] **A02:** especificar elegibilidade de séries/treinos para metas e contribuições. Compartilhar uma regra pequena onde necessário, mantendo distinção entre séries, sessões e dias.
- [ ] **A05:** carregar ingredientes/conversões e gravar refeição salva em transação única por executor explícito. Não chamar um método que abre outra transação de dentro da transação externa.
- [ ] **A13:** validar referências de mídia antes da escrita e descartar materialização em qualquer falha posterior.

Aceite: treino planejado/aberto, série desmarcada e aquecimento não inflacionam volume realizado; duas sessões no mesmo dia seguem a regra de dias definida. Falha no segundo ingrediente deixa zero ingredientes novos. Alimentos indisponíveis preservam feedback de ignorados. Manifest inválido não deixa diretório órfão nem muda banco/preferências.

## 3. Reduzir leituras de banco nos fluxos frequentes

- [ ] **A08:** implementar carregamento em lote para diário, refeições salvas e detalhes usados ao registrar ingredientes. Reutilizar os cálculos/hidratação existentes.
- [ ] **A09:** mapear dependências do dashboard, retornar primeiro os dados necessários à ação principal e usar projeções leves para histórico semanal/anual. Compartilhar dados já lidos no mesmo carregamento e impedir resultado obsoleto de reload.
- [ ] **A18:** documentar timestamps/dia local, executar `EXPLAIN QUERY PLAN` e trocar filtros de expressão por intervalos apenas quando equivalentes. Avaliar índices adicionais por evidência.
- [ ] Medir também o carregamento de sugestões em `FoodSearchScreen`: hoje inclui todas as refeições salvas, mesmo quando o usuário inicia uma busca de alimento. Decidir carregamento sob demanda depois de resolver A08.

Aceite: `getDayMeals` usa duas consultas independentemente do número de refeições; refeições salvas têm quantidade de queries limitada por lotes, sem consulta por modelo/ingrediente. Ordem, totais e `null` não mudam. Dashboard não carrega detalhes de rota para marcar dias. Filtros de datas preservam resultados na meia-noite local/UTC e têm plano registrado. Quantidade de consultas e latência são comparadas ao baseline.

## 4. Retirar persistência pesada da thread principal Android

- [ ] **A03:** definir fila sequencial para append de pontos, checkpoints, leitura e remoção de spool.
- [ ] Tornar o ciclo de encerramento explícito: enfileirar dados pendentes, confirmar flush e só então reportar conclusão durável.
- [ ] Manter atualizações de interface/canal na thread apropriada e separar I/O da geração de voz e totais.
- [ ] Instrumentar StrictMode apenas em desenvolvimento e executar corrida longa com tela ligada/desligada, pausa, retomada e encerramento de processo.

Aceite: traces não mostram as operações de arquivo do spool no callback principal de GPS. IDs e sequência de pontos permanecem estáveis; chamadas concorrentes de stop/pause não perdem escrita. Recuperação mantém o limite de perda de checkpoint atual ou um limite explicitamente aprovado como regra do produto. Testes nativos e importação Dart continuam passando.

## 5. Controlar memória de backup e imagens

- [ ] **A04:** medir separadamente coleta SQL, mídia, encode/decode e gravação. Retirar CPU pesado da UI sem copiar o dataset inteiro desnecessariamente.
- [ ] Processar mídia individualmente, validar limites antes de decodificar e reduzir representações simultâneas. Usar JSON compacto se não houver requisito de saída indentada.
- [ ] Manter formato atual legível; só propor arquivo/container novo se a solução incremental não atender ao orçamento de memória. Nesse caso, versionar e preservar importação antiga.
- [ ] **A19:** limitar resolução de miniaturas ao tamanho físico necessário, preservando imagem maior no zoom/análise.

Aceite: backup e restauração completos mantêm contagens, relações e referências de mídia. Cancelamento/erro deixa o banco íntegro e sem arquivos temporários abandonados. Medir pico de RAM com backup pequeno e grande; demonstrar redução e manter interface responsiva. Miniaturas reduzem memória decodificada sem prejudicar zoom nem leitura de rótulo.

## 6. Simplificar ciclo de vida e tornar erros visíveis

- [ ] **A10:** compartilhar inicialização em andamento; separar inicialização, refresh/reconcile e manutenção. Não duplicar assinaturas nem impedir retry após falha.
- [ ] **A11:** mover listeners/timers visuais para banners/relógios e respeitar visibilidade de aba/rota. Preservar atividade nativa em segundo plano.
- [ ] **A12:** introduzir feedback localizado de erro/repetir nos carregamentos essenciais. Preservar dados anteriores no refresh; erro não se transforma em progresso zero.
- [ ] **A20:** definir ownership de client HTTP e encerramento coerente com rotas filhas, singletons e injeção de fakes.

Aceite: chamadas concorrentes de initialize compartilham o trabalho; retomada atualiza o estado e consegue recuperar sessões. Mudança de aba não continua reconstruindo toda a home por tick. App com serviço ativo continua rastreando com tela/aba oculta. Erro de banco exibe repetir, e erro de persistência de chat indica estado não salvo. Clientes locais são encerrados quando seu proprietário termina, sem fechar clientes compartilhados ou interromper rota filha.

## 7. Melhorar busca de histórico e suporte aos idiomas

- [ ] **A21:** pesquisar conversas no banco com paginação da consulta, incluindo fora da primeira página. Se a solução for adiada, explicitar o limite de busca. Corrigir contador ou indicar que conta itens carregados.
- [ ] Renderizar cards do histórico sob demanda, preservando grupos e conversas fixadas.
- [ ] **A22:** respeitar o locale no resumo de proposta aplicada; traduzir fallbacks/erros na apresentação, mantendo conteúdo do usuário intacto.

Aceite: conversa antiga é encontrável com mais de 100 threads; paginação não duplica/perde conversas ao filtrar ou fixar. EN/PT cobrem erro de backup, título genérico e resumo após proposta. Aprovação de IA e catálogo completo de ferramentas permanecem com os mesmos contratos.

## 8. Remover código sem uso e simplificar as fronteiras alteradas

- [ ] **A14:** remover os quatro widgets sem consumidores, em alteração isolada. Decidir separadamente sobre `ProgressScreen` e seu teste de compatibilidade.
- [ ] **A15:** inventariar consumidores de wrappers/métodos em app, testes e `tool/`; migrar ao repositório e remover somente contratos realmente dispensáveis.
- [ ] **A16:** extrair responsabilidades dos maiores arquivos conforme necessidade concreta. Começar por queries/conversões e cálculos do relatório nutricional; preservar controllers e widgets privados já existentes.
- [ ] **A17:** tipar os retornos de domínio envolvidos nas entregas anteriores e remover casts/chaves redundantes desses caminhos.

Aceite: referências antigas deixam de existir; análise e testes passam. Diff não inclui limpeza de gerados, migrations ou arquivos não relacionados. Extrações deixam negócio testável sem `BuildContext`, com widgets focados em apresentação. Não há camada adicional sem consumidor nem API duplicada mantida apenas por conveniência. Redução de linhas é registrada como manutenção; redução de APK só é alegada se medida.

## 9. Otimizar busca local somente se o banco grande justificar

- [ ] **A23:** medir digitação e pesquisa com 1 mil, 10 mil e um volume maior plausível de alimentos locais, usando dados sintéticos.
- [ ] Comparar comportamento atual com prefixo/fallback ou pesquisa indexada. Registrar semântica e custo de manutenção do índice.

Aceite: manter acentos/normalização, marca, relevância e os resultados esperados pelo usuário. Latência melhora no cenário que motivou a mudança; cadastro/atualização e tamanho do banco não regridem sem justificativa. Se o baseline já atender ao orçamento, registrar o achado como monitorado e manter a solução atual.

## Protocolo de medição

Usar um Android físico representativo do aparelho mais modesto suportado, com `flutter run --profile`. Registrar também um aparelho intermediário se disponível. Emulador/debug serve para reproduzir funcionalidade, não para concluir desempenho de produção. Usar mesma versão, dados e condições nas comparações; executar pelo menos cinco repetições para fluxos curtos e registrar mediana e pior resultado.

| Cenário | Medição |
|---|---|
| Abertura fria/quente e primeira home | Primeiro frame, momento em que a ação principal pode ser usada, duração dos carregamentos |
| Alternar abas e registrar série | Tempo de resposta, rebuilds e frames fora do orçamento |
| Diário, biblioteca e refeição salva | Quantidade de queries, latência por etapa e resultado funcional |
| Histórico com anos de dados | RAM, páginas carregadas, consultas e fluidez de scroll |
| Corrida de 30–60 minutos | I/O na thread principal, latência de eventos, RAM e recuperação |
| Sono durante uma noite | Consumo/atividade de CPU e recuperação, preservando inferência e alarme |
| Exportar/restaurar com mídia | Pico de RAM, tempo total, responsividade e integridade |
| Release arm64 | Tamanho do APK/AAB e diferença por pacote/recurso |

Metas iniciais de engenharia, a calibrar após o baseline:

- Frames dentro do orçamento da tela: aproximadamente 16,7 ms em 60 Hz e 8,3 ms em 120 Hz, acompanhando também a proporção de frames lentos.
- Feedback visual de ações comuns perceptível em até 100 ms, separando esse feedback da conclusão da operação.
- Diário/busca local com alvo inicial de até 200 ms no aparelho escolhido e base representativa; anotar exceções e custo de rede separadamente.
- Quantidade de queries não cresce por item nos caminhos convertidos em carregamento em lote.
- RAM estabiliza ao repetir abrir/fechar os mesmos fluxos; diferenciar cache esperado de retenção crescente.
- APK por ABI permanece dentro do orçamento atual de 50 MiB, com comparação por release.

Esses números são alvos propostos, não resultados atuais nem garantias. Não fixar um teto universal de RAM ou bateria sem medir aparelho, workload e precisão necessária aos serviços.

## Validação por alteração

Executar primeiro o teste ligado ao comportamento, depois `flutter analyze` e a suíte Flutter quando a entrega alterar código compartilhado ou fluxo de usuário. Executar `:app:testDebugUnitTest` nas mudanças nativas e de schema/canais relacionados. Gerar EN/PT com `flutter gen-l10n` quando ARBs mudarem e formatar somente os arquivos Dart alterados.

Testes novos devem proteger resultados relevantes: rollback, elegibilidade, resultados antigos não sobrescrevendo novos, recuperação e regressões de consultas. Não criar testes que apenas repitam detalhes internos de widgets extraídos. Benchmarks pesados ficam fora da suíte rápida de PR.

Antes de concluir cada entrega, revisar async `BuildContext`, feedback de erro, consistência fresh/upgrade quando aplicável, segredos/logs e diff não relacionado. Registrar exatamente quais comandos e medições foram executados, sem apresentar hipóteses como ganhos realizados.

## Critério de conclusão da rodada

Os sete itens P1 de confiabilidade/custo e o baseline A24 estão resolvidos e validados; cada P2 tem alteração concluída ou decisão documentada por evidência, e A23 tem resultado de benchmark ou gatilho explícito para execução futura. O usuário continua conseguindo usar os mesmos recursos, com dados preservados e fluxos EN/PT consistentes.

Uma rodada encerrada deve entregar a tabela antes/depois de consultas, tempos, memória e tamanho que foram efetivamente medidos, além do inventário removido. Nenhum ganho percentual deve ser declarado apenas com base em redução de linhas ou leitura de código.
