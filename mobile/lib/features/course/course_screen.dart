import 'package:flutter/material.dart';
import '../content/content_repository.dart';
import '../content/models/course.dart';
import '../lesson/lesson_screen.dart';
import '../lesson/progress_repository.dart';

class CourseScreen extends StatefulWidget {
  const CourseScreen({
    super.key,
    required this.contentRepository,
    required this.progressRepository,
  });

  final ContentRepository contentRepository;
  final ProgressRepository progressRepository;

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  late final Future<Course> _courseFuture = widget.contentRepository.getActiveCourse();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Course>(
        future: _courseFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final course = snapshot.data!;
          return ListView(
            children: [
              for (final unit in course.units) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(unit.title, style: Theme.of(context).textTheme.titleLarge),
                ),
                for (final lesson in unit.lessons)
                  ListTile(
                    title: Text(lesson.title),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LessonScreen(
                          lesson: lesson,
                          progressRepository: widget.progressRepository,
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
