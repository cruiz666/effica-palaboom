import 'package:flutter/material.dart';
import 'progress_summary_repository.dart';
import 'unit_progress_summary.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.progressSummaryRepository});

  final ProgressSummaryRepository progressSummaryRepository;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late final Future<List<UnitProgressSummary>> _summariesFuture =
      widget.progressSummaryRepository.getUnitProgressSummaries();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tu progreso')),
      body: FutureBuilder<List<UnitProgressSummary>>(
        future: _summariesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('No se pudo cargar tu progreso.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final summaries = snapshot.data!;
          return ListView(
            children: [
              for (final s in summaries)
                ListTile(
                  title: Text(s.unitTitle),
                  subtitle: Text(
                    '${s.completedLessons}/${s.totalLessons} lecciones · '
                    '${s.learnedItems}/${s.totalLearningItems} aprendidas · '
                    '${s.dueTodayItems} para repasar hoy',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
