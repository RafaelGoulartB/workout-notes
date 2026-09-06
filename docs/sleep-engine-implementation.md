Implementação do monitor de sono — 05/09/2026

Atualização de 06/09/2026: o comportamento `sleep-wake-bedside-v1` descrito abaixo foi corrigido em `sleep-wake-bedside-v2`. Consulte [a correção da regressão na cabeceira](sleep-bedside-regression-fix.md) para as regras atuais. Esta página registra a entrega original.

As novas sessões usam `audio-features-v3` e o motor causal `sleep-wake-bedside-v1`, destinado ao celular na mesa de cabeceira. O caminho antigo permanece versionado para reproduzir gravações antigas; os resumos históricos não são reanalisados automaticamente.

**Comportamento implementado**

- Ausência de movimento ou silêncio, isoladamente, não confirmam sono. As novas sessões não ativam o acelerômetro.
- O motor produz sono provável, vigília provável ou indeterminado. Não estima profundo nem apresenta os escores heurísticos como percentual de precisão.
- Evidência acústica periódica precisa ser sustentada antes da confirmação de sono. A confirmação atual é causal: não retroage o início sobre os minutos anteriores. É um baseline experimental, não um modelo calibrado com polissonografia.
- Ruído breve não confirma um despertar; ruído alto estacionário sozinho também não. Evidência expirada e lacunas tornam o estado indeterminado.
- Não há regra de vigília obrigatória nos 90 segundos finais, nem fases impostas pelo horário/duração da noite no caminho v3.
- Lacunas, sobreposições e durações inválidas são tratadas no replay; períodos desconhecidos permanecem separados dos totais de sono e vigília.
- A sumarização v3 utiliza o início confirmado pelo motor e não cria um despertar final sem uma sequência acordada. Latência desconhecida permanece sem valor.
- Com mais de 20% de tempo indeterminado, não é publicado um total estimado da noite. A sessão continua acessível como estimativa incompleta no painel; ela não vira uma entrada fictícia de sono nem contamina as médias com tempo na cama.
- A análise funciona em sessões curtas; o antigo gate de quatro horas continua sendo um critério para validar noites legadas, não para bloquear a estimativa nova.
- A UI reutiliza um cursor de tamanho constante por sessão, processando apenas novos agregados. Ao abrir uma sessão ativa, recupera o contexto do spool uma vez. A coleta continua nativa com Flutter encerrado; não foi introduzido engine Flutter de fundo para classificar sem interface.
- Corrigida a exibição de eficiência na tela de resultado: o campo já é percentual e não deve ser multiplicado novamente por 100.

**Coleta e bateria**

- Os extratores recebem a taxa realmente aberta: 16 kHz ou fallback de 44,1 kHz. A análise respiratória mantém saltos de meio segundo em ambas.
- O áudio é dividido em blocos de duração fixa para RMS, baseline, variação de nível e duração de atividade. O resultado deixa de depender dos tamanhos de callbacks do `AudioRecord`.
- O analisador espectral preserva quadros parciais entre buffers. A FFT usa no máximo 8 quadros por segundo em regime contínuo em ambas as taxas; amostras intermediárias continuam alimentando os agregados acústicos e a periodicidade. Quadros de silêncio digital não executam FFT.
- Buffers são reutilizados; os estados dos extratores são descartados a cada janela. Nenhum áudio bruto é persistido e não há rede, modelo neural ou processamento duplicado de noite inteira durante a captura.
- Duração da captura, timeout, limite da sessão e término usam relógio monotônico ancorado ao horário de início. A interface cancela o contador periódico quando o app deixa o primeiro plano.
- Os diagnósticos acrescentam somente leituras de bateria no começo e no fim. Elas não isolam o consumo do aplicativo: outros processos e carregamento interferem. Não há polling de bateria.
- O microfone e o serviço de primeiro plano continuam necessários. O wake lock parcial existente foi mantido para não interromper a captura com tela apagada. Limitar CPU não prova consumo aceitável de bateria; essa conclusão depende de medição noturna no aparelho.

