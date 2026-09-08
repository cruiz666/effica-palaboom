import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/content/models/lesson.dart';
import 'package:effica_palaboom/features/lesson/lesson_screen.dart';
import 'package:effica_palaboom/features/lesson/progress_repository.dart';

class FakeProgressRepository implements ProgressRepository {
  String? lastLessonId;
  double? lastScore;

  @override
  Future<void> submitLessonResult({required String lessonId, required double score}) async {
    lastLessonId = lessonId;
    lastScore = score;
  }
}

Lesson _lesson() => const Lesson(
      id: 'lesson-1',
      title: 'Saludar y despedirse',
      sortOrder: 1,
      exercises: [
        Exercise(
          id: 'ex-1',
          sortOrder: 1,
          type: 'multiple_choice',
          content: {'prompt': 'Hola?', 'options': ['Hello', 'Goodbye']},
          correctAnswer: 'Hello',
        ),
        Exercise(
          id: 'ex-2',
          sortOrder: 2,
          type: 'multiple_choice',
          content: {'prompt': 'Adiós?', 'options': ['Hello', 'Goodbye']},
          correctAnswer: 'Goodbye',
        ),
      ],
    );

void main() {
  testWidgets('completing all exercises submits the score and shows completion', (tester) async {
    final progressRepo = FakeProgressRepository();
    await tester.pumpWidget(MaterialApp(
      home: LessonScreen(lesson: _lesson(), progressRepository: progressRepo),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goodbye'));
    await tester.pumpAndSettle();

    expect(progressRepo.lastLessonId, 'lesson-1');
    expect(progressRepo.lastScore, 1.0);
    expect(find.text('¡Lección completada!'), findsOneWidget);
  });
}
