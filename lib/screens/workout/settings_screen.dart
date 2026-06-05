import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/database_helper.dart';
import '../../database/test_seed_data.dart';
import '../../services/export_service.dart';
import '../../services/notification_service.dart';
import '../../main.dart';

class WorkoutSettingsScreen extends StatefulWidget {
  const WorkoutSettingsScreen({super.key});

  @override
  State<WorkoutSettingsScreen> createState() => _WorkoutSettingsScreenState();
}

class _WorkoutSettingsScreenState extends State<WorkoutSettingsScreen> {
  final _db = DatabaseHelper.instance;
  Map<String, String> _settings = {};
  bool _isLoading = true;
  int _selectedAccentIndex = AccentColors.indexOf(AccentColors.defaultColor);

  @override
  void initState() {
    super.initState();
    _selectedAccentIndex = AccentColors.indexOf(
      LifeNotesApp.themeNotifier.seedColor,
    );
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

  Future<void> _changeAccentColor(int index) async {
    final color = AccentColors.options[index];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accent_color', color.value);
    setState(() => _selectedAccentIndex = index);
    LifeNotesApp.themeNotifier.setSeedColor(color);
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

  Future<void> _generateTestData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gerar Dados de Teste?'),
        content: const Text('Isso vai adicionar treinos fictícios nos últimos meses para testar gráficos e funcionalidades.\n\nUse "Excluir Todo Histórico" para remover depois.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gerar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      final generator = TestDataGenerator();
      final count = await generator.generate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ $count treinos gerados!'), behavior: SnackBarBehavior.floating),
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
                // Accent Color
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.palette, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text('Cor do Tema', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: List.generate(AccentColors.options.length, (i) {
                            final isSelected = _selectedAccentIndex == i;
                            final color = AccentColors.options[i];
                            return GestureDetector(
                              onTap: () => _changeAccentColor(i),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(12),
                                  border: isSelected
                                      ? Border.all(color: theme.colorScheme.onSurface, width: 2.5)
                                      : Border.all(color: color.withAlpha(120), width: 1),
                                  boxShadow: isSelected
                                      ? [BoxShadow(color: color.withAlpha(100), blurRadius: 8, spreadRadius: 1)]
                                      : null,
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                                    : null,
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AccentColors.labels[_selectedAccentIndex],
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

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
                        child: Row(
                          children: [
                            Icon(Icons.straighten, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text('Unidades', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
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
                        child: Row(
                          children: [
                            Icon(Icons.timer, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text('Temporizador', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
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
                      SwitchListTile(
                        title: const Text('Timer de Treino Automático'),
                        subtitle: const Text('Iniciar timer ao completar a 1ª série, parar ao finalizar a última'),
                        value: _settings['auto_start_workout_timer'] == 'true',
                        onChanged: (v) => _update('auto_start_workout_timer', v.toString()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Notifications
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
                        child: Row(
                          children: [
                            Icon(Icons.notifications, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text('Notificações', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),

                      // ── Rest Timer Notification ──
                      SwitchListTile(
                        title: const Text('Timer de Descanso'),
                        subtitle: const Text('Notificação do temporizador entre séries'),
                        value: _settings['notification_rest_timer_enabled'] != 'false',
                        onChanged: (v) {
                          _update('notification_rest_timer_enabled', v.toString());
                          NotificationService.instance.loadSettings();
                        },
                      ),
                      if (_settings['notification_rest_timer_enabled'] != 'false') ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Row(
                            children: [
                              Icon(Icons.notifications_active, size: 16, color: theme.colorScheme.onSurfaceVariant.withAlpha(120)),
                              const SizedBox(width: 8),
                              Text('Opções de alerta', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('Som'),
                          subtitle: const Text('Tocar som ao iniciar e finalizar o descanso'),
                          value: _settings['notification_rest_timer_sound'] != 'false',
                          onChanged: (v) {
                            _update('notification_rest_timer_sound', v.toString());
                            NotificationService.instance.loadSettings();
                          },
                        ),
                        SwitchListTile(
                          title: const Text('Vibração'),
                          subtitle: const Text('Vibrar ao iniciar e finalizar o descanso'),
                          value: _settings['notification_rest_timer_vibration'] != 'false',
                          onChanged: (v) {
                            _update('notification_rest_timer_vibration', v.toString());
                            NotificationService.instance.loadSettings();
                          },
                        ),
                      ],
                      const Divider(height: 1, indent: 16, endIndent: 16),

                      // ── Workout Timer Notification ──
                      SwitchListTile(
                        title: const Text('Timer de Treino'),
                        subtitle: const Text('Notificação do cronômetro do treino ativo'),
                        value: _settings['notification_workout_timer_enabled'] != 'false',
                        onChanged: (v) {
                          _update('notification_workout_timer_enabled', v.toString());
                          NotificationService.instance.loadSettings();
                        },
                      ),
                      if (_settings['notification_workout_timer_enabled'] != 'false') ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Row(
                            children: [
                              Icon(Icons.notifications_active, size: 16, color: theme.colorScheme.onSurfaceVariant.withAlpha(120)),
                              const SizedBox(width: 8),
                              Text('Opções de alerta', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('Som'),
                          subtitle: const Text('Tocar som ao iniciar o treino'),
                          value: _settings['notification_workout_timer_sound'] == 'true',
                          onChanged: (v) {
                            _update('notification_workout_timer_sound', v.toString());
                            NotificationService.instance.loadSettings();
                          },
                        ),
                        SwitchListTile(
                          title: const Text('Vibração'),
                          subtitle: const Text('Vibrar ao iniciar o treino'),
                          value: _settings['notification_workout_timer_vibration'] == 'true',
                          onChanged: (v) {
                            _update('notification_workout_timer_vibration', v.toString());
                            NotificationService.instance.loadSettings();
                          },
                        ),
                      ],
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
                        child: Row(
                          children: [
                            Icon(Icons.visibility, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text('Tela', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
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
                        child: Row(
                          children: [
                            Icon(Icons.storage, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text('Dados', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      ListTile(
                        leading: Icon(Icons.download, color: theme.colorScheme.primary),
                        title: const Text('Exportar Backup'),
                        subtitle: const Text('JSON completo para salvar ou transferir'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _exportBackup(),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: Icon(Icons.bug_report, color: theme.colorScheme.secondary),
                        title: const Text('Gerar Dados de Teste'),
                        subtitle: const Text('Adiciona treinos fictícios para testar o app'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _generateTestData(),
                      ),
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
