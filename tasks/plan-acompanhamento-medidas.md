# Plan: Aba Plano → Acompanhamento (Planejamento + Medidas)

## Context & Root Cause

A aba inferior **Plano** hoje é só periodização (`PeriodizationHomeScreen`, título “Planejamento”). Medidas corporais ficam escondidas nas ferramentas do Treino (`workout_home_screen` → `BodyTrackerScreen`).

Objetivo:
1. Renomear a aba/settings para **Acompanhamento** (EN: **Tracking**).
2. Manter **Planejamento** como conteúdo principal da tela, mas com um **card compacto de Medidas no topo** (peso atual + delta + botão para abrir a tela completa).
3. Remover o atalho **Medidas** das ferramentas do Treino.

## Affected Files

- `lib/screens/workout/periodization_home_screen.dart`: AppBar → “Acompanhamento”; inserir card de medidas no topo do scroll (antes do hero do plano); section header “Planejamento” acima do conteúdo atual; carregar peso/delta via `BodyMeasurementRepository`; navegar para `BodyTrackerScreen`.
- `lib/widgets/periodization/body_measurements_teaser_card.dart` (**new**, ou private widget no home): card compacto — ícone, peso + unidade, delta vs anterior, CTA “Abrir medidas” / chevron.
- `lib/screens/workout/workout_home_screen.dart`: remover o `_NavItemData` de `workoutHomeBodyMeasurements` / `BodyTrackerScreen`.
- `lib/screens/main_shell.dart`: comentário de docs; label já vem de `loc.tabPlan` (só l10n).
- `lib/screens/workout/plan_settings_screen.dart`: labels via l10n (só strings).
- `lib/l10n/app_en.arb` + `lib/l10n/app_pt.arb`:
  - `tabPlan`: Plan → Tracking / Plano → Acompanhamento
  - `settingsPlanSectionToggle` + `Body`: Plan → Tracking / Plano → Acompanhamento
  - Novas chaves: `trackingTitle` (AppBar), `trackingBodySection` (ou reusar `progressBodyMeasurements` / `bodyTrackerTitle`), `trackingOpenMeasurements`, empty state curto se sem peso
  - Manter `periodizationTitle` = “Planejamento” / “Planning” como header da seção interna
- `test/nutrition_widget_test.dart` (stub MainShell): expectativa de texto da aba passa a ser o novo `tabPlan`
- `test/periodization_widget_test.dart`: ajustar se asserta título do AppBar como `periodizationTitle`

Sem mudança de schema/DB. `SectionsNotifier.planEnabled` e setting key podem permanecer (só copy UI).

## Implementation Checklist

### Phase 1: Localization

- [x] Atualizar `tabPlan`, `settingsPlanSectionToggle`, `settingsPlanSectionToggleBody` em EN + PT.
- [x] Adicionar chaves do teaser (título seção Medidas, CTA, empty “Sem peso registrado”, opcional label de delta).
- [x] Rodar `flutter gen-l10n`.

### Phase 2: Teaser de Medidas + home

- [x] Em `PeriodizationHomeScreen`:
  - AppBar title = `trackingTitle` (Acompanhamento / Tracking).
  - No `_load` (ou load paralelo): buscar latest weight + previous via `BodyMeasurementRepository` (`getBodyMeasurements` type weight limit 2, ou summary + previous).
  - No scroll **com plano ativo** e no empty state: card de Medidas **no topo** (antes do hero / empty periodization).
  - Abaixo do teaser, section header **Planejamento** (`periodizationTitle`) e o conteúdo atual intacto.
  - Tap no card / botão → `Navigator.push` → `BodyTrackerScreen` (mesmo padrão `AiCoachNavigation` do Treino, se aplicável).
  - `RefreshIndicator` também refresca medidas.
- [x] Empty teaser: peso ausente → copy curto + CTA para abrir medidas (ainda navega).
- [x] Visual alinhado a `PeriodizationSurface` / cards existentes (borda, radius 16, dark theme).

### Phase 3: Remover Medidas do Treino

- [x] Remover o tile Medidas do grid de ferramentas em `workout_home_screen.dart`.
- [x] Remover import morto de `body_tracker_screen.dart` se ficar unused.

### Phase 4: Validation

- [x] `flutter gen-l10n` + `flutter analyze` nos arquivos tocados.
- [x] Ajustar testes de widget que buscam `tabPlan` / título antigo.
- [ ] Manual: aba inferior mostra Acompanhamento; topo = medidas; abaixo = planejamento; ferramentas Treino sem Medidas; settings toggle com copy novo; abrir Medidas Corporais pelo CTA.

## Risks & Technical Debt

- Empty periodization + empty measures: garantir que a tela não fique só com dois empties confusos — teaser sempre no topo, empty de plano abaixo.
- `getPreviousBodyMeasurement` atual parece retornar o latest (LIMIT 1), não o anterior — para delta, preferir query dos 2 últimos pesos na home (ou corrigir o repo só se já for bug conhecido; escopo: não expandir além do teaser).
- Links para Body Tracker em Progress (`body_section_charts`) permanecem; só remove da home de Treino.
- Chave interna `planEnabled` / `tabPlan` permanece; só strings mudam — evita migração de settings.
