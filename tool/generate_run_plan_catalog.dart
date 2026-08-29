import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_templates.dart';

const _calibration = RunPlanPaceCalibration(
  distanceMeters: 5000,
  timeSeconds: 25 * 60,
);

void main() {
  test('generate the run-plan HTML catalog', _generate);
}

void _generate() {
  final plans = RunPlanTemplates.all.map(_planData).toList();
  final json = jsonEncode(plans).replaceAll('</', r'<\/');
  final output = _page.replaceFirst('__PLAN_DATA__', json);
  final file = File('docs/run-plan-catalog.html');
  file.writeAsStringSync(output);
  stdout.writeln(
    'Generated ${file.path} with ${plans.length} templates and '
    '${plans.fold<int>(0, (sum, plan) => sum + (plan['frequencies'] as List).length) ~/ 2} frequencies '
    '(each with and without hills).',
  );
}

Map<String, Object?> _planData(RunPlanTemplate template) {
  final frequencies = <Map<String, Object?>>[];
  for (final sessions in template.allowedSessionsPerWeek) {
    frequencies.add(
      _frequencyData(template, sessions: sessions, includeHills: true),
    );
    frequencies.add(
      _frequencyData(template, sessions: sessions, includeHills: false),
    );
  }
  return {
    'key': template.key,
    'title': template.titlePt,
    'description': template.descriptionPt,
    'prerequisite': template.prerequisitePt,
    'category': _category(template.category),
    'categoryKey': template.category.name,
    'level': _level(template.level),
    'style': template.style.name,
    'goal': template.goalKind.name,
    'weeks': template.weeks,
    'defaultSessions': _defaultSessions(template),
    'intent': _intent(template).name,
    'baselineKm': template.prerequisiteWeeklyKm,
    'frequencies': frequencies,
  };
}

Map<String, Object?> _frequencyData(
  RunPlanTemplate template, {
  required int sessions,
  required bool includeHills,
}) {
  final config = RunPlanBuildConfig(
    sessionsPerWeek: sessions,
    availableDays: _days(sessions),
    intent: _intent(template),
    intensity: RunPlanIntensity.standard,
    calibration: template.style == RunPlanTemplateStyle.runWalk
        ? null
        : _calibration,
    currentWeeklyKm: template.style == RunPlanTemplateStyle.runWalk
        ? 0
        : template.prerequisiteWeeklyKm,
    includeHills: includeHills,
    weeks: template.selectableWeeks ? template.defaultSelectableWeeks : null,
  );
  final schedule = RunPlanComposer.compose(template, config);
  final readiness = RunPlanComposer.assess(template, config);
  final weeks = <Map<String, Object?>>[];
  var totalKm = 0.0;
  var peakWeekKm = 0.0;
  var longestKm = 0.0;
  var qualitySessions = 0;

  for (var index = 0; index < schedule.length; index++) {
    final sorted = [...schedule[index]]
      ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
    final weekKm = sorted.fold<double>(
      0,
      (sum, workout) => sum + (workout.targetDistanceMeters ?? 0) / 1000,
    );
    final durationMinutes = sorted.fold<double>(
      0,
      (sum, workout) => sum + (workout.targetDurationSeconds ?? 0) / 60,
    );
    totalKm += weekKm;
    if (weekKm > peakWeekKm) peakWeekKm = weekKm;
    for (final workout in sorted) {
      final km = (workout.targetDistanceMeters ?? 0) / 1000;
      if (km > longestKm) longestKm = km;
      if (workout.kind.isQuality && workout.kind != RunWorkoutKind.race) {
        qualitySessions++;
      }
    }
    weeks.add({
      'number': index + 1,
      'phase': _phase(template, schedule, index),
      'distanceKm': _round(weekKm),
      'durationMinutes': durationMinutes.round(),
      'workouts': sorted.map(_workoutData).toList(),
    });
  }

  return {
    'sessions': sessions,
    'includeHills': includeHills,
    'days': _days(sessions).map(_weekday).toList(),
    'totalKm': _round(totalKm),
    'peakWeekKm': _round(peakWeekKm),
    'longestKm': _round(longestKm),
    'qualitySessions': qualitySessions,
    'ready': readiness.canCreate,
    'startWeeklyKm': _round(readiness.startWeeklyKm),
    'peakLongKm': _round(readiness.peakLongKm),
    'requiredLongKm': _round(readiness.requiredLongKm),
    'weeks': weeks,
  };
}

