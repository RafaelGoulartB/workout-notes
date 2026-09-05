Plano de melhoria da detecção de sono — 05/09/2026
=================================================

Objetivo: reduzir simultaneamente o início de sono antecipado e o excesso de tempo acordado no resultado. O cenário prioritário é o informado pelo usuário: celular na mesa de cabeceira ao lado da cama, demora para adormecer e resultados percebidos como inconsistentes. Ainda não existem horários anotados que permitam medir o erro individual.

Este documento é um plano de implementação. A auditoria e os testes indicados ao final foram realizados; as mudanças propostas ainda não foram implementadas.

**1. Definir o que podemos estimar e o que significa melhorar**

Priorizar sono/vigília e tempo para adormecer. Na mesa, o acelerômetro mede o celular, sem acoplamento confiável aos movimentos do corpo. Movimento zero não será evidência positiva de sono nesse modo. Pegar o aparelho pode fornecer contexto, mas precisa de validação e não justifica marcar minutos anteriores como acordado.

O áudio ambiente também não distingue sempre uma pessoa acordada e imóvel de uma pessoa dormindo silenciosamente. A saída precisa admitir incerteza. Usar três resultados de apresentação: provavelmente acordado, provavelmente dormindo e indeterminado. A incerteza deve ser acompanhada de cobertura para que o motor não pareça melhor apenas por deixar de classificar os casos difíceis.

Separar a estimativa de sono/vigília da classificação de sono profundo. O motor atual usa baixa frequência, silêncio e regularidade para favorecer profundo; não encontrei uma validação fisiológica dessa correspondência no material inspecionado. A proposta é tirar profundo da competição que decide sono/vigília e tratar qualquer classificação de estágios como uma etapa experimental independente, dependente de referência apropriada.

