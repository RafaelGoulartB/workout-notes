# Planos de corrida — avaliação por personas (set/2026)

Método: 21 personas simuladas direto na engine (`RunPlanComposer.outline`), com
o plano inteiro impresso semana a semana, mais o fluxo real percorrido no
emulador Android (catálogo → wizard de 4 passos → preview).

Personas principais:

| # | Persona | Plano | Entrada |
|---|---------|-------|---------|
| P1 | Sedentária, nunca correu | Começar a correr / Caminhada ao trote | 3 dias, sem pace |
| P2 | Corre 25 min, 8 km/sem | Primeiros 5 km | 3–4 dias |
| P3 | 5 km em 30:00, 15 km/sem | 5 km mais rápido | 3–4 dias, sem subida |
| P4 | 5 km em 25:00, 20 km/sem, meta 23:00 | 5 km mais rápido | 4 dias |
| P5 | 10 km em 55:00, 25 km/sem | 10 km mais rápido | 4 dias |
| P6 | 10 km em 60:00, 25 km/sem | Primeira meia | 3–4 dias |
| P7 | Meia em 2:10, 35 km/sem | Primeira maratona | 4 dias |

## 1. Engine — cumprível (segurança)

| Sev. | Problema | Evidência |
|------|----------|-----------|
| **Crítico** | "Caminhada ao trote": semana 7 manda correr **3,5 km contínuos** (~30 min) quem na semana 6 trotava blocos de 90 s. | P1b, W7 |
| **Crítico** | "Começar a correr": o mesmo salto — de blocos de 8 min para 3,5 km contínuos, e *antes* das sessões de 3×10 min da mesma semana. Prescrito em km para quem ainda não tem noção de distância. | P1, W7 |
| **Crítico** | Meta de tempo até 8 % mais rápida que a forma atual vira **ritmo de treino desde a semana 1**. Ex.: 25:00 → meta 23:00: tiros a 4:28/km (forma atual: 4:50) e limiar a 4:52 (atual: 5:16). | P4 |
| **Crítico** | Campo de tempo aceita `25` como **25 segundos** → "ritmo de prova 1:15/km" aceito e o botão Avançar libera. Sem validação de plausibilidade. | Emulador |
| Alto | Sessões ridículas de tão curtas: rodagens de 0,4–1,3 km e regenerativos de 0,7 km (ninguém sai de casa para correr 5 min). | P2, P2c, P3, P10 |
| Alto | "Regenerativo" de 7–9 km (~70 min) na véspera do longão — não é regenerativo. | P6, P7 |
| Médio | Rótulo não bate com a estrutura: "Ritmo de prova · 1×1 km" com bloco de 840 m / 1490 m. | P2, P5b |

## 2. Engine — efetivo (evolução)

| Sev. | Problema | Evidência |
|------|----------|-----------|
| **Crítico** | Primeira maratona típica (meia em 2:10, 35 km/sem) fica **bloqueada**: teto de 3 h de longão = 24,3 km < piso de 27,4 km. Beco sem saída sem sugestão. | P7 |
| Alto | Ritmos **nunca evoluem** durante o plano: o atleta treina 10–20 semanas no pace do dia da criação, e a "corrida-alvo" do 5 km mais rápido é o pace *atual*. | P3–P5 |
| Alto | O estímulo-chave da distância aparece pouco: no "5 km mais rápido" de 10 semanas só há **2 sessões de VO₂** (rotação de 6 tipos dilui tudo). | P3, P4 |
| Alto | Dose de VO₂ subdosada em volumes baixos: 3×400 m (≈7 min forte) ou até 3×200 m "VO₂" — 200 m é tiro de velocidade, não VO₂. | P3, P13 |
| Médio | Tiros não progridem em comprimento (400 m a plano inteiro para 5 km; 800 m para 10 km). | P3, P5 |
| Médio | Data da prova é só decorativa: o plano sempre começa "hoje" e a semana de prova não cai na data escolhida. | Código + emulador |

## 3. Interface e uso

