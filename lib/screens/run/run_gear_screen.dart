import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_gear.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Shoe list with mileage, wear bar and replacement hints.
class RunGearScreen extends StatefulWidget {
  const RunGearScreen({super.key});

  @override
  State<RunGearScreen> createState() => _RunGearScreenState();
}

class _RunGearScreenState extends State<RunGearScreen> {
  final _repo = DatabaseHelper.instance.runGearRepo;
  List<RunGearUsage> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _repo.listGearUsage();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _edit([RunGear? gear]) async {
    final saved = await showRunGearEditor(context, gear: gear);
    if (saved != null) await _load();
  }

  Future<void> _actions(RunGearUsage usage) async {
    final loc = AppLocalizations.of(context)!;
    final gear = usage.gear;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(loc.runGearEdit),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(
                gear.isRetired
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              title: Text(
                gear.isRetired ? loc.runGearUnretire : loc.runGearRetire,
              ),
              onTap: () => Navigator.pop(context, 'retire'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(loc.runGearDelete),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await _edit(gear);
      case 'retire':
        await _repo.setRetired(gear.id, !gear.isRetired);
        await _load();
      case 'delete':
        final confirmed = await showConfirmDialog(
          context,
          message: loc.runGearDeleteConfirm,
          confirmLabel: loc.runGearDelete,
        );
        if (confirmed == true) {
          await _repo.deleteGear(gear.id);
          await _load();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final active = _items.where((u) => !u.gear.isRetired).toList();
    final retired = _items.where((u) => u.gear.isRetired).toList();

    return Scaffold(
      appBar: AppBar(title: Text(loc.runGearTitle)),
      // The empty state already has its own "add" button.
      floatingActionButton: _loading || _items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add),
              label: Text(loc.runGearAdd),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? EmptyStatePlaceholder(
              icon: Icons.directions_walk_rounded,
              title: loc.runGearEmptyTitle,
              subtitle: loc.runGearEmptySubtitle,
              actionLabel: loc.runGearAdd,
              onAction: _edit,
            )
          : ListView(
              padding: AppUi.screenPadding,
              children: [
                for (final usage in active) ...[
                  _GearCard(usage: usage, onTap: () => _actions(usage)),
                  const SizedBox(height: 10),
                ],
                if (retired.isNotEmpty) ...[
                  AppSectionHeader(loc.runGearRetiredSection),
                  for (final usage in retired) ...[
                    _GearCard(usage: usage, onTap: () => _actions(usage)),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
    );
  }
}

class _GearCard extends StatelessWidget {
  final RunGearUsage usage;
  final VoidCallback onTap;

  const _GearCard({required this.usage, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final gear = usage.gear;
    final ratio = usage.wearRatio;
    final barColor = usage.needsReplacement
        ? colors.error
        : usage.nearingReplacement
        ? colors.tertiary
        : colors.primary;
    final lastUsed = usage.lastUsedAt == null
        ? null
        : DateFormat.yMMMd(
            Localizations.localeOf(context).toString(),
          ).format(usage.lastUsedAt!.toLocal());

    return AppSectionCard(
      onTap: onTap,
      child: Opacity(
        opacity: gear.isRetired ? 0.6 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AppIconBadge(Icons.directions_walk_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gear.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        [
                          if (gear.brand != null) gear.brand!,
                          loc.runGearRunCount(usage.runCount),
                          ?lastUsed,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (gear.isDefault)
                  AppPill(label: loc.runGearDefaultBadge)
                else if (gear.isRetired)
                  AppPill(
                    label: loc.runGearRetiredBadge,
                    color: colors.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AppValueUnit(
                  value: RunFormatters.distanceKm(usage.totalDistanceMeters),
                  unit: 'km',
                ),
                const Spacer(),
                Text(
                  loc.runGearDistanceOf(
                    '${(ratio * 100).round()}%',
                    RunFormatters.distanceWithUnit(gear.retireDistanceMeters),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: colors.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            if (!gear.isRetired && usage.nearingReplacement) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: barColor),
                  const SizedBox(width: 6),
                  Text(
                    usage.needsReplacement
                        ? loc.runGearReplaceNow
                        : loc.runGearReplaceSoon,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: barColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Add/edit sheet for a shoe. Returns the saved gear, or null if cancelled.
Future<RunGear?> showRunGearEditor(BuildContext context, {RunGear? gear}) {
  return showModalBottomSheet<RunGear>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _GearEditorSheet(gear: gear),
  );
}

class _GearEditorSheet extends StatefulWidget {
  final RunGear? gear;

  const _GearEditorSheet({this.gear});

  @override
  State<_GearEditorSheet> createState() => _GearEditorSheetState();
}

class _GearEditorSheetState extends State<_GearEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.gear?.name ?? '');
  late final _brand = TextEditingController(text: widget.gear?.brand ?? '');
  late final _initial = TextEditingController(
    text: widget.gear == null
        ? ''
        : RunFormatters.decimal(widget.gear!.initialDistanceMeters / 1000, 0),
  );
  late final _retire = TextEditingController(
    text: RunFormatters.decimal(
      (widget.gear?.retireDistanceMeters ??
              RunGear.defaultRetireDistanceMeters) /
          1000,
      0,
    ),
  );
  late bool _isDefault = widget.gear?.isDefault ?? false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _initial.dispose();
    _retire.dispose();
    super.dispose();
  }

  double? _km(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final saved = await DatabaseHelper.instance.runGearRepo.saveGear(
      id: widget.gear?.id,
      name: _name.text,
      brand: _brand.text,
      notes: widget.gear?.notes,
      initialDistanceMeters: (_km(_initial.text) ?? 0) * 1000,
      retireDistanceMeters:
          (_km(_retire.text) ?? RunGear.defaultRetireDistanceMeters / 1000) *
          1000,
      isDefault: _isDefault,
    );
    if (!mounted) return;
    Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final numberKeyboard = const TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.gear == null ? loc.runGearAdd : loc.runGearEdit,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: widget.gear == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: loc.runGearName,
                hintText: loc.runGearNameHint,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? loc.runGearNameRequired
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _brand,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: loc.runGearBrand),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _initial,
                    keyboardType: numberKeyboard,
                    decoration: InputDecoration(
                      labelText: loc.runGearInitialDistance,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _retire,
                    keyboardType: numberKeyboard,
                    decoration: InputDecoration(
                      labelText: loc.runGearRetireDistance,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isDefault,
              onChanged: (value) => setState(() => _isDefault = value),
              title: Text(loc.runGearDefault),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(loc.runGearSave),
            ),
          ],
        ),
      ),
    );
  }
}
