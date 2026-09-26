import 'package:flutter/material.dart';
import '../content/content_repository.dart';
import '../content/models/course.dart';
import '../lesson/lesson_screen.dart';
import '../lesson/progress_repository.dart';
import '../srs/review_session_screen.dart';
import '../srs/srs_repository.dart';

class CourseScreen extends StatefulWidget {
  const CourseScreen({
    super.key,
    required this.contentRepository,
    required this.progressRepository,
    required this.srsRepository,
  });

  final ContentRepository contentRepository;
  final ProgressRepository progressRepository;
  final SrsRepository srsRepository;

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  late Future<Course> _courseFuture = widget.contentRepository.getActiveCourse();
  late final Future<int> _dueCountFuture = widget.srsRepository.getDueCount();

  void _retry() {
    final future = widget.contentRepository.getActiveCourse();
    // Mark this future's error (if any) as handled synchronously, before the
    // setState below yields control back to the event loop. Without this, if
    // the future rejects in a microtask that runs before FutureBuilder
    // resubscribes on the next build, it surfaces as an unhandled async
    // error instead of being routed through snapshot.hasError. FutureBuilder
    // still gets its own independent listener on the same future once it
    // rebuilds, so the error still reaches the UI.
    future.ignore();
    setState(() {
      _courseFuture = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Course>(
        future: _courseFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No se pudo cargar el curso.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _retry,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final course = snapshot.data!;
          final units = [...course.units]
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          return ListView(
            children: [
              FutureBuilder<int>(
                future: _dueCountFuture,
                builder: (context, dueSnapshot) {
                  final dueCount = dueSnapshot.data ?? 0;
                  return Card(
                    child: ListTile(
                      title: const Text('Repaso'),
                      subtitle: Text(
                        dueCount > 0 ? '$dueCount para repasar' : 'Sin repasos pendientes hoy',
                      ),
                      onTap: dueCount == 0
                          ? null
                          : () async {
                              final exercises = await widget.srsRepository.getDueExercises();
                              if (!context.mounted) return;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ReviewSessionScreen(
                                    exercises: exercises,
                                    srsRepository: widget.srsRepository,
                                  ),
                                ),
                              );
                            },
                    ),
                  );
                },
              ),
              for (final unit in units) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(unit.title, style: Theme.of(context).textTheme.titleLarge),
                ),
                for (final lesson in [...unit.lessons]
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
                  ListTile(
                    title: Text(lesson.title),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LessonScreen(
                          lesson: lesson,
                          progressRepository: widget.progressRepository,
                          srsRepository: widget.srsRepository,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
