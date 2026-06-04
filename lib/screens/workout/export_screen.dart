import 'package:flutter/material.dart';
import '../../database/database_helper.dart';
import '../../services/export_service.dart';

class ExportScreen extends StatelessWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exportService = ExportService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exportar Dados'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // JSON Backup
          _ExportCard(
            icon: Icons.backup,
            title: 'Backup Completo (JSON)',
            subtitle: 'Exporta todos os dados: treinos, exercícios, rotinas, medidas e configurações',
            color: theme.colorScheme.primary,
            onTap: () async {
              try {
                await exportService.shareJsonBackup();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Backup exportado com sucesso!'), behavior: SnackBarBehavior.floating),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erro: $e'), behavior: SnackBarBehavior.floating),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 12),

          // CSV Export
          _ExportCard(
            icon: Icons.table_chart,
            title: 'Exportar CSV',
            subtitle: 'Exporta histórico de treinos (data, exercício, peso, reps) - filtrável por exercício e data',
            color: theme.colorScheme.secondary,
            onTap: () => _showCsvExportDialog(context, exportService),
          ),
          const SizedBox(height: 12),

          // Share workout summary
          _ExportCard(
            icon: Icons.share,
            title: 'Compartilhar Resumo',
            subtitle: 'Gera um resumo de texto de um treino específico para compartilhar',
            color: theme.colorScheme.tertiary,
            onTap: () => _pickAndShareWorkout(context, exportService),
          ),
          const SizedBox(height: 24),

          // Info
          Card(
            elevation: 0,
            color: theme.colorScheme.tertiaryContainer.withAlpha(80),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.onTertiaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dicas', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          '• O backup JSON contém todos os dados do app\n'
                          '• CSV é ideal para análise em Excel/Google Sheets\n'
                          '• Os arquivos são salvos temporariamente e compartilhados via share sheet nativo',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onTertiaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showCsvExportDialog(BuildContext context, ExportService exportService) {
    final db = DatabaseHelper.instance;
    final exerciseCtl = TextEditingController();
    final startDateCtl = TextEditingController();
    final endDateCtl = TextEditingController();
    String? exerciseId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.onSurfaceVariant.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ))),
            const SizedBox(height: 16),
            Text('Exportar CSV', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: exerciseCtl,
              decoration: const InputDecoration(
                labelText: 'Exercício (opcional - vazio exporta todos)',
                border: OutlineInputBorder(),
                hintText: 'Deixe vazio para todos',
              ),
              onChanged: (v) async {
                if (v.isEmpty) {
                  exerciseId = null;
                  return;
                }
                final exercises = await db.getExercises(search: v);
                if (exercises.isNotEmpty) {
                  exerciseId = exercises.first['id'] as String;
                  exerciseCtl.text = exercises.first['name'] as String;
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: startDateCtl,
                    decoration: const InputDecoration(
                      labelText: 'Data início',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now().subtract(const Duration(days: 30)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) startDateCtl.text = date.toIso8601String().substring(0, 10);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: endDateCtl,
                    decoration: const InputDecoration(
                      labelText: 'Data fim',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) endDateCtl.text = date.toIso8601String().substring(0, 10);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  try {
                    Navigator.pop(ctx);
                    await exportService.shareCsvExport(
                      exerciseId: exerciseId,
                      startDate: startDateCtl.text.isNotEmpty ? DateTime.tryParse(startDateCtl.text) : null,
                      endDate: endDateCtl.text.isNotEmpty ? DateTime.tryParse(endDateCtl.text) : null,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('CSV exportado com sucesso!'), behavior: SnackBarBehavior.floating),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro: $e'), behavior: SnackBarBehavior.floating),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.download),
                label: const Text('Exportar CSV'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickAndShareWorkout(BuildContext context, ExportService exportService) async {
    final db = DatabaseHelper.instance;
    final workouts = await db.getWorkouts(limit: 20);

    if (workouts.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum treino para compartilhar'), behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }

    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ))),
              const SizedBox(height: 16),
              Text('Compartilhar Treino', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              SizedBox(
                height: 300,
                child: ListView.separated(
                  itemCount: workouts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctxx, i) {
                    final w = workouts[i];
                    final date = w['date'] as String? ?? '';
                    return ListTile(
                      leading: const Icon(Icons.fitness_center),
                      title: Text(date),
                      subtitle: Text(w['duration_seconds'] != null ? '${(w['duration_seconds'] as int) ~/ 60}min' : 'Em andamento'),
                      onTap: () {
                        Navigator.pop(ctx);
                        exportService.shareWorkoutSummary(w['id'] as String);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

}

class _ExportCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ExportCard({
    required this.icon, required this.title, required this.subtitle,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
