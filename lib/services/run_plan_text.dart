/// Language a generated plan is written in.
enum RunPlanLanguage {
  pt('pt'),
  en('en');

  final String code;
  const RunPlanLanguage(this.code);

  static RunPlanLanguage fromCode(String? code) =>
      code == 'en' ? RunPlanLanguage.en : RunPlanLanguage.pt;
}

/// Names, notes and effort labels of the sessions the composer generates.
///
/// Sessions are stored in the database as text, so they are written once, in
/// the athlete's language at creation time. Portuguese stays the default so
/// existing plans and callers without a locale read the same as before.
abstract class RunPlanText {
  const RunPlanText();

  static RunPlanText of(RunPlanLanguage language) => switch (language) {
    RunPlanLanguage.pt => const _Pt(),
    RunPlanLanguage.en => const _En(),
  };

  /// `1,5 km` / `1.5 km`, `800 m`.
  String distance(double km);

  String easyWindow(String base, String window);

  String get easyName;
  String get recoveryName;
  String get easyNote;
  String get recoveryNote;
  String easyStridesName(int strides);
  String get easyStridesZone;
  String easyStridesNote(int strides, int seconds);

  String get longName;
  String get longNote;
  String get longTaperNote;

  String get longRacePaceName;
  String get longRacePaceZone;
  String longRacePaceNote(int blocks);

  String get raceName;
  String get raceNote;

  String sharpenName(int reps);
  String get sharpenNote;

  String intervalName(int reps, int meters);
  String intervalNote(int restSeconds);

  String tempoCruiseName(int reps, int minutes);
  String tempoCruiseNote(int restSeconds);
  String tempoName(int minutes);
  String get tempoNote;

  String fartlekName(int reps, int seconds);
  String get fartlekNote;

  String hillName(int reps, int seconds);
  String hillNote(int seconds);
  String stairsName(int reps, int seconds);
  String stairsNote(int seconds);
  String treadmillHillName(int reps, int seconds);
  String treadmillHillNote(int seconds);

  String progressionName(int km);
  String get progressionNote;

  String racePaceName(int blocks, String block);
  String get racePaceNote;

  String testName(String distance);
  String get testNote;

  String get runWalkName;
  String get walkJogName;
  String get runWalkNote;
  String get walkJogNote;
  String continuousName(int minutes);
  String get continuousNote;
}

class _Pt extends RunPlanText {
  const _Pt();

