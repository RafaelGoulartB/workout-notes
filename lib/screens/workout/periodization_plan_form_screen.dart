import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase_draft.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/models/periodization_template.dart';
import 'package:workout_notes/periodization/periodization_phase_form_controller.dart';
import 'package:workout_notes/periodization/phase_draft_data.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/screens/workout/periodization_phase_form_screen.dart';
import 'package:workout_notes/utils/periodization_palette.dart';
import 'package:workout_notes/widgets/periodization/periodization_ui.dart';

class PeriodizationPlanFormScreen extends StatefulWidget {
  const PeriodizationPlanFormScreen({super.key});

  @override
  State<PeriodizationPlanFormScreen> createState() =>
      _PeriodizationPlanFormScreenState();
}

class _PeriodizationPlanFormScreenState
    extends State<PeriodizationPlanFormScreen> {
  final _repository = PeriodizationRepository();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final List<_EditablePhase> _phases = [];
  List<Map<String, dynamic>> _routines = const [];
  DateTime _startDate = DateTime.now();
  PeriodizationTemplate? _template = PeriodizationTemplate.cuttingBulking;
  bool _useTemplate = true;
  bool _saving = false;
  int _step = 0;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final year = DateTime.now().year;
    _nameController.text = '${_templateName(_template!)} $year';
    _rebuildTemplate();
    _loadRoutines();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadRoutines() async {
    final routines = await RoutineRepository().getRoutines();
    if (mounted) setState(() => _routines = routines);
  }

  String _templateName(PeriodizationTemplate template) {
    final loc = AppLocalizations.of(context)!;
    return switch (template.key) {
      'strength_cycle' => loc.periodizationTemplateStrength,
      'running_season' => loc.periodizationTemplateRunning,
      _ => loc.periodizationTemplateCutting,
    };
  }

  String _phaseName(String key) {
    final pt = Localizations.localeOf(context).languageCode == 'pt';
    const names = {
      'cutting': ['Cutting', 'Cutting'],
      'deload': ['Deload', 'Deload'],
      'bulking': ['Bulking controlado', 'Controlled bulking'],
      'maintenance': ['Manutenção', 'Maintenance'],
      'base': ['Base', 'Base'],
      'intensification': ['Intensificação', 'Intensification'],
      'peak': ['Pico', 'Peak'],
      'build': ['Construção', 'Build'],
      'taper': ['Polimento', 'Taper'],
      'event': ['Prova', 'Event'],
    };
    return names[key]?[pt ? 0 : 1] ?? key;
  }

  String _phaseIntent(String key) {
    final pt = Localizations.localeOf(context).languageCode == 'pt';
    const intents = {
      'gradualDeficit': ['Déficit gradual', 'Gradual deficit'],
      'recover': ['Reduzir fadiga e recuperar', 'Reduce fatigue and recover'],
      'controlledGain': ['Ganho controlado', 'Controlled gain'],
      'stabilize': ['Estabilizar resultados', 'Stabilize results'],
      'buildCapacity': [
        'Construir capacidade de trabalho',
        'Build work capacity',
      ],
      'raiseIntensity': ['Elevar a intensidade', 'Raise intensity'],
      'expressPerformance': ['Expressar performance', 'Express performance'],
      'buildAerobicBase': ['Construir base aeróbica', 'Build aerobic base'],
      'increaseSpecificLoad': [
        'Aumentar carga específica',
        'Increase specific load',
      ],
      'reduceFatigue': ['Reduzir fadiga', 'Reduce fatigue'],
      'eventWeek': ['Semana da prova', 'Event week'],
    };
    return intents[key]?[pt ? 0 : 1] ?? '';
  }

  void _rebuildTemplate() {
    _phases.clear();
    if (_useTemplate && _template != null) {
      for (final phase in _template!.phases) {
        _phases.add(
          _EditablePhase(
            name: _phaseName(phase.nameKey),
            intent: _phaseIntent(phase.intentKey),
            templateKey: phase.templateKey,
            weeks: phase.weeks,
            color: phase.color,
          ),
        );
      }
    } else {
      _phases.add(
        _EditablePhase(
          name: Localizations.localeOf(context).languageCode == 'pt'
              ? 'Primeira fase'
              : 'First phase',
          weeks: 4,
          color: kDefaultPhaseColor,
        ),
      );
    }
  }

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null && mounted) setState(() => _startDate = date);
  }

  void _selectMode(bool useTemplate) {
    setState(() {
      _useTemplate = useTemplate;
      _template = useTemplate ? PeriodizationTemplate.cuttingBulking : null;
      _rebuildTemplate();
    });
  }

  void _selectTemplate(PeriodizationTemplate template) {
    setState(() {
      _template = template;
      _nameController.text = '${_templateName(template)} ${_startDate.year}';
      _rebuildTemplate();
    });
  }

  DateTime _phaseStart(int index) {
    var date = DateTime(_startDate.year, _startDate.month, _startDate.day);
    for (var i = 0; i < index; i++) {
      date = date.add(Duration(days: _phases[i].weeks * 7));
    }
    return date;
  }

  DateTime _phaseEnd(int index) =>
      _phaseStart(index).add(Duration(days: _phases[index].weeks * 7 - 1));

  Future<void> _editPhase(int index) async {
    final source = _phases[index];
    final name = TextEditingController(text: source.name);
    final intent = TextEditingController(text: source.intent);
    final weeks = TextEditingController(text: source.weeks.toString());
    var color = source.color;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppLocalizations.of(context)!.periodizationEditPhase,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    )!.periodizationPhaseName,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: intent,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    )!.periodizationIntent,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: weeks,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.periodizationWeeks,
                    prefixIcon: const Icon(Icons.calendar_view_week_outlined),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  children: kPeriodizationColors.map((value) {
                    final selected = color == value;
                    return InkWell(
                      onTap: () => setSheetState(() => color = value),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(value),
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(color: Colors.white, width: 3)
                              : null,
                        ),
                        child: selected
                            ? const Icon(Icons.check, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: Text(AppLocalizations.of(context)!.commonSave),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == true && mounted) {
      final parsedWeeks = int.tryParse(weeks.text);
      if (name.text.trim().isNotEmpty &&
          parsedWeeks != null &&
          parsedWeeks > 0) {
        setState(() {
          source.name = name.text.trim();
          source.intent = intent.text.trim();
          source.weeks = parsedWeeks.clamp(1, 104);
          source.color = color;
          source.weeklyTargets = _fitWeeklyTargets(
            source.weeklyTargets,
            source.weeks,
          );
        });
      }
    }
  }

  Future<void> _editTargets(int index) async {
    final phase = _phases[index];
    final controller = PeriodizationPhaseFormController(
      plan: _editorPlan(),
      draftMode: true,
      draft: PeriodizationPhaseDraftData(
        name: phase.name,
        intent: phase.intent.isEmpty ? null : phase.intent,
        templateKey: phase.templateKey,
        color: phase.color,
        startDate: _phaseStart(index),
        endDate: _phaseEnd(index),
        weeklyTargets: phase.weeklyTargets,
      ),
    );
    await controller.load();
    if (!mounted) {
      controller.dispose();
      return;
    }
    final route = MaterialPageRoute<bool>(
      builder: (_) => PeriodizationPhaseFormScreen(
        plan: _editorPlan(),
        draftMode: true,
        controller: controller,
      ),
    );
    final saved = await Navigator.push<bool>(context, route);
    // The editor's widgets stay attached while the pop animation runs and
    // keep listening to the controller, so its disposal must outlive the
    // route transition.
    void disposeAfterExit() => Future<void>.delayed(
      route.transitionDuration + const Duration(milliseconds: 100),
      controller.dispose,
    );
    if (saved != true || !mounted) {
      disposeAfterExit();
      return;
    }
    final result = controller.draftData;
    disposeAfterExit();
    setState(() {
      phase.name = result.name;
      phase.intent = result.intent ?? '';
      phase.templateKey = result.templateKey;
      phase.color = result.color;
      final weeks =
          ((result.endDate.difference(result.startDate).inDays + 1) / 7)
              .ceil()
              .clamp(1, 104);
      phase.weeks = weeks;
      phase.weeklyTargets = _fitWeeklyTargets(result.weeklyTargets, weeks);
    });
  }

  PeriodizationPlan _editorPlan() => PeriodizationPlan(
    id: 'draft-plan',
    name: _nameController.text,
    startDate: _startDate,
    endDate: _startDate.add(const Duration(days: 3650)),
    status: PeriodizationPlanStatus.draft,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _phases.isEmpty) return;
    setState(() => _saving = true);
    try {
      final drafts = <PeriodizationPhaseDraft>[];
      for (var i = 0; i < _phases.length; i++) {
        final phase = _phases[i];
        drafts.add(
          PeriodizationPhaseDraft(
            name: phase.name,
            intent: phase.intent,
            templateKey: phase.templateKey,
            color: phase.color,
            startDate: _phaseStart(i),
            endDate: _phaseEnd(i),
            weeklyTargets: phase.weeklyTargets.any((target) => !target.isEmpty)
                ? phase.weeklyTargets
                : null,
          ),
        );
      }
      await _repository.createPlanWithPhases(
        name: _nameController.text,
        startDate: _startDate,
        phases: drafts,
        notes: _notesController.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.periodizationSaveError('$error'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final titles = [
      loc.periodizationStructureStep,
      loc.periodizationNextPhases,
      loc.periodizationTargets,
      loc.periodizationReviewPlan,
    ];
    final subtitles = [
      loc.periodizationStructureStepHelp,
      loc.periodizationPhasesStepHelp,
      loc.periodizationTargetsStepHelp,
      loc.periodizationReviewStepHelp,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          loc.periodizationNewPlan,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withAlpha(80),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        loc.periodizationStepOf(_step + 1, 4),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${((_step + 1) / 4 * 100).round()}%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(
                      4,
                      (index) => Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          height: 5,
                          margin: EdgeInsets.only(right: index == 3 ? 0 : 5),
                          decoration: BoxDecoration(
                            color: index <= _step
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    titles[_step],
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitles[_step],
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(.025, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: SingleChildScrollView(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  child: switch (_step) {
                    0 => _buildStructureStep(loc),
                    1 => _buildPhasesStep(loc),
                    2 => _buildTargetsStep(loc),
                    _ => _buildReviewStep(loc),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: PeriodizationBottomBar(
        secondary: _step == 0
            ? null
            : OutlinedButton(
                onPressed: _saving ? null : () => setState(() => _step--),
                child: Text(loc.periodizationBack),
              ),
        primary: FilledButton(
          onPressed: _saving ? null : _continue,
          child: _saving
              ? const SizedBox.square(
                  dimension: 19,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _step == 3
                      ? loc.periodizationCreateAndActivate
                      : loc.periodizationContinue,
                  textAlign: TextAlign.center,
                ),
        ),
      ),
    );
  }

  void _continue() {
    if (_step == 0 && !_formKey.currentState!.validate()) return;
    if (_step == 3) {
      _save();
      return;
    }
    setState(() => _step++);
  }

  Widget _buildStructureStep(AppLocalizations loc) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: _ChoiceCard(
              selected: _useTemplate,
              icon: Icons.auto_awesome_rounded,
              title: loc.periodizationUseTemplate,
              subtitle: loc.periodizationUseTemplateSubtitle,
              onTap: () => _selectMode(true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ChoiceCard(
              selected: !_useTemplate,
              icon: Icons.draw_outlined,
              title: loc.periodizationStartBlank,
              subtitle: loc.periodizationStartBlankSubtitle,
              onTap: () => _selectMode(false),
            ),
          ),
        ],
      ),
      if (_useTemplate) ...[
        const SizedBox(height: 20),
        PeriodizationSectionHeader(
          title: loc.periodizationUseTemplate,
          icon: Icons.view_carousel_outlined,
        ),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: PeriodizationTemplate.all.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final template = PeriodizationTemplate.all[index];
              return SizedBox(
                width: 240,
                child: _TemplateCard(
                  template: template,
                  name: _templateName(template),
                  selected: _template?.key == template.key,
                  onTap: () => _selectTemplate(template),
                ),
              );
            },
          ),
        ),
      ],
      const SizedBox(height: 22),
      PeriodizationSectionHeader(
        title: loc.periodizationNewPlan,
        icon: Icons.edit_note_outlined,
      ),
      PeriodizationSurface(
        child: Column(
          children: [
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: loc.periodizationPlanName,
                prefixIcon: const Icon(Icons.route_outlined),
                border: const OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? loc.periodizationPlanName
                  : null,
            ),
            const SizedBox(height: 12),
            _DateField(
              label: loc.periodizationStartDate,
              value: _startDate,
              onTap: _pickStartDate,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: loc.periodizationPlanNotes,
                alignLabelWithHint: true,
                prefixIcon: const Icon(Icons.notes_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildPhasesStep(AppLocalizations loc) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withAlpha(90),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              Icons.drag_indicator_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(loc.periodizationReorderHelp)),
          ],
        ),
      ),
      const SizedBox(height: 14),
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: _phases.length,
        onReorderItem: (oldIndex, newIndex) {
          setState(() {
            _phases.insert(newIndex, _phases.removeAt(oldIndex));
          });
        },
        itemBuilder: (context, index) {
          final phase = _phases[index];
          return Padding(
            key: ValueKey(phase),
            padding: const EdgeInsets.only(bottom: 10),
            child: PeriodizationSurface(
              accentColor: Color(phase.color),
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              onTap: () => _editPhase(index),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: Color(phase.color).withAlpha(28),
                    foregroundColor: Color(phase.color),
                    child: Text(
                      (index + 1).toString(),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          phase.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 7,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${DateFormat.MMMd(Intl.defaultLocale).format(_phaseStart(index))} – ${DateFormat.MMMd(Intl.defaultLocale).format(_phaseEnd(index))}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Color(phase.color).withAlpha(22),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                '${phase.weeks} ${loc.periodizationWeeks.toLowerCase()}',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Color(phase.color),
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        if (phase.intent.trim().isNotEmpty)
                          Text(
                            phase.intent,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: loc.commonDelete,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: _phases.length == 1
                        ? null
                        : () => setState(() => _phases.removeAt(index)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 4),
      OutlinedButton.icon(
        onPressed: () => setState(
          () => _phases.add(
            _EditablePhase(
              name: loc.periodizationNewPhase,
              weeks: 4,
              color:
                  kPeriodizationColors[_phases.length %
                      kPeriodizationColors.length],
            ),
          ),
        ),
        icon: const Icon(Icons.add_rounded),
        label: Text(loc.periodizationAddPhase),
      ),
    ],
  );

  Widget _buildTargetsStep(AppLocalizations loc) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer.withAlpha(90),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              Icons.tune_rounded,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(loc.periodizationOptionalTargets)),
          ],
        ),
      ),
      const SizedBox(height: 14),
      ...List.generate(_phases.length, (index) {
        final phase = _phases[index];
        final count = _targetCount(phase);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PeriodizationSurface(
            accentColor: Color(phase.color),
            onTap: () => _editTargets(index),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(phase.color).withAlpha(24),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.tune_rounded, color: Color(phase.color)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phase.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        count == 0
                            ? loc.periodizationNoTargetsSet
                            : _targetSummary(phase),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      count.toString(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        );
      }),
    ],
  );

  Widget _buildReviewStep(AppLocalizations loc) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.tertiaryContainer.withAlpha(150),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.event_available_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _nameController.text,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '${DateFormat.yMMMd(Intl.defaultLocale).format(_startDate)} – ${DateFormat.yMMMd(Intl.defaultLocale).format(_phaseEnd(_phases.length - 1))}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Row(
                children: [
                  for (final phase in _phases)
                    Expanded(
                      flex: phase.weeks,
                      child: Container(height: 8, color: Color(phase.color)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Row(
        children: [
          Expanded(
            child: PeriodizationSectionHeader(title: loc.periodizationPhases),
          ),
          Text(
            '${_phases.fold<int>(0, (sum, phase) => sum + phase.weeks)} ${loc.periodizationWeeks.toLowerCase()}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      ...List.generate(_phases.length, (index) {
        final phase = _phases[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PeriodizationSurface(
            accentColor: Color(phase.color),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(phase.color).withAlpha(25),
                  foregroundColor: Color(phase.color),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phase.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${phase.weeks} ${loc.periodizationWeeks.toLowerCase()} · ${_targetSummary(phase)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    ],
  );

  /// Number of distinct target blocks in the weekly list: the base target
  /// plus each week that deviates from the previous one.
  int _targetCount(_EditablePhase phase) {
    if (phase.weeklyTargets.isEmpty) return 0;
    var count = phase.weeklyTargets.first.isEmpty ? 0 : 1;
    for (var i = 1; i < phase.weeklyTargets.length; i++) {
      if (!_sameTarget(phase.weeklyTargets[i], phase.weeklyTargets[i - 1])) {
        count++;
      }
    }
    return count;
  }

  String _targetSummary(_EditablePhase phase) {
    final values = <String>[];
    PeriodizationTarget? target;
    for (final entry in phase.weeklyTargets) {
      if (!entry.isEmpty) {
        target = entry;
        break;
      }
    }
    if (target != null) {
      if (target.calories != null) {
        values.add('${target.calories!.round()} kcal');
      }
      if (target.proteinG != null) values.add('${target.proteinG!.round()}g P');
      if (target.workoutsPerWeek != null) {
        values.add('${target.workoutsPerWeek}×/sem.');
      }
      if (target.targetWeightKg != null) {
        values.add('${target.targetWeightKg} kg');
      }
      if (target.sleepHours != null) values.add('${target.sleepHours}h');
      for (final routineId in target.routineIds) {
        final match = _routines.where((routine) => routine['id'] == routineId);
        if (match.isNotEmpty) values.add(match.first['name'] as String);
      }
    }
    return values.isEmpty
        ? AppLocalizations.of(context)!.periodizationNoTargetsSet
        : values.join(' · ');
  }

  /// Truncates or extends a weekly target list to [weeks] entries. New
  /// trailing weeks inherit the last effective target so the phase keeps its
  /// configured values when its duration grows.
  static List<PeriodizationTarget> _fitWeeklyTargets(
    List<PeriodizationTarget> source,
    int weeks,
  ) {
    final resized = List<PeriodizationTarget?>.filled(weeks, null);
    PeriodizationTarget? last;
    for (var i = 0; i < weeks; i++) {
      final candidate = i < source.length ? source[i] : last;
      if (candidate != null) resized[i] = candidate;
      last = resized[i] ?? last;
    }
    return resized
        .map((target) => target ?? _EditablePhase.emptyTarget())
        .toList();
  }

  static bool _sameTarget(PeriodizationTarget? a, PeriodizationTarget? b) {
    final emptyA = a == null || a.isEmpty;
    final emptyB = b == null || b.isEmpty;
    if (emptyA && emptyB) return true;
    if (a == null || b == null) return false;
    return a.nutritionJson.toString() == b.nutritionJson.toString() &&
        a.trainingJson.toString() == b.trainingJson.toString() &&
        a.bodyJson.toString() == b.bodyJson.toString() &&
        a.sleepJson.toString() == b.sleepJson.toString();
  }
}

class _EditablePhase {
  String name;
  String intent;
  String? templateKey;
  int weeks;
  int color;

  /// One effective target per week (index 0 = first week). Entries may be
  /// empty targets when the week is undefined. The linked routine lives in
  /// each week's target (`PeriodizationTarget.routineIds`).
  List<PeriodizationTarget> weeklyTargets;

  _EditablePhase({
    required this.name,
    this.intent = '',
    this.templateKey,
    required this.weeks,
    required this.color,
    List<PeriodizationTarget>? weeklyTargets,
  }) : weeklyTargets =
           weeklyTargets ?? List.generate(weeks, (_) => emptyTarget());

  static PeriodizationTarget emptyTarget() => PeriodizationTarget(
    id: '',
    phaseId: '',
    version: 0,
    validFrom: DateTime.now(),
    createdAt: DateTime.now(),
  );
}

class _ChoiceCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PeriodizationSurface(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const Spacer(),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final PeriodizationTemplate template;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: PeriodizationSurface(
        selected: selected,
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const Spacer(),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
            const Spacer(),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                for (var i = 0; i < template.phases.length; i++) ...[
                  Expanded(
                    flex: template.phases[i].weeks,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Color(
                          kPeriodizationColors[i % kPeriodizationColors.length],
                        ),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  if (i != template.phases.length - 1) const SizedBox(width: 3),
                ],
              ],
            ),
            const SizedBox(height: 7),
            Text(
              '${template.phases.length} ${AppLocalizations.of(context)!.periodizationPhases.toLowerCase()} · ${template.phases.fold<int>(0, (sum, phase) => sum + phase.weeks)} ${AppLocalizations.of(context)!.periodizationWeeks.toLowerCase()}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 19,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat.yMMMd(Intl.defaultLocale).format(value),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.expand_more_rounded),
          ],
        ),
      ),
    );
  }
}
