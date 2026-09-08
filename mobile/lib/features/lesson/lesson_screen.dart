import 'package:flutter/material.dart';
import '../content/models/lesson.dart';
import 'widgets/multiple_choice_exercise.dart';
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

  void _onAnswered(bool correct) {
    if (correct) _correctCount++;
    final isLast = _currentIndex == widget.lesson.exercises.length - 1;
    if (isLast) {
      final score = _correctCount / widget.lesson.exercises.length;
      widget.progressRepository.submitLessonResult(
        lessonId: widget.lesson.id,
        score: score,
      );
      setState(() => _completed = true);
    } else {
      setState(() => _currentIndex++);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) {
      return const Scaffold(
        body: Center(child: Text('¡Lección completada!')),
      );
    }
    final exercise = widget.lesson.exercises[_currentIndex];
    return Scaffold(
      appBar: AppBar(title: Text(widget.lesson.title)),
      body: MultipleChoiceExercise(
        key: ValueKey(exercise.id),
        exercise: exercise,
        onAnswered: _onAnswered,
      ),
    );
  }
}