Essa cautela tem base empírica: um estudo de actigrafia de pulso encontrou sensibilidade de sono de 96,5%, mas especificidade de vigília de 32,9%. Isso ilustra por que acertar muito sono pode coexistir com perder muitos despertares; esses valores não são uma estimativa do aplicativo nem de um celular sobre a mesa. [Marino et al., 2013](https://pmc.ncbi.nlm.nih.gov/articles/PMC3792393/).

Também existe pesquisa com áudio e polissonografia, mas com dados pareados e modelos treinados: um estudo reportou concordância de 68% na validação externa por smartphone para quatro estágios. Esse resultado não pode ser transferido para nossos pesos heurísticos ou interpretado como desempenho binário sono/vigília. [Hong et al., 2022](https://pubmed.ncbi.nlm.nih.gov/35783665/).

**2. Achados que determinam a ordem do trabalho**

| Evidência no código atual | Consequência ou hipótese a verificar | Ação |
| --- | --- | --- |
| `SleepStageEngine._featuresOf` converte movimento ausente em zero; os escores de sono recompensam pouca movimentação. | Ausência de sensor e celular imóvel na mesa podem favorecer sono. Compatível com início antecipado, sem comprovar a causa das noites relatadas. | Representar disponibilidade e relevância por modalidade; excluir ausência de movimento como evidência de sono no modo mesa. |
| `AudioSignalProcessor` pode abrir áudio em 44.100 Hz, mas instancia `SpectralAnalyzer()` no padrão 16.000 Hz e `BreathingAnalyzer` usa constantes de 16.000 Hz. | Frequências e períodos ficam interpretados incorretamente se o fallback ocorrer. Não sabemos se ocorreu no aparelho do usuário. | Corrigir o contrato de amostragem antes de calibrar o classificador. |
| `noise_burst_count` incrementa por buffer acima do limiar. | O escore pode variar com tamanho e frequência de entrega dos buffers, sem mudança equivalente do som. | Medir duração e eventos com definição temporal estável. |
| O motor remove janelas não classificáveis antes do Viterbi e da descoberta do início de sono. | Janelas separadas por falhas podem parecer consecutivas; contagem de janelas não garante continuidade temporal. | Manter uma linha temporal explícita e interromper continuidade nas lacunas. |
| `_applyWindow` sobrescreve estágios antes/depois da janela e nos 90 segundos finais, inclusive resultados `unknown`. | Pode fabricar vigília e converter falha de sinal em acordado. A regra final não distingue término manual de interrupção técnica. | Preservar desconhecido; usar eventos reais de interação e motivo do encerramento. |
| A sobrescrita de estágio mantém probabilidades e confiança anteriores; `_confidence` mistura margem, máximo posterior e qualidade de captura. | O rótulo exibido pode discordar de sua distribuição; confiança interna não é precisão medida. | Tornar decisão e evidências coerentes; calibrar probabilidades com referência independente. |
| O motor de ruído, o motor de estágios e o sumarizador possuem critérios diferentes de início de sono. | Combinação de resultados pode misturar definições e mudar o início estimado de acordo com o caminho executado. | Uma política de início, despertar e duração por versão; compatibilidade antiga explicitamente identificada. |
| `SleepMonitorRepository.importNativeSpool` calcula o resultado no import; `_LiveSignal` exibe quiet/noise/invalid; `SleepStageModelGate` tem runtime nativo desabilitado. | Coleta em tempo real existe, mas o fluxo inspecionado não entrega classificação contínua equivalente ao resultado da noite. | Criar um modo causal explícito, com contrato distinto da revisão após a noite. |
| `SleepMonitorDiagnostics` usa sessão encerrada de pelo menos quatro horas como requisito de inferência. | O gate de validação de uma noite inteira impede reutilização direta em testes curtos e inferência ao vivo. | Separar qualidade local, elegibilidade de sessão e critérios de validação de campo. |
| Segmentos e épocas não são persistidos no import; o spool é apagado após sucesso. | Não há replay das noites recentes a partir apenas do resumo salvo. | Adicionar coleta diagnóstica opcional e limitada, com exportação de agregados. |
| A ferramenta do diário supõe despertares de 60 segundos, assume sono no restante do intervalo, exclui após o despertar final e ignora previsões desconhecidas na matriz. | A avaliação não mede adequadamente duração dos despertares, vigília final e cobertura; pode recompensar excesso de sono. | Corrigir o avaliador antes de utilizá-lo para escolher pesos. |

Arquivos principais: `lib/services/sleep_stage_engine.dart`, `sleep_inference_service.dart`, `sleep_stage_analysis_service.dart`, `lib/models/sleep_monitor_diagnostics.dart`, `lib/repositories/sleep_monitor_repository.dart`, `lib/services/sleep_monitor_service.dart`, `tool/validate_sleep_stages.dart` e os extratores Kotlin em `android/app/src/main/kotlin/com/workoutnotes/workout_notes/sleep/`.

**3. Primeira entrega: tornar cada erro reproduzível**

Congelar a versão atual como baseline, identificada por commit, versão de características, parâmetros e versão do motor. Construir replay em lote usando a ferramenta existente como ponto de partida. O mesmo conjunto de agregados deve produzir os mesmos rótulos e métricas, independentemente dos UUIDs.

Criar um modo de diagnóstico local, opcional, com retenção inicial proposta de 14 noites e limite de armazenamento. Persistir agregados antes da exclusão do spool e permitir exportação deliberada. Evitar gravação de áudio bruto, transcrições e envio automático. Os arquivos pessoais de campo não devem entrar no Git por padrão; fixtures compartilhadas devem ser minimizadas e revisadas.

Registrar por janela:

- horário, duração real, continuidade, contagem de amostras e cobertura por sensor;
- taxa e fonte efetivamente abertas para áudio, estado de calibração, baseline acústico, fração de silêncio digital e saturação;
- características de áudio e movimento, disponibilidade e posicionamento configurado;
- probabilidade de vigília, decisão, qualidade, motivos da decisão e versão dos parâmetros;
- eventos explícitos relevantes: início, interação no app, toque/descarte/soneca do alarme, encerramento e falhas.

Não coletar textos digitados nem histórico de uso de outros aplicativos. Um alarme tocar não prova que a pessoa acordou; uma tela acender sozinha também não.

Para suporte ao modo mesa, usar a persistência de preferências existente. Enquanto não houver escolha explícita, o modo conservador para sono/vigília não deve presumir acoplamento corporal do acelerômetro. Outros posicionamentos podem ser adicionados depois, com validação própria.

Critério de conclusão: exportar uma sessão, reproduzir exatamente suas decisões e explicar um trecho marcado como acordado ou dormindo sem depender da lembrança de quem alterou o código. Simular import com falha e nova tentativa sem perder nem duplicar registros.

**4. Segunda entrega: corrigir coleta e integridade temporal**

Manter a representação interna de áudio em 16 kHz, com reamostragem correta quando o dispositivo entregar 44,1 kHz. Alternativamente, parametrizar integralmente os extratores, desde que os testes provem características comparáveis. Para o primeiro caminho, o reamostrador precisa manter estado entre buffers e filtrar antes de reduzir a taxa.

`SpectralAnalyzer.add` atualmente processa apenas quadros completos em cada chamada. Preservar sobras entre chamadas, para que o resultado não dependa de como o Android dividiu o mesmo sinal. Calibração, baseline e rajadas também devem usar tempo/amostras, com constantes temporais independentes do número de callbacks.

Trocar contagem de buffers ruidosos por duração acima do limiar e número de eventos acústicos, com início, fim e intervalo mínimo de separação. Preservar as características antigas com sua versão para comparação, sem reinterpretar registros históricos como se fossem novos.

Usar tempo monotônico para duração e alinhamento de sensores; manter horário civil para apresentação. No movimento, verificar retorno de registro, tipo de sensor, contagem de amostras e lacunas. Não prolongar artificialmente uma atividade durante falta de callbacks. Verificar a diferença entre aceleração linear e a aproximação atual por magnitude menos gravidade.

Normalizar a linha temporal no Dart: ordenar, deduplicar, resolver sobreposições, recortar aos limites da sessão e representar períodos sem dados. Calcular métricas por segundos cobertos. Qualidade de captura e qualidade para distinguir sono são conceitos separados.

Testes de saída obrigatórios:

- sinal conhecido capturado a 16 kHz e 44,1 kHz mantém bandas e periodicidade dentro de tolerâncias previamente definidas;
- o mesmo PCM dividido em buffers diferentes mantém características e eventos equivalentes;
- silêncio digital, clipping, perda parcial, permissão revogada, callback ausente e mudança de relógio não viram sono ou vigília inventados;
- início/fim parcial de janela e lacunas não alteram a duração total contabilizada;
- no aparelho físico, verificar captura com tela apagada, engine Flutter encerrado, economia de bateria, alarme e disputa do microfone.

O serviço de primeiro plano já existe; a tarefa é verificar sua continuidade efetiva. As restrições de sensores em segundo plano justificam incluir esses testes no dispositivo. [Documentação Android](https://developer.android.com/develop/sensors-and-location/sensors/sensors_overview).

**5. Terceira entrega: construir uma referência que não favoreça um extremo**

Começar com 10–14 noites pessoais, como piloto de diagnóstico, e sessões controladas curtas. Essa quantidade serve para descobrir falhas e verificar a experiência do usuário; não comprova precisão generalizável.

O usuário pode marcar quando começou a tentar dormir, informar na manhã seguinte uma faixa aproximada em que adormeceu, e registrar início/fim aproximado dos despertares lembrados e do despertar final. Aceitar desconhecido e intervalo de incerteza. Não exigir ações durante o sono nem pedir para a pessoa estimar sono profundo.

Executar sessões acordado na configuração real: 15–30 minutos deitado em silêncio, leitura, mudanças de posição, celular parado sem pessoa no quarto e ventilador/ar ligado. Gravações ambientais e ruídos simulados servem para testar robustez da coleta e falsos positivos; não são referência fisiológica de sono.

Cada rótulo deve guardar origem e precisão: interação observada, sessão acordado controlada, lembrança aproximada, dispositivo comparador ou polissonografia sincronizada. O intervalo entre adormecer e despertar não recebe automaticamente rótulo verdadeiro de sono a cada 30 segundos. Relógios e outros aplicativos servem como comparação secundária, não como verdade.

Para medir sensibilidade de sono e despertares breves com confiabilidade, obter posteriormente noites com áudio do smartphone sincronizado à polissonografia e rótulos independentes. Verificar disponibilidade, licença e compatibilidade dos dados antes de escolher um conjunto público ou modelo. Dados apenas de EEG ou movimento no pulso não substituem áudio de mesa pareado.

Corrigir o avaliador para aceitar início e fim dos despertares, faixas incertas e ausência de rótulo; incluir vigília após o despertar final; contabilizar desconhecido separadamente; usar duração real; tratar conjunto vazio e classes ausentes como métrica indisponível. Corrigir também a disposição de falsos positivos/negativos no texto da matriz, atualmente incompatível com a descrição de linhas e colunas.

Separar noites inteiras para desenvolvimento e teste. Com vários participantes, separar por pessoa e reservar aparelhos/ambientes não vistos. Nunca dividir épocas vizinhas da mesma noite aleatoriamente entre treino e teste. No piloto individual, reservar as noites posteriores para confirmação prospectiva. Se o teste reservado orientar novos ajustes, ele passa a ser desenvolvimento e deve ser substituído.

Critério de conclusão: um detector que sempre prevê sono e outro que sempre prevê vigília aparecem claramente ruins no relatório equilibrado. Os dois JSONs atuais em `report/` são schema 1 / `audio-noise-v1`: ajudam a verificar compatibilidade, mas não validam a fusão espectral atual.

**6. Quarta entrega: motor de sono/vigília apropriado para mesa**

Organizar o fluxo como: agregados validados → qualidade e disponibilidade → características temporais → escore de vigília → decisão com continuidade e incerteza → resumo. Manter lógica pura em Dart, usando serviços/modelos existentes; Kotlin continua responsável por coleta e extração.

Construir primeiro um baseline binário simples e inspecionável. Comparar pesos atuais adaptados ao modo mesa com regressão logística regularizada, quando houver rótulos suficientes. Um modelo maior só avança se superar o baseline em noites reservadas. Não treinar usando as previsões do próprio aplicativo como verdade.

Características candidatas: variação acústica relativa ao ambiente, duração das rajadas, contraste espectral, estabilidade e mudanças recentes, periodicidade acompanhada de qualidade e contexto explícito de interação. Testar janelas causais de diferentes durações. A regularidade atual é uma autocorrelação da amplitude: ventilador, música, outra pessoa e ronco podem confundi-la; não assumir que toda periodicidade é respiração do usuário.

No modo mesa, não usar falta de movimento para aumentar probabilidade de sono. Avaliar movimento positivo como possível manuseio, condicionado ao contexto. Ausência de respiração audível também não demonstra vigília; sua presença periódica isolada não demonstra sono profundo.

Aplicar histerese temporal: evidência consistente para entrar em sono, retorno a acordado com evidência apropriada e ruído isolado sem transição automática. Os limiares e tempos serão escolhidos com dados de validação, não com uma meta de quantidade desejada de sono. Impedir que a persistência mantenha indefinidamente um estado depois de perda do sinal.

Usar interação explícita como evidência localizada. Não projetar automaticamente 90 segundos de vigília antes de qualquer fim de sessão. Calcular início sustentado com janelas em segundos e continuidade; remover a hipótese de que o horário em que a pessoa iniciou o monitoramento determina sua latência.

Qualidade insuficiente ou ambiguidade relevante produz indeterminado. A saída deve distinguir qualidade de captura, força da evidência e probabilidade calibrada. Quando houver rótulos adequados, verificar calibração por faixas de probabilidade; até lá, não apresentar confiança heurística como percentual de acerto.

Unificar a política de início, despertar final, despertares internos e duração. O sumarizador deve consumir a mesma linha temporal, sem redefinir por conta própria o que o motor decidiu. Não contar indeterminado como sono ou vigília. Mostrar cobertura e, quando apropriado, intervalo plausível de início; separar latência desconhecida de latência zero.

Critério de conclusão: a versão candidata reduz os erros dos dois lados em noites reservadas, com cobertura declarada, e supera baselines triviais. Um ganho apenas no total de minutos ou no formato do gráfico não basta.

**7. Quinta entrega: tempo real e resultado final coerentes**

Criar APIs separadas para atualização causal e revisão após encerramento. A atualização a cada agregado de aproximadamente 30 segundos utiliza apenas informação disponível até aquele instante. O período de confirmação do sono é um atraso de detecção a medir, não uma razão para prometer detecção instantânea.

O Viterbi atual usa a sequência inteira, probabilidades com informação futura e duração final. Não pode ser reaproveitado sem alteração como detector causal. Para o modo ao vivo, usar filtragem causal com estado incremental e janela limitada. Se houver revisão com atraso, declarar explicitamente esse atraso. Teste obrigatório: anexar o futuro não modifica uma decisão online que já foi emitida como definitiva.

Na tela, distinguir sinal capturado, estado provável e resultado provisório. O resumo final pode revisar trechos com contexto posterior, mas deve informar essa natureza e preservar a coerência de totais e incerteza.

Na primeira implementação, o serviço Android continua coletando quando o Flutter estiver fechado. A classificação Dart atualiza a interface enquanto o engine estiver disponível e recupera o contexto do spool ao reabrir, sem interromper nem duplicar a coleta. Separar snapshot parcial para retomar o classificador do import de sessão encerrada.

Se for requisito manter classificação continuamente calculada com o engine Flutter fechado, será necessário projetar e testar um engine Dart de fundo com estado recuperável e custo de bateria medido. Isso não existe no fluxo inspecionado e é uma entrega adicional explícita. Não criar silenciosamente um segundo classificador em Kotlin. O alarme deve continuar independente da classificação durante essas entregas.

**8. Critérios de aceitação e proteção contra novas oscilações**

Publicar relatório por noite e por cenário, com comparação pareada da versão atual e candidata. Com amostra suficiente, usar intervalos de confiança agrupados por pessoa/noite; não tratar milhares de épocas correlacionadas como milhares de participantes independentes.

| Medida | O que detecta | Critério inicial proposto |
| --- | --- | --- |
| Erro do início de sono | O problema de adormecer cedo demais no gráfico | Reduzir viés antecipado e erro absoluto; meta exploratória de mediana ≤15 min somente com referência de precisão suficiente. |
| Minutos de sono inventados em vigília confirmada | Tendência a sempre dormir | Redução nas sessões acordado em silêncio e períodos anotados; reportar também os indeterminados. |
| Minutos de vigília inventados em sono de referência | Tendência a dormir pouco | Redução simultânea em noites pareadas com referência apropriada. Sem referência, declarar essa medida não validada. |
| Recall de vigília e recall de sono | Equilíbrio entre os erros | Avaliar ambos e sua média; baselines sempre-sono/sempre-vigília não podem passar. |
| Tempo total e vigília após início do sono | Duração percebida da noite | Medir erro absoluto e viés separado; meta exploratória de mediana ≤30 min no total, sem compensação entre erros. |
| Eventos de despertar | Fragmentação real e falsos alarmes | Medir detecção por duração, falsos eventos por hora e atraso; não exigir detectar microdespertares sem evidência. |
| Cobertura de classificação | Ganhos artificiais por abstenção | Comparar erro à mesma cobertura e publicar proporção indeterminada, inclusive por classe de referência. |
| Calibração e qualidade | Excesso de certeza | Probabilidade deve corresponder à frequência observada em referência independente; captura boa não basta. |
| Continuidade e bateria | Viabilidade no Android real | Comparação com baseline no mesmo dispositivo e condições; lacunas explicadas e sem perda silenciosa. |

Os números de 15 e 30 minutos são metas propostas de produto, não resultados, normas clínicas ou promessa de viabilidade. Definir margem tolerável de regressão e cobertura mínima após conhecer o baseline e antes de avaliar o teste reservado. Melhorar a média sem inspecionar noites piores não autoriza publicar.

Executar ablações: áudio sozinho, adição de contexto de interação, temporalidade, periodicidade e eventual contribuição de movimento positivo. Cada componente precisa demonstrar benefício mensurável. Ajustar uma hipótese por experimento, mantendo manifesto de parâmetros, relatório e motivo.

Adicionar testes de regressão para: vigília quieta prolongada; ruído ambiental; pessoa ausente; respiração/ronco confundidos com ambiente; manuseio; alarme sem resposta; ruído isolado durante sono de referência; sensor ausente; falhas no começo/meio/fim; encerramento automático; sessão sem sono; sessão curta; retomada após interrupção. Cenários sintéticos verificam contratos, mas não estabelecem verdade fisiológica.

Publicar primeiro em modo de comparação: calcular candidato e baseline sobre os mesmos agregados sem substituir imediatamente o resultado estável. Após aprovação dos critérios, ativar a nova versão com possibilidade de retorno. Não reescrever silenciosamente resumos históricos; se houver reanálise, preservar versão/origem e distinguir o resultado recalculado.

**9. Sequência de implementação e pontos de decisão**

| Ordem | Entrega | Dependência e condição para avançar |
| --- | --- | --- |
| 1 | Diagnóstico opcional, replay e avaliador corrigido | Conservar baseline; exportar e reproduzir uma sessão com rótulos incertos representados corretamente. |
| 2 | Correções de amostragem, buffers, tempo, lacunas e disponibilidade | Testes determinísticos no Kotlin/Dart e verificação no dispositivo antes da coleta de referência nova. |
| 3 | Piloto pessoal de 10–14 noites e sessões acordado | Instrumentação corrigida; relatório dos padrões de erro, sem afirmar precisão geral. |
| 4 | Classificador binário e resumo único para modo mesa | Dados de desenvolvimento separados dos de confirmação; evidência de ganho equilibrado. |
| 5 | Estado causal na UI e recuperação do spool | Contrato online testado; requisito de execução com Flutter fechado tratado explicitamente. |
| 6 | Comparação prospectiva e validação mais ampla | Novas noites, outros aparelhos/ambientes e referência independente para alegações de precisão. |

As entregas de engenharia permitem iniciar o piloto; validar o comportamento real depende de acumular noites. Se áudio de mesa continuar incapaz de distinguir vigília silenciosa, o resultado correto será declarar essa limitação, usar confirmação/intervalos de incerteza e avaliar sensor corporal adicional como projeto posterior. Não continuar aumentando e reduzindo pesos para produzir um total de sono esperado.

Na implementação, seguir as fronteiras existentes: coleta Kotlin; inferência Dart; SQLite pelo repositório; `EventChannel` apenas como sinal para UI; persistência durável pelo spool/import. Campos novos persistidos exigem criação fresca, migração incremental, aumento de versão e testes correspondentes. Atualizar schema do spool, modelos, exportação e compatibilidade de registros antigos. Ajustar `test/support/ai_test_db.dart` se as novas tabelas forem lidas pelas ferramentas de IA. Textos visíveis em inglês e português, sem nova arquitetura de estado.

Validação de cada entrega: testes Kotlin dos extratores; testes Dart do motor, normalização, avaliador e sumarização; testes do repositório/migração quando aplicáveis; widgets para incerteza, falhas e modo ao vivo. Antes de integrar mudanças de comportamento, rodar formatação, localização quando alterada, `flutter analyze`, testes relevantes e ampliar à suíte conforme impacto.

**10. Verificação realizada para este plano**

Inspecionados coleta nativa, extratores, gate nativo, inferência, motor de estágios, sumarização, diagnóstico, import/persistência, tela ao vivo, ferramenta de validação, testes do motor e os metadados dos dois diagnósticos existentes.

Executado com sucesso: `flutter test test/sleep_stage_engine_test.dart test/sleep_stage_engine_validation_test.dart test/sleep_inference_service_test.dart test/sleep_stage_analysis_service_test.dart --reporter compact` — 23 testes passaram.

Não executados nesta elaboração: suíte completa, `flutter analyze`, testes Kotlin, build Android e medição em aparelho/noite real. Nenhum algoritmo, peso, configuração do aplicativo ou dado de sono foi alterado. O único arquivo criado é este plano.