Map<String, Object?> _workoutData(RunPlanTemplateWorkout workout) => {
  'name': workout.name,
  'kind': workout.kind.value,
  'kindLabel': _kind(workout.kind),
  'day': _weekday(workout.dayOfWeek),
  'distanceKm': workout.targetDistanceMeters == null
      ? null
      : _round(workout.targetDistanceMeters! / 1000),
  'durationMinutes': workout.targetDurationSeconds == null
      ? null
      : (workout.targetDurationSeconds! / 60).round(),
  'pace': _pace(workout.targetPaceSecPerKm),
  'effort': workout.effortZone,
  'notes': workout.notes,
  'steps': workout.steps.map(_stepData).toList(),
};

Map<String, Object?> _stepData(RunPlanTemplateStep step) => {
  'role': _stepRole(step.role),
  'metric': step.metric.name,
  'value': step.value,
  'repeatCount': step.repeatCount,
  'paceMin': _pace(step.targetPaceMinSecPerKm),
  'paceMax': _pace(step.targetPaceMaxSecPerKm),
};

RunPlanIntent _intent(RunPlanTemplate template) {
  if ({
    'return',
    'return_injury',
    'walk_jog',
    'first_5k',
    'first_10k',
    'to_half',
    'first_half',
    'first_marathon',
    'habit_3x',
    'trail_intro',
    'keep_fit',
  }.contains(template.key)) {
    return RunPlanIntent.finish;
  }
  if (template.style == RunPlanTemplateStyle.performance ||
      template.raceFinish) {
    return RunPlanIntent.pb;
  }
  return RunPlanIntent.finish;
}

int _defaultSessions(RunPlanTemplate template) {
  final preferred = template.sessionsPerWeek.clamp(3, 5);
  return template.allowedSessionsPerWeek.contains(preferred)
      ? preferred
      : template.allowedSessionsPerWeek.last;
}

List<int> _days(int sessions) => switch (sessions) {
  3 => const [2, 5, 7],
  5 => const [2, 4, 5, 6, 7],
  _ => const [2, 4, 5, 7],
};

String _phase(
  RunPlanTemplate template,
  List<List<RunPlanTemplateWorkout>> schedule,
  int index,
) {
  final raceIndex =
      schedule.last.any((workout) => workout.kind == RunWorkoutKind.race)
      ? schedule.length - 1
      : -1;
  if (index == raceIndex) return 'Prova';
  final taperWeeks = raceIndex < 0
      ? 0
      : template.goalKind == RunPlanGoalKind.marathon && schedule.length >= 12
      ? 2
      : 1;
  if (raceIndex >= 0 && index >= raceIndex - taperWeeks) return 'Polimento';
  if (index > 0 && index % 4 == 3) return 'Recuperação';
  return 'Construção';
}

String _category(RunPlanTemplateCategory category) => switch (category) {
  RunPlanTemplateCategory.gettingStarted => 'Começar',
  RunPlanTemplateCategory.fiveK => '5 km',
  RunPlanTemplateCategory.tenK => '10 km',
  RunPlanTemplateCategory.half => 'Meia maratona',
  RunPlanTemplateCategory.marathon => 'Maratona',
  RunPlanTemplateCategory.conditioning => 'Condicionamento',
};

