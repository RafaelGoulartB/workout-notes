import 'package:flutter/material.dart';
import '../../database/database_helper.dart';
import '../../services/export_service.dart';

class WorkoutSettingsScreen extends StatefulWidget {
  const WorkoutSettingsScreen({super.key});

  @override
  State<WorkoutSettingsScreen> createState() => _WorkoutSettingsScreenState();
}

class _WorkoutSettingsScreenState extends State<WorkoutSettingsScreen> {
  final _db = DatabaseHelper.instance;
  Map<String, String> _settings = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _settings = await _db.getAllSettings();
    setState(() => _isLoading = false);
  }

  Future<void> _update(String key, String value) async {
    await _db.setSetting(key, value);
    _settings[key] = value;
    setState(() {});
  }

  Future<void> _exportBackup() async {
    final exportService = ExportService();
    try {
      await exportService.shareJsonBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Backup exportado!'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  // Future<void> _importBackup() async {
  //   try {
  //     final result = await FilePicker.platform.pickFiles(
  //       type: FileType.custom,
  //       allowedExtensions: ['json'],
  //     );
  //     if (result == null || result.files.isEmpty) return;

  //     final filePath = result.files.first.path;
  //     if (filePath == null) return;

  //     final exportService = ExportService();
  //     final count = await exportService.importFromJson(filePath);
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text('✅ $count registros importados!'), behavior: SnackBarBehavior.floating),
  //       );
  //       _load();
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text('Erro ao importar: $e'), behavior: SnackBarBehavior.floating),
  //       );
  //     }
  //   }
  // }

  Future<void> _deleteAllHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Todo Histórico?'),
        content: const Text('Todos os treinos, séries e exercícios registrados serão apagados. Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir Tudo', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _db.deleteAllWorkoutData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Histórico excluído'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Unit system
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text('Unidades', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      SwitchListTile(
                        title: const Text('Sistema de Unidades'),
                        subtitle: Text(_settings['unit_system'] == 'kg' ? 'kg / cm' : 'lbs / in'),
                        value: _settings['unit_system'] == 'kg',
                        onChanged: (v) => _update('unit_system', v ? 'kg' : 'lbs'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Rest timer defaults
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text('Temporizador', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      ListTile(
                        title: const Text('Descanso Padrão'),
                        subtitle: Text('${_settings['default_rest_time'] ?? '90'} segundos'),
                        trailing: SizedBox(
                          width: 100,
                          child: DropdownButtonFormField<int>(
                            value: int.tryParse(_settings['default_rest_time'] ?? '90') ?? 90,
                            items: const [30, 45, 60, 90, 120, 180].map((s) => DropdownMenuItem(
                              value: s, child: Text(s >= 60 ? '${s ~/ 60}min' : '${s}s'),
                            )).toList(),
                            onChanged: (v) => _update('default_rest_time', v.toString()),
                            decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                          ),
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('Auto-iniciar Timer'),
                        subtitle: const Text('Iniciar automaticamente após cada série'),
                        value: _settings['auto_start_rest_timer'] == 'true',
                        onChanged: (v) => _update('auto_start_rest_timer', v.toString()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Display
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text('Tela', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      SwitchListTile(
                        title: const Text('Manter Tela Ligada'),
                        subtitle: const Text('Durante o treino'),
                        value: _settings['keep_screen_on'] == 'true',
                        onChanged: (v) => _update('keep_screen_on', v.toString()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Data management
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text('Dados', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      ListTile(
                        leading: Icon(Icons.download, color: theme.colorScheme.primary),
                        title: const Text('Exportar Backup'),
                        subtitle: const Text('JSON completo para salvar ou transferir'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _exportBackup(),
                      ),
                      // const Divider(height: 1, indent: 16, endIndent: 16),
                      // ListTile(
                      //   leading: Icon(Icons.upload, color: theme.colorScheme.secondary),
                      //   title: const Text('Importar Backup'),
                      //   subtitle: const Text('Restaurar dados de um arquivo JSON'),
                      //   trailing: const Icon(Icons.chevron_right),
                      //   onTap: () => _importBackup(),
                      // ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
                        title: const Text('Sobre'),
                        subtitle: const Text('Life Notes Workout v1.0'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Danger zone
                Center(
                  child: TextButton.icon(
                    onPressed: _deleteAllHistory,
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text('Excluir Todo Histórico de Treinos', style: TextStyle(color: Colors.red)),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}
