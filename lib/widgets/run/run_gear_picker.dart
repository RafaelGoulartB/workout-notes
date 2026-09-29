import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_gear.dart';
import 'package:workout_notes/screens/run/run_gear_screen.dart';
import 'package:workout_notes/utils/run_formatters.dart';

/// Result of [showRunGearPicker]: `cleared` means "no shoes" was chosen.
class RunGearChoice {
  final RunGear? gear;

  const RunGearChoice(this.gear);

  bool get cleared => gear == null;
}

/// Bottom sheet listing active shoes. Returns null when dismissed.
Future<RunGearChoice?> showRunGearPicker(
  BuildContext context, {
  String? selectedGearId,
}) {
  return showModalBottomSheet<RunGearChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _GearPickerSheet(selectedGearId: selectedGearId),
  );
}

class _GearPickerSheet extends StatefulWidget {
  final String? selectedGearId;

  const _GearPickerSheet({this.selectedGearId});

  @override
  State<_GearPickerSheet> createState() => _GearPickerSheetState();
}

class _GearPickerSheetState extends State<_GearPickerSheet> {
  List<RunGearUsage>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await DatabaseHelper.instance.runGearRepo.listGearUsage(
      includeRetired: false,
    );
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final items = _items;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: items == null
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      loc.runGearPickerTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.block),
                    title: Text(loc.runGearNone),
                    trailing: widget.selectedGearId == null
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () =>
                        Navigator.pop(context, const RunGearChoice(null)),
                  ),
                  for (final usage in items)
                    ListTile(
                      leading: const Icon(Icons.directions_walk_rounded),
                      title: Text(usage.gear.name),
                      subtitle: Text(
                        RunFormatters.distanceWithUnit(
                          usage.totalDistanceMeters,
                        ),
                      ),
                      trailing: usage.gear.id == widget.selectedGearId
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () =>
                          Navigator.pop(context, RunGearChoice(usage.gear)),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: Text(
                      items.isEmpty ? loc.runGearAdd : loc.runGearManage,
                    ),
                    onTap: () async {
                      if (items.isEmpty) {
                        final created = await showRunGearEditor(context);
                        if (created != null && context.mounted) {
                          Navigator.pop(context, RunGearChoice(created));
                        }
                        return;
                      }
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RunGearScreen(),
                        ),
                      );
                      await _load();
                    },
                  ),
                ],
              ),
      ),
    );
  }
}
