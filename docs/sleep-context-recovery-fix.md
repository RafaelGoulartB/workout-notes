Correção da perda de contexto no monitor — 12/09/2026

O usuário confirmou o aviso “Noite monitorada com estimativa incompleta”. O arquivo enviado corresponde à sessão concluída no alarme em 12/09, com aproximadamente 6h08 de captura, 735 agregados e qualidade de captura próxima de 100%. O v3 registrou 228 minutos de sono, 27 de vigília e 114 indeterminados; o limite de 20% de tempo indeterminado impediu a criação da entrada no histórico. Não houve falha de microfone ou encerramento antecipado nesse arquivo. Não foi enviado um segundo arquivo das duas noites recentes mencionadas.

O replay mostrou que 75 dos 114 minutos indeterminados estavam em `sleep_pending`. Depois de expirar o estado por áudio ambíguo, o cursor esquecia o estado confirmado e exigia novamente acúmulo de quietude, mesmo sem ter confirmado uma mudança de estado. Essa regra não estava coberta pelos testes anteriores de ruído isolado.

No motor `sleep-wake-bedside-v4`, o estado exibido pode ficar indeterminado enquanto o áudio é ambíguo, mas o último estado confirmado é preservado separadamente. Quando volta áudio válido com baixa atividade, o cursor retoma esse estado. Um despertar confirmado substitui a memória anterior; silêncio após esse despertar não retoma automaticamente o sono. Lacunas e captura inválida apagam a memória imediatamente; ambiguidade prolongada por vinte minutos também a descarta. A confirmação inicial e os critérios de sono/vigília permanecem. Essa memória é causal e não reescreve épocas já emitidas.

Reprodução com os arquivos originais, sem alterar os agregados:

| Arquivo | Sono estimado | Vigília estimada | Indeterminado | Tempo classificado |
| --- | ---: | ---: | ---: | ---: |
| 12/09 | 258,1 min | 66,3 min | 44,1 min | 88,0% |
| 08/09 | 323,6 min | 79,3 min | 21,5 min | 94,9% |

Esses resultados verificam o funcionamento do fluxo de estimativa, não a precisão fisiológica. Não há referência independente de sono/vigília para 12/09. O relato anterior de adormecer depois das 02h se refere a 08/09 e não foi aplicado à noite nova.

A recuperação de diagnósticos locais agora inclui sessões incompletas v3, além de v1/v2. Continua limitada a sessões existentes, com arquivo correspondente, sem estimativa publicada, preservando entradas manuais e com revalidação na transação. A versão v4 não é reprocessada repetidamente. Assim, ao abrir o app fora de uma gravação ativa, é possível recuperar a noite enviada se o diagnóstico original continuar guardado no aparelho. As demais noites só podem ser reanalisadas se também tiverem seus arquivos locais.

A fixture `test/fixtures/sleep_ambiguous_bedside.json` remove horários absolutos, identificadores, alarme e bateria; mantém os valores dos agregados sem arredondar. Os testes verificam retomada após ambiguidade, vigília confirmada, esquecimento por lacuna/captura inválida/ambiguidade longa, causalidade entre cursor e replay, cobertura da noite real e recuperação idempotente de uma sessão v3. A reprodução do teste contra o código v3 falhou como esperado em `build/sleep-sep12-regression-before.log`.

Não foram alterados sensores, frequência de coleta, FFT, timers ou wake locks. A alteração no cursor usa uma enumeração adicional; o reparo de arquivos ocorre na reconciliação, fora de uma gravação ativa. A bateria do arquivo passou de 85% para 71%, mas essa leitura é do aparelho inteiro e não comprova o consumo isolado do monitor.

Validação: `dart format` nos arquivos Dart alterados; `flutter analyze --no-pub` sem problemas; `flutter test --no-pub --concurrency=2 --reporter expanded` com 795 testes aprovados; `git diff --check` sem erros. Logs em `build/sleep-sep12-analysis.log` e `build/sleep-sep12-full-tests.log`. Os replays originais ficam em `build/sleep-sep12-current-replay.json` e `build/sleep-sep12-previous-replay.json`. Não foram repetidos testes Kotlin, pois a coleta nativa não foi alterada.

`flutter build apk --release --no-pub` concluído, com identificação v4 conferida nas bibliotecas AOT das três arquiteturas. APK de 92,9 MB em `build/app/outputs/flutter-apk/app-sleep-v4.apk` (cópia identificada do `app-release.apk`). Log em `build/sleep-sep12-release.log`. Não houve instalação ou validação de uma nova noite no aparelho nesta execução.