**Diagnóstico e replay**

Em Configurações de sono, habilitar “Guardar diagnósticos de sono” antes de finalizar uma sessão. A função é opcional e desligada por padrão. Ela arquiva os agregados já existentes após o import, junto à versão/parâmetros e resumo gerado. Não acrescenta gravação ou escrita por amostra durante a noite.

O armazenamento é limitado a 14 arquivos, 4 MB por arquivo e 20 MB no conjunto. Arquivos com mais de 14 dias são eliminados na próxima utilização do arquivo de diagnósticos; não existe alarme de limpeza noturna. Desativar a opção remove os diagnósticos salvos. A exportação pelo seletor de arquivos é explícita e inclui horários da sessão e identificadores locais, além dos agregados. Não inclui áudio, conversas, tokens de provedores ou envio automático.

Gerar um exemplo de rótulos e executar a comparação:

```powershell
dart run tool/replay_sleep.dart --template
dart run tool/replay_sleep.dart caminho/diagnostico.json caminho/rotulos.json
```

O arquivo de rótulos usa intervalos relativos ao início da sessão, estado `awake` ou `asleep` e origem da referência. Intervalos não anotados não são presumidos como sono. O relatório inclui cobertura total, cobertura nos intervalos anotados, falsos minutos de sono/vigília, abstenções por classe e decisões por janela com motivos. Avaliações sem referência suficiente retornam métricas nulas. A ferramenta antiga encaminha os novos arquivos para o avaliador novo; sua matriz legada e a exclusão da vigília final também foram corrigidas.

Exemplo de referência de vigília confirmada:

```json
{
  "labels": [
    {"start_seconds": 0, "end_seconds": 900, "state": "awake", "source": "controlled_awake"}
  ]
}
```

Esses dados não exigem migração de SQLite: os novos atributos dos sensores ficam nos agregados transitórios do spool/diagnóstico; os resultados usam colunas de sessão já existentes. Textos novos estão em inglês e português.

**Limites da entrega e medição no aparelho**

Os testes determinísticos verificam os contratos da coleta, orçamento de FFT, causalidade, integridade da linha temporal, persistência e apresentação. Não comprovam sensibilidade/especificidade fisiológicas. Os pesos e durações continuam sendo uma referência inicial a confrontar com noites reais. Uma pessoa acordada e imóvel pode produzir áudio indistinguível de sono; o resultado correto nesses casos pode ser indeterminado.

Não havia dispositivo conectado via ADB durante esta implementação. Para validar bateria, usar uma build release e comparar noites com condições equivalentes (aparelho, duração, tela, carregamento, ambiente e outros aplicativos). Registrar carga inicial/final, cobertura e falhas; inspecionar `adb shell dumpsys batterystats` quando disponível. Uma noite carregando não mede descarga. Não aprovar alegações de economia por um benchmark de CPU ou pelo percentual isolado de uma noite.

A coleta prospectiva pessoal e a validação com referência independente previstas no plano original continuam dependendo de noites reais. Esta entrega fornece as correções e instrumentos necessários; não substitui essa etapa por porcentagens obtidas de dados sintéticos.

**Verificações realizadas nesta entrega**

- `flutter gen-l10n` e formatação dos arquivos Dart alterados.
- `flutter analyze --no-pub`: sem problemas.
- `flutter test --reporter expanded`: 777 testes passaram.
- `android/gradlew.bat :app:testDebugUnitTest`: 50 testes passaram em 12 suítes, incluindo taxa alternativa, independência dos buffers, silêncio digital e limite de FFT.
- `dart run tool/replay_sleep.dart --template`: executado com sucesso.
- `flutter build apk --release`: concluído; artefato em `build/app/outputs/flutter-apk/app-release.apk`.
- `git diff --check`: sem erros de whitespace. Não foram feitos commit, push, instalação em aparelho ou publicação.

Os logs locais das verificações estão em `build/sleep-flutter-tests.log`, `build/sleep-kotlin-tests.log` e `build/sleep-release-build.log`.