String _level(RunPlanTemplateLevel level) => switch (level) {
  RunPlanTemplateLevel.beginner => 'Iniciante',
  RunPlanTemplateLevel.intermediate => 'Intermediário',
  RunPlanTemplateLevel.advanced => 'Avançado',
};

String _kind(RunWorkoutKind kind) => switch (kind) {
  RunWorkoutKind.easy => 'Rodagem leve',
  RunWorkoutKind.long => 'Longão',
  RunWorkoutKind.tempo => 'Limiar',
  RunWorkoutKind.interval => 'Intervalado',
  RunWorkoutKind.fartlek => 'Fartlek',
  RunWorkoutKind.hills => 'Morros',
  RunWorkoutKind.progression => 'Progressivo',
  RunWorkoutKind.recovery => 'Regenerativo',
  RunWorkoutKind.race => 'Prova',
};

String _stepRole(RunStepRole role) => switch (role) {
  RunStepRole.warmup => 'Aquecimento',
  RunStepRole.work => 'Trabalho',
  RunStepRole.recovery => 'Recuperação',
  RunStepRole.steady => 'Contínuo',
  RunStepRole.cooldown => 'Desaquecimento',
};

String _weekday(int day) =>
    const ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'][day];

String? _pace(double? seconds) {
  if (seconds == null || !seconds.isFinite) return null;
  final rounded = seconds.round();
  return '${rounded ~/ 60}:${(rounded % 60).toString().padLeft(2, '0')}/km';
}

double _round(double value) => (value * 10).round() / 10;

