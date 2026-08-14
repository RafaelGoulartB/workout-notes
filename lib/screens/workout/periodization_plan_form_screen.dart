import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase_draft.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/models/periodization_template.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';

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
          color: 0xFF4F8EF7,
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
                  decoration: const InputDecoration(
                    labelText: 'Semanas / Weeks',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  children: _phaseColors.map((value) {
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
        });
      }
    }
  }

  Future<void> _editTargets(int index) async {
    final phase = _phases[index];
    final controllers = <String, TextEditingController>{
      'calories': _controller(phase.calories),
      'protein': _controller(phase.proteinG),
      'carbs': _controller(phase.carbsG),
      'fat': _controller(phase.fatG),
      'workouts': _controller(phase.workoutsPerWeek),
      'minSets': _controller(phase.minSetsPerWeek),
      'maxSets': _controller(phase.maxSetsPerWeek),
      'minRpe': _controller(phase.minRpe),
      'maxRpe': _controller(phase.maxRpe),
      'weight': _controller(phase.targetWeightKg),
      'change': _controller(phase.weeklyWeightChangePercent),
      'sleep': _controller(phase.sleepHours),
    };
    var routineId = phase.routineId;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .9,
          maxChildSize: .96,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            children: [
              Text(phase.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _targetSection(
                context,
                AppLocalizations.of(context)!.periodizationNutritionTargets,
                Icons.restaurant_outlined,
                [
                  _numberField(
                    controllers['calories']!,
                    AppLocalizations.of(context)!.periodizationCaloriesPerDay,
                  ),
                  _numberField(
                    controllers['protein']!,
                    AppLocalizations.of(context)!.periodizationProteinG,
                  ),
                  _numberField(
                    controllers['carbs']!,
                    AppLocalizations.of(context)!.periodizationCarbsG,
                  ),
                  _numberField(
                    controllers['fat']!,
                    AppLocalizations.of(context)!.periodizationFatG,
                  ),
                ],
              ),
              _targetSection(
                context,
                AppLocalizations.of(context)!.periodizationTrainingTargets,
                Icons.fitness_center,
                [
                  _numberField(
                    controllers['workouts']!,
                    AppLocalizations.of(context)!.periodizationWorkoutsPerWeek,
                    decimal: false,
                  ),
                  _numberField(
                    controllers['minSets']!,
                    AppLocalizations.of(context)!.periodizationMinSets,
                    decimal: false,
                  ),
                  _numberField(
                    controllers['maxSets']!,
                    AppLocalizations.of(context)!.periodizationMaxSets,
                    decimal: false,
                  ),
                  _numberField(
                    controllers['minRpe']!,
                    AppLocalizations.of(context)!.periodizationMinRpe,
                  ),
                  _numberField(
                    controllers['maxRpe']!,
                    AppLocalizations.of(context)!.periodizationMaxRpe,
                  ),
                ],
              ),
              _targetSection(
                context,
                AppLocalizations.of(context)!.periodizationBodyTargets,
                Icons.monitor_weight_outlined,
                [
                  _numberField(
                    controllers['weight']!,
                    AppLocalizations.of(context)!.periodizationTargetWeight,
                  ),
                  _numberField(
                    controllers['change']!,
                    AppLocalizations.of(
                      context,
                    )!.periodizationWeeklyWeightChange,
                  ),
                ],
              ),
              _targetSection(
                context,
                AppLocalizations.of(context)!.periodizationSleepTargets,
                Icons.nightlight_outlined,
                [
                  _numberField(
                    controllers['sleep']!,
                    AppLocalizations.of(context)!.periodizationSleepHours,
                  ),
                ],
              ),
              DropdownButtonFormField<String?>(
                initialValue: routineId,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(
                    context,
                  )!.periodizationLinkedRoutine,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      AppLocalizations.of(context)!.periodizationNoRoutine,
                    ),
                  ),
                  ..._routines.map(
                    (routine) => DropdownMenuItem<String?>(
                      value: routine['id'] as String,
                      child: Text(routine['name'] as String),
                    ),
                  ),
                ],
                onChanged: (value) => setSheetState(() => routineId = value),
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
    );
    if (result == true && mounted) {
      setState(() {
        phase.calories = _double(controllers['calories']);
        phase.proteinG = _double(controllers['protein']);
        phase.carbsG = _double(controllers['carbs']);
        phase.fatG = _double(controllers['fat']);
        phase.workoutsPerWeek = _int(controllers['workouts']);
        phase.minSetsPerWeek = _int(controllers['minSets']);
        phase.maxSetsPerWeek = _int(controllers['maxSets']);
        phase.minRpe = _double(controllers['minRpe']);
        phase.maxRpe = _double(controllers['maxRpe']);
        phase.targetWeightKg = _double(controllers['weight']);
        phase.weeklyWeightChangePercent = _double(controllers['change']);
        phase.sleepHours = _double(controllers['sleep']);
        phase.routineId = routineId;
      });
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Widget _targetSection(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> fields,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 19),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: fields),
      ],
    ),
  );

  Widget _numberField(
    TextEditingController controller,
    String label, {
    bool decimal = true,
  }) => SizedBox(
    width: 164,
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(
        decimal: decimal,
        signed: true,
      ),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
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
            routineId: phase.routineId,
            target: phase.target,
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
    return Scaffold(
      appBar: AppBar(title: Text(loc.periodizationNewPlan)),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _step,
          onStepTapped: (value) => setState(() => _step = value),
          onStepContinue: _step == 3 ? _save : () => setState(() => _step++),
          onStepCancel: _step == 0 ? null : () => setState(() => _step--),
          controlsBuilder: (context, details) => Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Row(
              children: [
                FilledButton(
                  onPressed: _saving ? null : details.onStepContinue,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _step == 3
                              ? loc.periodizationCreateAndActivate
                              : loc.periodizationReviewPlan,
                        ),
                ),
                if (_step > 0)
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: Text(loc.commonCancel),
                  ),
              ],
            ),
          ),
          steps: [
            Step(
              title: Text(loc.periodizationNewPlan),
              subtitle: Text(loc.periodizationStartChoice),
              isActive: _step >= 0,
              content: _buildStructureStep(loc),
            ),
            Step(
              title: Text(loc.periodizationNextPhases),
              isActive: _step >= 1,
              content: _buildPhasesStep(loc),
            ),
            Step(
              title: Text(loc.periodizationTargets),
              isActive: _step >= 2,
              content: _buildTargetsStep(loc),
            ),
            Step(
              title: Text(loc.periodizationReviewPlan),
              isActive: _step >= 3,
              content: _buildReviewStep(loc),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStructureStep(AppLocalizations loc) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _ChoiceCard(
        selected: _useTemplate,
        icon: Icons.auto_awesome,
        title: loc.periodizationUseTemplate,
        subtitle: loc.periodizationUseTemplateSubtitle,
        onTap: () => _selectMode(true),
      ),
      const SizedBox(height: 8),
      _ChoiceCard(
        selected: !_useTemplate,
        icon: Icons.add,
        title: loc.periodizationStartBlank,
        subtitle: loc.periodizationStartBlankSubtitle,
        onTap: () => _selectMode(false),
      ),
      if (_useTemplate) ...[
        const SizedBox(height: 14),
        RadioGroup<String>(
          groupValue: _template?.key,
          onChanged: (value) {
            if (value == null) return;
            _selectTemplate(
              PeriodizationTemplate.all.firstWhere(
                (template) => template.key == value,
              ),
            );
          },
          child: Column(
            children: PeriodizationTemplate.all
                .map(
                  (template) => RadioListTile<String>(
                    value: template.key,
                    title: Text(_templateName(template)),
                    subtitle: Text(
                      template.phases
                          .map((phase) => '${phase.weeks}w')
                          .join(' · '),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
      const SizedBox(height: 14),
      TextFormField(
        controller: _nameController,
        decoration: InputDecoration(
          labelText: loc.periodizationPlanName,
          border: const OutlineInputBorder(),
        ),
        validator: (value) => value == null || value.trim().isEmpty
            ? loc.periodizationPlanName
            : null,
      ),
      const SizedBox(height: 12),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(loc.periodizationStartDate),
        subtitle: Text(DateFormat.yMMMd(Intl.defaultLocale).format(_startDate)),
        trailing: const Icon(Icons.calendar_month_outlined),
        onTap: _pickStartDate,
      ),
      TextField(
        controller: _notesController,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: loc.periodizationPlanNotes,
          border: const OutlineInputBorder(),
        ),
      ),
    ],
  );

  Widget _buildPhasesStep(AppLocalizations loc) => Column(
    children: [
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _phases.length,
        onReorderItem: (oldIndex, newIndex) {
          setState(() {
            _phases.insert(newIndex, _phases.removeAt(oldIndex));
          });
        },
        itemBuilder: (context, index) {
          final phase = _phases[index];
          return Card(
            key: ValueKey(phase),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Color(phase.color),
                child: Text('${index + 1}'),
              ),
              title: Text(phase.name),
              subtitle: Text(
                '${DateFormat.MMMd(Intl.defaultLocale).format(_phaseStart(index))} – ${DateFormat.MMMd(Intl.defaultLocale).format(_phaseEnd(index))} · ${phase.weeks}w',
              ),
              onTap: () => _editPhase(index),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _phases.length == 1
                    ? null
                    : () => setState(() => _phases.removeAt(index)),
              ),
            ),
          );
        },
      ),
      OutlinedButton.icon(
        onPressed: () => setState(
          () => _phases.add(
            _EditablePhase(
              name: loc.periodizationNewPhase,
              weeks: 4,
              color: _phaseColors[_phases.length % _phaseColors.length],
            ),
          ),
        ),
        icon: const Icon(Icons.add),
        label: Text(loc.periodizationAddPhase),
      ),
    ],
  );

  Widget _buildTargetsStep(AppLocalizations loc) => Column(
    children: List.generate(_phases.length, (index) {
      final phase = _phases[index];
      return Card(
        child: ListTile(
          leading: Icon(Icons.tune, color: Color(phase.color)),
          title: Text(phase.name),
          subtitle: Text(
            phase.target.isEmpty
                ? loc.periodizationTargets
                : _targetSummary(phase),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _editTargets(index),
        ),
      );
    }),
  );

  Widget _buildReviewStep(AppLocalizations loc) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(_nameController.text, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        '${DateFormat.yMMMd(Intl.defaultLocale).format(_startDate)} – ${DateFormat.yMMMd(Intl.defaultLocale).format(_phaseEnd(_phases.length - 1))}',
      ),
      const SizedBox(height: 16),
      ...List.generate(_phases.length, (index) {
        final phase = _phases[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 6,
            height: 44,
            decoration: BoxDecoration(
              color: Color(phase.color),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          title: Text(phase.name),
          subtitle: Text('${phase.weeks}w · ${_targetSummary(phase)}'),
        );
      }),
    ],
  );

  String _targetSummary(_EditablePhase phase) {
    final values = <String>[];
    if (phase.calories != null) values.add('${phase.calories!.round()} kcal');
    if (phase.proteinG != null) values.add('${phase.proteinG!.round()}g P');
    if (phase.workoutsPerWeek != null) {
      values.add('${phase.workoutsPerWeek}×/w');
    }
    if (phase.targetWeightKg != null) values.add('${phase.targetWeightKg} kg');
    if (phase.sleepHours != null) values.add('${phase.sleepHours}h');
    if (phase.routineId != null) {
      final match = _routines.where(
        (routine) => routine['id'] == phase.routineId,
      );
      if (match.isNotEmpty) values.add(match.first['name'] as String);
    }
    return values.isEmpty ? '—' : values.join(' · ');
  }

  static TextEditingController _controller(num? value) =>
      TextEditingController(text: value?.toString() ?? '');
  static double? _double(TextEditingController? controller) =>
      double.tryParse(controller?.text.trim().replaceAll(',', '.') ?? '');
  static int? _int(TextEditingController? controller) =>
      int.tryParse(controller?.text.trim() ?? '');
}