  @override
  String distance(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    final rounded = (km * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.toStringAsFixed(0)} km'
        : '${rounded.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  @override
  String easyWindow(String base, String window) =>
      '$base Faixa fácil: $window.';

  @override
  String get easyName => 'Rodagem leve';
  @override
  String get recoveryName => 'Regenerativo';
  @override
  String get easyNote =>
      'Ritmo de conversa. Cerca de 80% do volume deve ficar aqui — '
      'correr o fácil rápido demais é o erro mais comum.';
  @override
  String get recoveryNote =>
      'Muito leve. Acelera a recuperação entre estímulos de qualidade.';
  @override
  String easyStridesName(int strides) => 'Rodagem leve + $strides educativos';
  @override
  String get easyStridesZone => 'Z1–Z2 / RPE 2–4 + educativos';
  @override
  String easyStridesNote(int strides, int seconds) =>
      'Rodagem tranquila e, no fim, $strides tiros soltos de ${seconds}s '
      '(não é tiro forçado): melhora economia de corrida e recruta fibras '
      'rápidas sem custo de recuperação.';

  @override
  String get longName => 'Longão aeróbico';
  @override
  String get longNote =>
      'Ritmo de conversa. Base aeróbica: o volume fácil impulsiona a '
      'maioria dos ganhos.';
  @override
  String get longTaperNote =>
      'Volume reduzido para o polimento — corte a distância, não o ritmo.';

  @override
  String get longRacePaceName => 'Longão com blocos no ritmo de prova';
  @override
  String get longRacePaceZone => 'Z2 → ritmo de prova';
  @override
  String longRacePaceNote(int blocks) =>
      'A maior parte fácil e $blocks blocos no ritmo-alvo já cansado. '
      'É o treino que mais transfere para o dia da prova: ensina o corpo a '
      'poupar glicogênio e a manter a técnica em fadiga.';

  @override
  String get raceName => 'Corrida-alvo';
  @override
  String get raceNote =>
      'Prova ou simulado. Saia no ritmo treinado, não no ritmo da largada.';

  @override
  String sharpenName(int reps) => 'Ativação · $reps×400 m no ritmo de prova';
  @override
  String get sharpenNote =>
      'Semana de prova: o objetivo é lembrar o ritmo, não treinar. '
      'Tem que terminar com a sensação de que sobrou muito.';

  @override
  String intervalName(int reps, int meters) => '$reps×$meters m (VO₂)';
  @override
  String intervalNote(int restSeconds) =>
      'Tiros no ritmo de VO₂máx com ${restSeconds}s de trote — a recuperação '
      'acompanha a duração do tiro para que todos saiam iguais. Se o '
      'último tiro sair bem mais lento, pare ali: é sinal de pace alto.';

  @override
  String tempoCruiseName(int reps, int minutes) =>
      'Limiar · $reps×$minutes min';
  @override
  String tempoCruiseNote(int restSeconds) =>
      'Blocos de limiar com ${restSeconds}s de trote entre eles. Fracionar '
      'acima de 20 min sustenta o ritmo certo por mais tempo: mesmo '
      'estímulo, menos queda de pace no fim.';
  @override
  String tempoName(int minutes) => 'Limiar · $minutes min';
  @override
  String get tempoNote =>
      'Ritmo de limiar: sustentável, só dá para falar frases curtas. '
      'Empurra o ponto em que o lactato começa a acumular — o que mais '
      'melhora o pace que você consegue segurar numa prova.';

  @override
  String fartlekName(int reps, int seconds) => 'Fartlek · $reps×${seconds}s';
  @override
  String get fartlekNote =>
      'Variações de ritmo entre limiar e VO₂. Melhora economia e a troca '
      'de marcha sem o custo de recuperação de um tiro cronometrado.';

  @override
  String hillName(int reps, int seconds) => 'Morros · $reps×${seconds}s';
  @override
  String hillNote(int seconds) =>
      'Subida forte por ${seconds}s — esforço, não pace: no morro o ritmo '
      'cai naturalmente. Volte trotando. Força específica e técnica com '
      'menos impacto que tiros no plano.';
  @override
  String stairsName(int reps, int seconds) => 'Escadaria · $reps×${seconds}s';
  @override
  String stairsNote(int seconds) =>
      'Suba a escada em ritmo forte por ${seconds}s, degrau a degrau, '
      'tronco firme e olhar à frente. Desça caminhando, com calma e '
      'segurando o corrimão se houver — a descida é a recuperação.';
  @override
  String treadmillHillName(int reps, int seconds) =>
      'Esteira inclinada · $reps×${seconds}s';
  @override
  String treadmillHillNote(int seconds) =>
      'Na esteira a 5–6% de inclinação, ${seconds}s em esforço forte. '
      'Volte para 1% e trote leve na recuperação. Esforço, não pace: '
      'mesma força específica de um morro.';

  @override
  String progressionName(int km) => 'Progressivo · $km km';
  @override
  String get progressionNote =>
      'Comece fácil e feche mais rápido. Treina distribuição de esforço e '
      'ensina a acelerar já cansado.';

  @override
  String racePaceName(int blocks, String block) =>
      'Ritmo de prova · $blocks×$block';
  @override
  String get racePaceNote =>
      'Blocos exatamente no ritmo-alvo da prova. Especificidade: calibra '
      'passada, respiração e cabeça no pace que você vai precisar segurar.';

  @override
  String testName(String distance) => 'Teste de $distance';
  @override
  String get testNote =>
      'Aqueça bem e corra a distância no seu melhor ritmo sustentável — '
      'forte, mas sem sprintar no começo. O app usa o resultado para '
      'recalibrar os ritmos das próximas semanas.';

  @override
  String get runWalkName => 'Corrida e caminhada';
  @override
  String get walkJogName => 'Trote e caminhada';
  @override
  String get runWalkNote =>
      'Corra confortável e caminhe antes de perder a forma. '
      'Se a semana ficou difícil, repita-a antes de avançar.';
  @override
  String get walkJogNote =>
      'Trote bem leve; caminhe antes de perder a respiração. '
      'Se a semana ficou difícil, repita-a antes de avançar.';
  @override
  String continuousName(int minutes) => 'Corrida contínua · $minutes min';
  @override
  String get continuousNote =>
      'Corra sem parar, devagar o bastante para conseguir conversar. '
      'Se precisar, caminhe 1 minuto e retome — completar vale mais '
      'que o ritmo.';
}

class _En extends RunPlanText {
  const _En();

  @override
  String distance(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    final rounded = (km * 10).round() / 10;
    return rounded == rounded.roundToDouble()
        ? '${rounded.toStringAsFixed(0)} km'
        : '${rounded.toStringAsFixed(1)} km';
  }

  @override
  String easyWindow(String base, String window) => '$base Easy range: $window.';

  @override
  String get easyName => 'Easy run';
  @override
  String get recoveryName => 'Recovery run';
  @override
  String get easyNote =>
      'Conversational pace. About 80% of your volume belongs here — running '
      'the easy days too fast is the most common mistake.';
  @override
  String get recoveryNote =>
      'Very easy. Speeds up recovery between quality sessions.';
  @override
  String easyStridesName(int strides) => 'Easy run + $strides strides';
  @override
  String get easyStridesZone => 'Z1–Z2 / RPE 2–4 + strides';
  @override
  String easyStridesNote(int strides, int seconds) =>
      'Relaxed run and, at the end, $strides loose ${seconds}s strides (not a '
      'sprint): improves running economy and recruits fast fibres at no '
      'recovery cost.';