const _page = r'''<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light dark">
  <title>Catálogo de planos de corrida</title>
  <style>
    :root {
      --bg:#f3f6f2; --surface:#fff; --soft:#edf2ec; --ink:#17221b; --muted:#627067;
      --line:#d8e1d8; --green:#13734a; --green2:#0b5133; --green-soft:#d9f3e3;
      --orange:#c16a16; --blue:#2773b8; --purple:#7759b7; --red:#b3483e;
      --shadow:0 16px 42px rgba(24,38,29,.09); --radius:18px;
    }
    @media(prefers-color-scheme:dark){:root{
      --bg:#0e1511;--surface:#172019;--soft:#202b22;--ink:#eef6ef;--muted:#abb9ae;
      --line:#334439;--green:#65d59b;--green2:#9be9bc;--green-soft:#193e2c;
      --orange:#ffb56d;--blue:#8ec5ff;--purple:#c0a9ff;--red:#ff9c92;
      --shadow:0 18px 48px rgba(0,0,0,.27)
    }}
    *{box-sizing:border-box} html{scroll-behavior:smooth} body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.55 Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif}
    button,input,select{font:inherit} button{color:inherit} .app{min-height:100vh}
    .top{padding:30px max(24px,calc((100vw - 1440px)/2));background:linear-gradient(135deg,#0b3d28,#176d49);color:#f5fff8}
    .top-inner{display:flex;justify-content:space-between;gap:28px;align-items:end;max-width:1440px;margin:auto}
    .eyebrow{font-size:11px;font-weight:800;letter-spacing:.14em;text-transform:uppercase;color:#9de7bd}
    h1{margin:6px 0 5px;font-size:clamp(30px,4vw,52px);line-height:1.04;letter-spacing:-.04em}.top p{margin:0;max-width:720px;color:#c2d9ca;font-size:16px}
    .top-stat{display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end}.top-stat span{padding:7px 10px;border:1px solid #4d8868;border-radius:999px;background:#ffffff0d;font-size:12px;font-weight:700;white-space:nowrap}
    .toolbar{position:sticky;top:0;z-index:20;padding:12px max(24px,calc((100vw - 1440px)/2));border-bottom:1px solid var(--line);background:color-mix(in srgb,var(--surface) 92%,transparent);backdrop-filter:blur(12px)}
    .toolbar-inner{max-width:1440px;margin:auto;display:grid;grid-template-columns:minmax(220px,1fr) 190px 170px 185px;gap:10px}
    .field{display:flex;align-items:center;gap:8px;padding:0 12px;border:1px solid var(--line);border-radius:11px;background:var(--soft)}
    .field input,.field select{width:100%;padding:10px 0;border:0;outline:0;background:transparent;color:var(--ink)}
    .layout{display:grid;grid-template-columns:320px minmax(0,1fr);gap:26px;max-width:1440px;margin:auto;padding:26px 24px 70px}
    .sidebar{align-self:start;position:sticky;top:82px;max-height:calc(100vh - 108px);overflow:auto;padding-right:5px}
    .result-count{margin:0 0 10px;color:var(--muted);font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.08em}
    .plan-list{display:grid;gap:9px}.plan-button{width:100%;padding:15px;border:1px solid var(--line);border-radius:14px;background:var(--surface);text-align:left;cursor:pointer;transition:.15s}
    .plan-button:hover{transform:translateY(-1px);box-shadow:0 8px 22px rgba(20,40,28,.07)}.plan-button.active{border-color:var(--green);background:var(--green-soft);box-shadow:inset 4px 0 var(--green)}
    .plan-button strong{display:block;font-size:15px}.plan-button small{display:flex;gap:7px;margin-top:5px;color:var(--muted)}
    .empty{padding:28px;border:1px dashed var(--line);border-radius:15px;color:var(--muted);text-align:center}
    .content{min-width:0}.plan-hero{padding:27px;border:1px solid var(--line);border-radius:22px;background:var(--surface);box-shadow:var(--shadow)}
    .plan-tags{display:flex;gap:7px;flex-wrap:wrap}.tag{padding:4px 8px;border-radius:7px;background:var(--soft);color:var(--muted);font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.06em}
    .plan-hero h2{margin:12px 0 5px;font-size:clamp(28px,4vw,42px);line-height:1.08;letter-spacing:-.035em}.description{margin:0;color:var(--muted);font-size:16px}.prereq{margin:17px 0 0;padding:12px 14px;border-radius:11px;background:var(--soft)}
    .config-line{display:flex;flex-wrap:wrap;gap:9px;margin-top:18px}.config-pill{padding:8px 11px;border:1px solid var(--line);border-radius:999px;background:var(--surface);font-size:12px}.config-pill b{color:var(--green2)}
    .stats{display:grid;grid-template-columns:repeat(5,1fr);gap:10px;margin:14px 0 25px}.stat{padding:15px;border:1px solid var(--line);border-radius:14px;background:var(--surface)}.stat b{display:block;color:var(--green2);font-size:24px;line-height:1.1}.stat span{display:block;margin-top:5px;color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.06em}
    .schedule-head{display:flex;justify-content:space-between;align-items:center;gap:15px;margin:0 0 12px}.schedule-head h3{margin:0;font-size:22px}.schedule-head button{padding:7px 10px;border:1px solid var(--line);border-radius:9px;background:var(--surface);cursor:pointer}
    .weeks{display:grid;gap:11px}.week{border:1px solid var(--line);border-radius:15px;background:var(--surface);overflow:hidden}.week summary{display:grid;grid-template-columns:48px 1fr auto auto;gap:12px;align-items:center;padding:15px 17px;cursor:pointer;list-style:none}.week summary::-webkit-details-marker{display:none}.week summary:before{content:"+";display:grid;place-items:center;width:29px;height:29px;border-radius:50%;background:var(--soft);color:var(--green2);font-weight:900}.week[open] summary:before{content:"−"}.week-title strong{display:block}.week-title small{color:var(--muted)}
    .phase{padding:4px 8px;border-radius:999px;background:var(--soft);color:var(--muted);font-size:11px;font-weight:800}.week-volume{min-width:70px;text-align:right;font-weight:800;color:var(--green2)}
    .sessions{display:grid;gap:1px;border-top:1px solid var(--line);background:var(--line)}.session{display:grid;grid-template-columns:56px 10px minmax(180px,1.4fr) minmax(120px,.8fr) minmax(130px,1fr);gap:13px;align-items:start;padding:15px 17px;background:var(--surface)}
    .day{font-weight:800}.kind-dot{width:9px;height:9px;margin-top:7px;border-radius:50%;background:var(--green)}.kind-dot.interval,.kind-dot.tempo{background:var(--red)}.kind-dot.hills{background:var(--orange)}.kind-dot.fartlek,.kind-dot.progression{background:var(--purple)}.kind-dot.long{background:var(--blue)}.kind-dot.race{background:#e0a400}
    .session-name strong{display:block}.session-name small{color:var(--muted)}.targets{font-weight:700}.targets small,.effort{display:block;color:var(--muted);font-weight:400}.notes{color:var(--muted);font-size:13px}.steps{grid-column:3/-1;display:flex;flex-wrap:wrap;gap:6px;margin-top:-3px}.step{padding:4px 7px;border:1px solid var(--line);border-radius:7px;background:var(--soft);font-size:11px;color:var(--muted)}
    .notice{margin:14px 0 0;padding:11px 13px;border-radius:10px;background:#fff1d9;color:#7d4b11;font-size:13px}.ready{background:var(--green-soft);color:var(--green2)}
    @media(prefers-color-scheme:dark){.notice{background:#3c2b16;color:#ffd092}.notice.ready{background:var(--green-soft);color:var(--green2)}}
    @media(max-width:1050px){.toolbar-inner{grid-template-columns:1fr 1fr}.layout{grid-template-columns:250px 1fr}.stats{grid-template-columns:repeat(3,1fr)}.session{grid-template-columns:45px 8px 1fr 140px}.notes{grid-column:3/-1}.steps{grid-column:3/-1}}
    @media(max-width:760px){.top-inner{display:block}.top-stat{justify-content:flex-start;margin-top:17px}.toolbar{position:static}.toolbar-inner{grid-template-columns:1fr}.layout{display:block;padding:18px 14px 50px}.sidebar{position:static;max-height:none;margin-bottom:16px}.plan-list{display:flex;overflow-x:auto;padding-bottom:7px}.plan-button{min-width:230px}.plan-hero{padding:20px}.stats{grid-template-columns:repeat(2,1fr)}.week summary{grid-template-columns:38px 1fr auto}.phase{display:none}.session{grid-template-columns:42px 8px 1fr}.targets,.notes,.steps{grid-column:3/-1}.week-volume{font-size:13px}}
    @media print{.top,.toolbar,.sidebar,.schedule-head button{display:none}.layout{display:block;padding:0}.plan-hero,.stat,.week{box-shadow:none}.week{break-inside:avoid}.week>.sessions{display:grid!important}}
  </style>
</head>
<body>
  <div class="app">
    <header class="top">
      <div class="top-inner">
        <div>
          <div class="eyebrow">Workout Notes · gerado pelo algoritmo real</div>
          <h1>Catálogo de planos de corrida</h1>
          <p>Explore cada modelo semana a semana, altere a frequência e compare a versão com ou sem treinos em subida.</p>
        </div>
        <div class="top-stat"><span id="model-count"></span><span id="frequency-count"></span><span>pace-base 5 km · 25:00</span></div>
      </div>
    </header>
    <div class="toolbar"><div class="toolbar-inner">
      <label class="field">⌕ <input id="search" type="search" aria-label="Buscar plano ou objetivo" placeholder="Buscar plano ou objetivo"></label>
      <label class="field"><select id="category" aria-label="Filtrar por categoria"><option value="all">Todas as categorias</option></select></label>
      <label class="field"><select id="sessions" aria-label="Frequência semanal"><option value="auto">Frequência padrão</option><option value="3">3 dias por semana</option><option value="4">4 dias por semana</option><option value="5">5 dias por semana</option></select></label>
      <label class="field"><select id="hills" aria-label="Disponibilidade de morros"><option value="true">Com treinos em subida</option><option value="false">Sem treinos em subida</option></select></label>
    </div></div>
    <div class="layout">
      <aside class="sidebar"><p class="result-count" id="count"></p><nav class="plan-list" id="plan-list"></nav></aside>
      <main class="content" id="content"></main>
    </div>
  </div>
  <script>
    const plans = __PLAN_DATA__;
    document.querySelector('#model-count').textContent = `${plans.length} modelos`;
    document.querySelector('#frequency-count').textContent = `${plans.reduce((sum,p)=>sum+p.frequencies.length/2,0)} frequências`;
    const els = {
      search: document.querySelector('#search'), category: document.querySelector('#category'),
      sessions: document.querySelector('#sessions'), hills: document.querySelector('#hills'),
      list: document.querySelector('#plan-list'), content: document.querySelector('#content'), count: document.querySelector('#count')
    };
    let selectedKey = location.hash.slice(1) || plans[0].key;
    const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const categories = [...new Map(plans.map(p => [p.categoryKey,p.category])).entries()];
    categories.forEach(([key,label]) => els.category.insertAdjacentHTML('beforeend', `<option value="${key}">${esc(label)}</option>`));
    const matching = () => {
      const q = els.search.value.trim().toLocaleLowerCase('pt-BR');
      return plans.filter(p => (els.category.value === 'all' || p.categoryKey === els.category.value) &&
        (!q || `${p.title} ${p.description} ${p.category}`.toLocaleLowerCase('pt-BR').includes(q)) &&
        (els.sessions.value === 'auto' || p.frequencies.some(f => f.sessions === Number(els.sessions.value))));
    };
    const variantFor = plan => {
      let sessions = els.sessions.value === 'auto' ? plan.defaultSessions : Number(els.sessions.value);
      if (!plan.frequencies.some(f => f.sessions === sessions)) sessions = plan.defaultSessions;
      return plan.frequencies.find(f => f.sessions === sessions && String(f.includeHills) === els.hills.value) ||
        plan.frequencies.find(f => f.sessions === sessions);
    };
    const formatKm = value => value == null ? '' : `${Number(value).toLocaleString('pt-BR',{maximumFractionDigits:1})} km`;
    const weekCount = value => `${value} ${value === 1 ? 'semana' : 'semanas'}`;
    const stepText = s => {
      const value = s.metric === 'distance' ? (s.value >= 1000 ? `${(s.value/1000).toLocaleString('pt-BR')} km` : `${s.value} m`) : `${Math.round(s.value/60)} min`;
      const repeat = s.repeatCount > 1 ? `${s.repeatCount}× ` : '';
      const pace = s.paceMin || s.paceMax ? ` · ${s.paceMin || s.paceMax}${s.paceMax && s.paceMax !== s.paceMin ? `–${s.paceMax}` : ''}` : '';
      return `${s.role}: ${repeat}${value}${pace}`;
    };
    function renderList(){
      const list = matching();
      els.count.textContent = `${list.length} ${list.length === 1 ? 'plano encontrado' : 'planos encontrados'}`;
      if (!list.some(p => p.key === selectedKey)) selectedKey = list[0]?.key;
      els.list.innerHTML = list.length ? list.map(p => `<button class="plan-button ${p.key===selectedKey?'active':''}" data-key="${p.key}"><strong>${esc(p.title)}</strong><small><span>${esc(p.category)}</span><span>·</span><span>${weekCount(p.weeks)}</span></small></button>`).join('') : '<div class="empty">Nenhum plano corresponde aos filtros.</div>';
      els.list.querySelectorAll('button').forEach(button => button.addEventListener('click', () => {selectedKey=button.dataset.key;location.hash=selectedKey;render();}));
    }
    function sessionHtml(s){
      const target = [s.distanceKm != null ? formatKm(s.distanceKm) : null,s.durationMinutes ? `${s.durationMinutes} min` : null,s.pace].filter(Boolean);
      return `<article class="session"><div class="day">${s.day}</div><span class="kind-dot ${s.kind}"></span><div class="session-name"><strong>${esc(s.name)}</strong><small>${esc(s.kindLabel)}</small></div><div class="targets">${target.map(esc).join(' · ') || 'Por esforço'}<small class="effort">${esc(s.effort || '')}</small></div><div class="notes">${esc(s.notes || '')}</div>${s.steps.length?`<div class="steps">${s.steps.map(step=>`<span class="step">${esc(stepText(step))}</span>`).join('')}</div>`:''}</article>`;
    }
    function renderContent(){
      const plan = plans.find(p => p.key === selectedKey);
      if(!plan){els.content.innerHTML='<div class="empty">Selecione um plano.</div>';return;}
      const variant = variantFor(plan);
      const intent = plan.intent === 'pb' ? 'Recorde pessoal' : 'Completar bem';
      const readiness = variant.ready ? '<div class="notice ready">✓ Esta configuração passou pela checagem de prontidão.</div>' : '<div class="notice">⚠ Esta configuração é exibida para análise, mas o wizard pediria ajustes antes de criar.</div>';
      els.content.innerHTML = `<section class="plan-hero"><div class="plan-tags"><span class="tag">${esc(plan.category)}</span><span class="tag">${esc(plan.level)}</span><span class="tag">${weekCount(plan.weeks)}</span></div><h2>${esc(plan.title)}</h2><p class="description">${esc(plan.description)}</p><p class="prereq"><strong>Pré-requisito:</strong> ${esc(plan.prerequisite)}</p><div class="config-line"><span class="config-pill"><b>${variant.sessions} dias:</b> ${variant.days.join(' · ')}</span><span class="config-pill"><b>Intenção:</b> ${intent}</span><span class="config-pill"><b>Intensidade:</b> padrão</span><span class="config-pill"><b>Morros:</b> ${variant.includeHills?'incluídos':'substituídos por fartlek'}</span></div>${readiness}</section>
      <section class="stats"><div class="stat"><b>${variant.weeks.length}</b><span>Semanas</span></div><div class="stat"><b>${formatKm(variant.totalKm)}</b><span>Volume total</span></div><div class="stat"><b>${formatKm(variant.peakWeekKm)}</b><span>Semana de pico</span></div><div class="stat"><b>${formatKm(variant.peakLongKm)}</b><span>Maior longão</span></div><div class="stat"><b>${variant.qualitySessions}</b><span>Sessões de qualidade</span></div></section>
      <div class="schedule-head"><h3>Semanas do plano</h3><button id="toggle-all">Abrir todas</button></div><section class="weeks">${variant.weeks.map((w,i)=>`<details class="week" ${i<2?'open':''}><summary><span class="week-title"><strong>Semana ${w.number}</strong><small>${variant.sessions} sessões</small></span><span class="phase">${w.phase}</span><span class="week-volume">${w.distanceKm?formatKm(w.distanceKm):`${w.durationMinutes} min`}</span></summary><div class="sessions">${w.workouts.map(sessionHtml).join('')}</div></details>`).join('')}</section>`;
      let open=false;document.querySelector('#toggle-all').addEventListener('click',e=>{open=!open;document.querySelectorAll('.week').forEach(w=>w.open=open);e.currentTarget.textContent=open?'Fechar todas':'Abrir todas';});
    }
    function render(){renderList();renderContent();}
    [els.search,els.category,els.sessions,els.hills].forEach(el=>el.addEventListener(el===els.search?'input':'change',render));
    addEventListener('hashchange',()=>{selectedKey=location.hash.slice(1)||plans[0].key;render();});
    render();
  </script>
</body>
</html>''';
