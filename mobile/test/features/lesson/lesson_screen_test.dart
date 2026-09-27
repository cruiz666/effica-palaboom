import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/content/models/lesson.dart';
import 'package:effica_palaboom/features/lesson/lesson_screen.dart';
import 'package:effica_palaboom/features/lesson/progress_repository.dart';
import 'package:effica_palaboom/features/srs/srs_repository.dart';
import 'package:effica_palaboom/features/gamification/gamification_repository.dart';
import 'package:effica_palaboom/features/gamification/gamification_state.dart';

class FakeGamificationRepository implements GamificationRepository {
  final xpAwards = <int>[];
  bool activityRecorded = false;

  @override
  Future<GamificationState> getState() async =>
      const GamificationState(xpTotal: 0, currentStreak: 0, longestStreak: 0, level: 1);

  @override
  Future<void> awardXp(int amount) async {
    xpAwards.add(amount);
  }

  @override
  Future<void> recordActivity() async {
    activityRecorded = true;
  }
}

class FakeSrsRepository implements SrsRepository {
  FakeSrsRepository({this.shouldThrow = false});

  final bool shouldThrow;
  final calls = <(String, bool)>[];

  @override
  Future<int> getDueCount() async => 0;

  @override
  Future<List<Exercise>> getDueExercises() async => const [];

  @override
  Future<void> submitReviewResult({required String learningItemId, required bool correct}) async {
    if (shouldThrow) {
      throw Exception('SRS backend unavailable');
    }
    calls.add((learningItemId, correct));
  }
}

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
          learningItemIds: ['li-1'],
        ),
        Exercise(
          id: 'ex-2',
          sortOrder: 2,
          type: 'multiple_choice',
          content: {'prompt': 'Adiós?', 'options': ['Hello', 'Goodbye']},
          correctAnswer: 'Goodbye',
          learningItemIds: ['li-2'],
        ),
      ],
    );

Lesson _lessonForErrorLimit() => const Lesson(
      id: 'lesson-limit',
      title: 'Práctica larga',
      sortOrder: 1,
      exercises: [
        Exercise(id: 'ex-1', sortOrder: 1, type: 'multiple_choice', content: {'prompt': 'p1', 'options': ['A', 'B']}, correctAnswer: 'A'),
        Exercise(id: 'ex-2', sortOrder: 2, type: 'multiple_choice', content: {'prompt': 'p2', 'options': ['A', 'B']}, correctAnswer: 'A'),
        Exercise(id: 'ex-3', sortOrder: 3, type: 'multiple_choice', content: {'prompt': 'p3', 'options': ['A', 'B']}, correctAnswer: 'A'),
        Exercise(id: 'ex-4', sortOrder: 4, type: 'multiple_choice', content: {'prompt': 'p4', 'options': ['A', 'B']}, correctAnswer: 'A'),
      ],
    );

void main() {
  testWidgets('completing all exercises submits the score and shows completion', (tester) async {
    final progressRepo = FakeProgressRepository();
    final srsRepo = FakeSrsRepository();
    final gamificationRepo = FakeGamificationRepository();
    await tester.pumpWidget(MaterialApp(
      home: LessonScreen(lesson: _lesson(), progressRepository: progressRepo, srsRepository: srsRepo, gamificationRepository: gamificationRepo),
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
    expect(srsRepo.calls, [
      ('li-1', true),
      ('li-2', true),
    ]);
    expect(gamificationRepo.xpAwards, [10, 10]);
    expect(gamificationRepo.activityRecorded, true);
  });

  testWidgets(
      'a throwing SRS repository never blocks or breaks lesson completion',
      (tester) async {
    final progressRepo = FakeProgressRepository();
    final srsRepo = FakeSrsRepository(shouldThrow: true);
    final gamificationRepo = FakeGamificationRepository();
    await tester.pumpWidget(MaterialApp(
      home: LessonScreen(lesson: _lesson(), progressRepository: progressRepo, srsRepository: srsRepo, gamificationRepository: gamificationRepo),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goodbye'));
    await tester.pumpAndSettle();

    expect(progressRepo.lastLessonId, 'lesson-1');
    expect(find.text('¡Lección completada!'), findsOneWidget);
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
      home: LessonScreen(lesson: emptyLesson, progressRepository: FakeProgressRepository(), srsRepository: FakeSrsRepository(), gamificationRepository: FakeGamificationRepository()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Esta lección aún no tiene ejercicios.'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Presentarse'), findsOneWidget);
  });

  testWidgets('a failed progress submission shows an error instead of a false completion',
      (tester) async {
    final progressRepo = FakeProgressRepository(shouldThrow: true);
    await tester.pumpWidget(MaterialApp(
      home: LessonScreen(lesson: _lesson(), progressRepository: progressRepo, srsRepository: FakeSrsRepository(), gamificationRepository: FakeGamificationRepository()),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goodbye'));
    await tester.pumpAndSettle();

    expect(find.text('¡Lección completada!'), findsNothing);
    expect(find.text('No se pudo guardar tu progreso. Intenta de nuevo.'), findsOneWidget);
  });

  testWidgets('reaching the error limit ends the session before it completes', (tester) async {
    final progressRepo = FakeProgressRepository();
    final gamificationRepo = FakeGamificationRepository();
    await tester.pumpWidget(MaterialApp(
      home: LessonScreen(
        lesson: _lessonForErrorLimit(),
        progressRepository: progressRepo,
        srsRepository: FakeSrsRepository(),
        gamificationRepository: gamificationRepo,
      ),
    ));

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();

    expect(find.text('Alcanzaste el límite de errores para esta sesión.'), findsOneWidget);
    expect(find.text('p4'), findsNothing);
    expect(progressRepo.lastLessonId, isNull);
    expect(gamificationRepo.activityRecorded, false);
  });
}
