# Melhorias de UI/UX — Workout Notes

As melhorias abaixo foram implementadas após percorrer os principais fluxos do aplicativo no emulador Android. O escopo priorizou clareza dos dados, ações diretas, consistência visual e textos que descrevem com precisão o estado atual.

## Plano executado

1. **Corrigir informações e indicadores**: evitar sequência de treinos desatualizada, mostrar o volume das categorias de exercício e deixar explícito qual meta nutricional está em uso.
2. **Reduzir passos nos fluxos frequentes**: iniciar um dia de rotina ou um treino planejado diretamente pela tela correspondente.
3. **Melhorar leitura e orientação**: explicar os marcadores do calendário, remover resultados repetidos na busca de alimentos e permitir que rótulos da tela inicial quebrem linha.
4. **Padronizar textos e estados**: usar unidades localizadas, distinguir horário de despertar planejado de um alarme configurado e retirar ação de compartilhamento indisponível.
5. **Validar e registrar**: gerar traduções EN/PT, analisar e compilar o app e salvar capturas pareadas antes/depois.

## Melhorias implementadas

### Indicadores e dados

- A sequência de treinos agora zera quando o último treino ocorreu há mais de um dia, em vez de exibir uma sequência antiga como atual.
- O painel de volume por categoria das rotinas agora acumula os valores corretamente.
- As configurações de nutrição mostram a meta efetiva do plano ativo para o diário e identificam a meta base separadamente.

### Fluxos e usabilidade

- Cada dia de uma rotina tem uma ação direta para iniciar o treino.
- O editor de treino futuro oferece “Começar este treino”, junto de “Adicionar exercício”.
- A busca de alimentos elimina duplicatas entre favoritos, sugestões e itens recentes.
- O calendário explica visualmente os marcadores de treino, corrida concluída e corrida planejada.
- Os rótulos de estatística da tela inicial podem ocupar duas linhas, evitando cortes em telas estreitas.

### Consistência visual e de conteúdo

- Os campos de peso usam o rótulo traduzido e a unidade correspondente, em vez de texto português fixo em tabelas de treino.
- A tela de sono informa que o horário de despertar está planejado; não sugere que já existe um alarme configurado. O horário anterior de 6h30 foi restaurado no emulador após a inspeção.
- Foi removido o ícone de compartilhamento desativado da revisão de corrida.
- Os novos textos foram adicionados em inglês e português brasileiro.

## Capturas pareadas

As imagens estão em `report/uiux_before/` e `report/uiux_after/`.

| Fluxo | Antes | Depois | O que mudou |
|---|---|---|---|
| Início e sequência de treinos | [Imagem](uiux_before/workout_home.png) | [Imagem](uiux_after/workout_home.png) | Indicador de sequência atualizado e rótulo sem corte. |
| Dias de rotina | [Imagem](uiux_before/routine_days.png) | [Imagem](uiux_after/routine_days.png) | Volume corrigido e ação direta para iniciar cada dia. |
| Treino planejado | [Imagem](uiux_before/future_workout_start.png) | [Imagem](uiux_after/future_workout_start.png) | Nova ação para começar o treino futuro. |
| Configurações de nutrição | [Imagem](uiux_before/nutrition_settings.png) | [Imagem EN](uiux_after/nutrition_settings.png) · [Imagem PT-BR](uiux_after/nutrition_settings_pt.png) | Metas efetivas e base identificadas claramente. |
| Calendário | [Imagem](uiux_before/calendar_legend.png) | [Imagem](uiux_after/calendar_legend.png) | Legenda para os tipos de atividade. |
| Busca de alimentos | [Imagem](uiux_before/food_search.png) | [Imagem](uiux_after/food_search.png) | Resultados repetidos removidos. |
| Monitor de sono | [Imagem](uiux_before/sleep_monitor_ready.png) | [Imagem](uiux_after/sleep_monitor_ready.png) | Texto indica horário planejado, mantendo o despertar em 6h30. |
| Exercícios e unidades | [Imagem](uiux_before/active_workout_labels.png) | [Imagem](uiux_after/active_workout_labels.png) | Colunas localizadas, incluindo peso em kg. |

## Validação

- `flutter gen-l10n` — concluído.
- `flutter analyze` — concluído sem problemas.
- `flutter build apk --debug` — concluído; APK instalado e aberto no emulador.
- Testes automatizados não foram executados.
