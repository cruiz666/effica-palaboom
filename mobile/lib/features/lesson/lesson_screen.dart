import 'package:flutter/material.dart';
import '../content/models/lesson.dart';
import 'exercise_widget_factory.dart';
import 'progress_repository.dart';

class LessonScreen extends StatefulWidget {
  const LessonScreen({
    super.key,
    required this.lesson,
    required this.progressRepository,
  });

  final Lesson lesson;
  final ProgressRepository progressRepository;

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  int _currentIndex = 0;
  int _correctCount = 0;
  bool _completed = false;
  String? _errorMessage;

  Future<void> _onAnswered(bool correct) async {
    if (correct) _correctCount++;
    final isLast = _currentIndex == widget.lesson.exercises.length - 1;
    if (isLast) {
      final score = _correctCount / widget.lesson.exercises.length;
      try {
        await widget.progressRepository.submitLessonResult(
          lessonId: widget.lesson.id,
          score: score,
        );
        if (!mounted) return;
        setState(() {
          _errorMessage = null;
          _completed = true;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'No se pudo guardar tu progreso. Intenta de nuevo.';
        });
      }
    } else {
      setState(() => _currentIndex++);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The pilot seed data intentionally includes a lesson with no exercises
    // yet (a shape variation). Guard against indexing into an empty list.
    if (widget.lesson.exercises.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.lesson.title)),
        body: const Center(
          child: Text('Esta lección aún no tiene ejercicios.'),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.lesson.title)),
        body: Center(child: Text(_errorMessage!)),
      );
    }

    if (_completed) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.lesson.title)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('¡Lección completada!'),
              const SizedBox(height: 8),
              Text('$_correctCount de ${widget.lesson.exercises.length} correctas'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver al curso'),
              ),
            ],
          ),
        ),
      );
    }

    final exercise = widget.lesson.exercises[_currentIndex];
    return Scaffold(
      appBar: AppBar(title: Text(widget.lesson.title)),
      body: buildExerciseWidget(
        exercise: exercise,
        onAnswered: (correct) {
          _onAnswered(correct);
        },
      ),
    );
  }
}