| Sev. | Problema |
|------|----------|
| Alto | Ritmo: é preciso escolher **ou** prova recente **ou** meta. Para melhorar tempo, o app precisa das duas coisas (onde estou, onde quero chegar) e de dizer se a meta é realista. |
| Alto | Subida é um liga/desliga só em planos de performance; não existe "escada" nem "esteira inclinada". Desligar subida no plano "Força em subidas" esvazia o plano. |
| Alto | Bloqueios sem saída: base zero, volume insuficiente, maratona longa demais — o card vermelho explica mas não oferece o próximo passo (trocar de plano / usar menos dias). |
| Médio | Catálogo com 23 planos e vários parecidos para iniciante (Voltar a correr, Voltar após lesão, Caminhada ao trote, Começar a correr, Hábito, Base) — falta um "qual plano é para mim?". |
| Médio | Preview mostra só a semana 1, fora de ordem (Qui, Sex, Ter, Dom), sem duração estimada de cada sessão. |
| Médio | Não é possível escolher o dia do longão (sempre domingo/sábado). |
| Médio | "Terminar bem" vs "Recorde pessoal" aparece até no "5 km mais rápido" (redundante); "Conservador/Padrão/Agressivo" sem explicar o efeito. |
| Baixo | Nomes e notas das sessões são sempre em português, mesmo com o app em inglês (engine sem locale). |

## 4. O que foi implementado

Engine (`lib/services/run_plan_composer.dart`):

- **Corrida/caminhada**: a sessão contínua de graduação é por tempo, ~1,5× o
  maior bloco da semana (15 → 25 min), e é a última sessão da semana.
  "Caminhada ao trote" não tem mais corrida contínua. Notas orientam a repetir
  a semana se ficou difícil.
- **Ritmos que evoluem** (`RunPlanPaceRamp`): partem da forma atual e caminham
  até a meta, com teto de ganho realista por semana (0,35 / 0,25 / 0,15 VDOT
  conforme o nível). Meta classificada como realista / ambiciosa / irreal; o
  ritmo de prova mira no tempo alcançável. Sem meta, plano PB progride a meia
  velocidade; manutenção não progride.
- **Estímulo-chave semanal** em 5/10 km: com 1 dia de qualidade alterna VO₂ e
  limiar; com 2, VO₂ toda semana + limiar no segundo slot.
- **Dose de VO₂**: mínimo de ~10 min no ritmo de tiro (teto 12% da semana),
  tiros nunca abaixo de 400 m e que alongam ao longo do plano (400 → 800 m no
  5 km). Se nem 3×400 m cabem, vira fartlek.
- **Piso de duração** (~15 min, 1,6–2,5 km) em rodagens; regenerativo com teto
  de ~40 min. Semana de prova enxuta: ativação + rodagem + prova (+ trote em
  planos de 5 dias).
- **Maratona**: teto do longão pode ir de 3 h a 3h30 só até o piso de ~27 km.
  Piso de longão para 5 km/10 km passou a 80%/85% da distância.
- **Data da prova**: prova mais próxima encurta o plano (mínimo ~60% do
  template, senão bloqueia com aviso); prova mais distante adia o início. A
  prova cai no dia da semana real, sem treinos depois dela. A partir de
  sexta, a semana 1 é a seguinte. A ativação ancora na data da prova.
- **Terreno**: ladeira, escadaria (30–45 s, descida caminhando), esteira
  inclinada (5–6%) ou só plano.
- **Dia do longão** escolhível. Rótulos de ritmo de prova batem com o passo.
- `RunPaceCalculator.isPlausibleRace` rejeita tempos fora do limite humano.

Interface:

- Catálogo: "Não sabe por onde começar?" com duas perguntas →
  `RunPlanTemplates.recommend`.
- Wizard: dia do longão; dia já cheio avisa em vez de trocar em silêncio;
  data da prova mostra se o plano foi encurtado / quando começa; intenção
  escondida nos planos que só fazem sentido para recorde; explicação de cada
  volume; seletor de terreno; tempo atual **e** meta separados, com validação
  (número solto = minutos, `1:55` vira h:mm na meia) e veredito da meta;
  histórico GPS convertido para o equivalente na distância padrão; preview
  navegável por semana (setas ou toque no gráfico), ordenado por dia, com
  duração estimada; avisos com ação (usar 3 dias, volume conservador, abrir
  outro plano, mudar a data).
- Plano ativado para o futuro mostra "Começa em <data>".

Testes: `test/run_plan_persona_test.dart` (novo) cobre cada persona acima;
testes existentes ajustados onde o comportamento mudou de propósito.

Pendente (fora deste ciclo): nomes/notas de sessão localizados (a engine ainda
gera em português); adaptação do plano ao que foi de fato cumprido (RPE,
sessões puladas).
