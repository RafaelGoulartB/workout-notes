Correção da estimativa de sono na cabeceira — 06/09/2026

O usuário relatou duas noites com o alerta de estimativa incompleta após a entrega anterior. Os diagnósticos estavam desativados, portanto os agregados dessas noites não estão disponíveis para reprodução ou recuperação. A correção trata uma regressão reproduzível no código; não permite afirmar que foi a única causa no aparelho.

O motor `sleep-wake-bedside-v1` exigia dez minutos consecutivos de áudio periódico compatível com respiração. Áudio válido e quieto, sem essa periodicidade, não confirmava sono e fazia uma classificação anterior expirar em dois minutos. Como o repositório não publica totais com mais de 20% de tempo indeterminado, uma noite quieta inteira podia ser coletada e terminar sem entrada no histórico. Os testes anteriores exigiam esse resultado, sem verificar a utilidade de uma noite típica na cabeceira.

O motor `sleep-wake-bedside-v2` usa os mesmos agregados `audio-features-v3`:

- Áudio periódico continua permitindo confirmação após dez minutos. Baixa atividade sonora válida também permite estimar sono, com confirmação mais lenta de vinte minutos. Não se retroage o início para preencher todo o tempo na cama.
- Falhas na detecção de periodicidade não zeram o acúmulo de baixa atividade. Após confirmar sono, áudio válido e quieto mantém a estimativa, mesmo sem respiração audível.
- Um ruído isolado reduz o suporte acumulado; atividade sustentada por sessenta segundos confirma vigília e reinicia a confirmação de sono. Ruído alto estacionário sozinho continua sem confirmar vigília.
- Captura inválida e lacunas continuam indeterminadas e reiniciam a confirmação. O limite de 20% de tempo indeterminado permanece; o alerta não foi simplesmente ocultado.
- A versão do motor fica no resumo e nos diagnósticos. Não há migração ou reescrita de noites históricas sem agregados. Os textos em português e inglês explicam que vigília quieta pode ser confundida com sono; os acentos corrompidos nos textos do monitor também foram corrigidos.

A mudança acrescenta um contador limitado ao cursor Dart que já processa cada agregado. Não muda microfone, serviço Android, wake lock, frequência de captura, orçamento de FFT, rede ou escrita durante a noite. Não ativa acelerômetro ou processamento Flutter em segundo plano. O consumo real de bateria ainda depende de medição no aparelho.

Os testes de regressão cobrem noite de oito horas sem respiração audível, periodicidade intermitente com ruídos curtos, manutenção da estimativa após perda da periodicidade, retomada após vigília, silêncio digital, lacunas e gravação idempotente do resultado no histórico. Reexecutados contra o motor anterior, os cenários de noite quieta e perda da periodicidade falham; com o motor corrigido, passam. A igualdade entre o cursor ao vivo e o replay permanece coberta.

As durações são parâmetros heurísticos, não medições do instante fisiológico de adormecer. O teste sintético demonstra a correção do fluxo, não uma taxa de precisão em noites reais. Para investigar uma eventual recorrência, ativar opcionalmente “Guardar diagnósticos de sono” antes de encerrar a próxima sessão e exportar o arquivo. Essa opção salva os agregados existentes após a importação e não grava áudio bruto.

Verificações desta correção:

- `flutter gen-l10n` e `dart format` concluídos; `flutter analyze --no-pub` sem problemas.
- Motor, repositório e estado ao vivo: 29 testes passaram (`build/sleep-regression-after.log`). O teste de regressão contra a versão anterior está em `build/sleep-regression-before.log`.
- Suíte completa repetida com `--concurrency=2`: 781 passaram e um falhou. A falha restante é `nutrition_widget_test.dart: balance nutrient averages start collapsed and load on expand`, com timer SQLite pendente ao desmontar o widget. Esse teste passou isoladamente, sem alteração de código. O timeout do gerador de dados que apareceu na primeira execução não reapareceu. Logs: `build/sleep-flutter-tests-recheck.log` e `build/sleep-unrelated-test-recheck.log`. Não se afirma que a suíte completa está verde.
- Validação local com Flutter 3.44.8 / Dart 3.12.2. O resolvedor ajustou temporariamente cinco dependências fixadas pelo SDK local; essas mudanças em `pubspec.lock` foram revertidas para não alterar as dependências do projeto.
- `git diff --check` sem erros. Os testes Kotlin não foram repetidos nesta correção, que não modifica código nativo.
- `flutter build apk --release --no-pub` concluído: `build/app/outputs/flutter-apk/app-release.apk` (92,8 MB). Log em `build/sleep-release-build.log`. O APK não foi instalado ou validado em uma noite real nesta execução.
