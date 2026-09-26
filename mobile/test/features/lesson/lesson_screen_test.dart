import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/content/models/lesson.dart';
import 'package:effica_palaboom/features/lesson/lesson_screen.dart';
import 'package:effica_palaboom/features/lesson/progress_repository.dart';

class FakeProgressRepository implements ProgressRepository {
  FakeProgressRepository({this.shouldThrow = false});

  final bool shouldThrow;
  String? lastLessonId;
  double? lastScore;

  @override
  Future<void> submitLessonResult({required String lessonId, required double score}) async {
    if (shouldThrow) {
      throw Exception('submission failed');
    }
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
    // Finding #5: completion screen keeps the AppBar, shows the score, and
    // offers a way back to the course instead of being a visual dead end.
    expect(find.widgetWithText(AppBar, 'Saludar y despedirse'), findsOneWidget);
    expect(find.text('2 de 2 correctas'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Volver al curso'), findsOneWidget);
  });

  testWidgets('opening a lesson with no exercises shows a friendly message instead of crashing',
      (tester) async {
    const emptyLesson = Lesson(
      id: 'lesson-empty',
      title: 'Presentarse',
      sortOrder: 2,
      exercises: [],
    );

    await tester.pumpWidget(MaterialApp(
      home: LessonScreen(lesson: emptyLesson, progressRepository: FakeProgressRepository()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Esta lección aún no tiene ejercicios.'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Presentarse'), findsOneWidget);
  });

  testWidgets('a failed progress submission shows an error instead of a false completion',
      (tester) async {
    final progressRepo = FakeProgressRepository(shouldThrow: true);
    await tester.pumpWidget(MaterialApp(
      home: LessonScreen(lesson: _lesson(), progressRepository: progressRepo),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goodbye'));
    await tester.pumpAndSettle();

    expect(find.text('¡Lección completada!'), findsNothing);
    expect(find.text('No se pudo guardar tu progreso. Intenta de nuevo.'), findsOneWidget);
  });
}