  @override
  String get longName => 'Aerobic long run';
  @override
  String get longNote =>
      'Conversational pace. Aerobic base: easy volume drives most of the '
      'gains.';
  @override
  String get longTaperNote =>
      'Shorter for the taper — cut the distance, not the pace.';

  @override
  String get longRacePaceName => 'Long run with race-pace blocks';
  @override
  String get longRacePaceZone => 'Z2 → race pace';
  @override
  String longRacePaceNote(int blocks) =>
      'Mostly easy, with $blocks blocks at goal pace on tired legs. It is the '
      'session that transfers most to race day: it teaches the body to spare '
      'glycogen and hold form under fatigue.';

  @override
  String get raceName => 'Goal race';
  @override
  String get raceNote =>
      'Race or time trial. Start at your trained pace, not the start-line '
      'pace.';

  @override
  String sharpenName(int reps) => 'Sharpener · $reps×400 m at race pace';
  @override
  String get sharpenNote =>
      'Race week: the aim is to remember the pace, not to train. Finish '
      'feeling there was plenty left.';

  @override
  String intervalName(int reps, int meters) => '$reps×$meters m (VO₂)';
  @override
  String intervalNote(int restSeconds) =>
      'VO₂max reps with ${restSeconds}s of jogging — recovery follows rep '
      'length so every rep comes out the same. If the last rep is much '
      'slower, stop there: the pace was too high.';

  @override
  String tempoCruiseName(int reps, int minutes) =>
      'Threshold · $reps×$minutes min';
  @override
  String tempoCruiseNote(int restSeconds) =>
      'Threshold blocks with ${restSeconds}s of jogging between them. '
      'Splitting beyond 20 min holds the right pace for longer: same '
      'stimulus, less fade at the end.';
  @override
  String tempoName(int minutes) => 'Threshold · $minutes min';
  @override
  String get tempoNote =>
      'Threshold pace: sustainable, short sentences only. It pushes back '
      'the point where lactate builds up — what most improves the pace you '
      'can hold in a race.';

  @override
  String fartlekName(int reps, int seconds) => 'Fartlek · $reps×${seconds}s';
  @override
  String get fartlekNote =>
      'Pace changes between threshold and VO₂. Improves economy and gear '
      'changes without the recovery cost of timed reps.';

  @override
  String hillName(int reps, int seconds) => 'Hills · $reps×${seconds}s';
  @override
  String hillNote(int seconds) =>
      'Strong ${seconds}s uphill — effort, not pace: the pace drops '
      'naturally on a hill. Jog back down. Specific strength and form with '
      'less impact than flat reps.';
  @override
  String stairsName(int reps, int seconds) => 'Stairs · $reps×${seconds}s';
  @override
  String stairsNote(int seconds) =>
      'Climb the stairs hard for ${seconds}s, one step at a time, trunk '
      'firm and eyes ahead. Walk down calmly, holding the rail if there is '
      'one — the descent is the recovery.';
  @override
  String treadmillHillName(int reps, int seconds) =>
      'Treadmill incline · $reps×${seconds}s';
  @override
  String treadmillHillNote(int seconds) =>
      'At 5–6% incline, ${seconds}s of hard effort. Drop back to 1% and jog '
      'easy to recover. Effort, not pace: the same specific strength as a '
      'hill.';

  @override
  String progressionName(int km) => 'Progression · $km km';
  @override
  String get progressionNote =>
      'Start easy and finish faster. Trains pacing and teaches you to speed '
      'up when tired.';

  @override
  String racePaceName(int blocks, String block) => 'Race pace · $blocks×$block';
  @override
  String get racePaceNote =>
      'Blocks exactly at goal race pace. Specificity: tunes stride, '
      'breathing and focus at the pace you will need to hold.';

  @override
  String testName(String distance) => '$distance time trial';
  @override
  String get testNote =>
      'Warm up well and run the distance at your best sustainable pace — '
      'hard, but no sprint at the start. The app uses the result to '
      'recalibrate the paces of the coming weeks.';

  @override
  String get runWalkName => 'Run/walk';
  @override
  String get walkJogName => 'Jog/walk';
  @override
  String get runWalkNote =>
      'Run comfortably and walk before your form breaks down. If the week '
      'felt hard, repeat it before moving on.';
  @override
  String get walkJogNote =>
      'Very gentle jog; walk before you get out of breath. If the week felt '
      'hard, repeat it before moving on.';
  @override
  String continuousName(int minutes) => 'Continuous run · $minutes min';
  @override
  String get continuousNote =>
      'Run without stopping, slowly enough to hold a conversation. If you '
      'need to, walk for 1 minute and carry on — finishing matters more '
      'than pace.';
}