class _EditablePhase {
  String name;
  String intent;
  String? templateKey;
  int weeks;
  int color;
  double? calories;
  double? proteinG;
  double? carbsG;
  double? fatG;
  int? workoutsPerWeek;
  int? minSetsPerWeek;
  int? maxSetsPerWeek;
  double? minRpe;
  double? maxRpe;
  double? targetWeightKg;
  double? weeklyWeightChangePercent;
  double? sleepHours;
  String? routineId;

  _EditablePhase({
    required this.name,
    this.intent = '',
    this.templateKey,
    required this.weeks,
    required this.color,
  });

  PeriodizationTarget get target => PeriodizationTarget(
    id: '',
    phaseId: '',
    version: 0,
    validFrom: DateTime.now(),
    calories: calories,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
    workoutsPerWeek: workoutsPerWeek,
    minSetsPerWeek: minSetsPerWeek,
    maxSetsPerWeek: maxSetsPerWeek,
    minRpe: minRpe,
    maxRpe: maxRpe,
    targetWeightKg: targetWeightKg,
    weeklyWeightChangePercent: weeklyWeightChangePercent,
    sleepHours: sleepHours,
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
    return Card(
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
        ),
      ),
    );
  }
}

const _phaseColors = <int>[
  0xFF4F8EF7,
  0xFFF5B942,
  0xFF9B6BE8,
  0xFF43B581,
  0xFFE85858,
  0xFF26A6A1,
];
