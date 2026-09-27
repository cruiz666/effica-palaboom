import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/gamification/gamification_repository.dart';
import 'package:effica_palaboom/features/gamification/gamification_state.dart';
import 'package:effica_palaboom/features/srs/review_session_screen.dart';
import 'package:effica_palaboom/features/srs/srs_repository.dart';

class FakeSrsRepository implements SrsRepository {
  bool shouldFail = false;
  final calls = <String>[];

  @override
  Future<int> getDueCount() async => 0;

  @override
  Future<List<Exercise>> getDueExercises() async => const [];

  @override
  Future<void> submitReviewResult({required String learningItemId, required bool correct}) async {
    if (shouldFail) throw Exception('network error');
    calls.add(learningItemId);
  }
}

class FakeGamificationRepository implements GamificationRepository {
  bool shouldThrow = false;
  final xpAwards = <int>[];
  bool activityRecorded = false;

  @override
  Future<GamificationState> getState() async =>
      const GamificationState(xpTotal: 0, currentStreak: 0, longestStreak: 0, level: 1);

  @override
  Future<void> awardXp(int amount) async {
    if (shouldThrow) throw Exception('gamification backend unavailable');
    xpAwards.add(amount);
  }

  @override
  Future<void> recordActivity() async {
    if (shouldThrow) throw Exception('gamification backend unavailable');
    activityRecorded = true;
  }
}

List<Exercise> _exercises() => const [
      Exercise(
        id: 'ex-1',
        sortOrder: 1,
        type: 'multiple_choice',
        content: {'prompt': 'Hola?', 'options': ['Hello', 'Goodbye']},
        correctAnswer: 'Hello',
        learningItemIds: ['li-1'],
      ),
    ];

List<Exercise> _exercisesForErrorLimit() => const [
      Exercise(id: 'ex-1', sortOrder: 1, type: 'multiple_choice', content: {'prompt': 'p1', 'options': ['Hello', 'Goodbye']}, correctAnswer: 'Hello', learningItemIds: ['li-1']),
      Exercise(id: 'ex-2', sortOrder: 2, type: 'multiple_choice', content: {'prompt': 'p2', 'options': ['Hello', 'Goodbye']}, correctAnswer: 'Hello', learningItemIds: ['li-2']),
      Exercise(id: 'ex-3', sortOrder: 3, type: 'multiple_choice', content: {'prompt': 'p3', 'options': ['Hello', 'Goodbye']}, correctAnswer: 'Hello', learningItemIds: ['li-3']),
      Exercise(id: 'ex-4', sortOrder: 4, type: 'multiple_choice', content: {'prompt': 'p4', 'options': ['Hello', 'Goodbye']}, correctAnswer: 'Hello', learningItemIds: ['li-4']),
    ];

void main() {
  testWidgets('answering the only due exercise completes the session', (tester) async {
    final repo = FakeSrsRepository();
    final gamificationRepo = FakeGamificationRepository();
    await tester.pumpWidget(MaterialApp(
      home: ReviewSessionScreen(
        exercises: _exercises(),
        srsRepository: repo,
        gamificationRepository: gamificationRepo,
      ),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['li-1']);
    expect(find.text('¡Repaso completado!'), findsOneWidget);
    expect(gamificationRepo.xpAwards, [10]);
    expect(gamificationRepo.activityRecorded, true);
  });

  testWidgets(
      'a throwing gamification repository never blocks or breaks review completion',
      (tester) async {
    final repo = FakeSrsRepository();
    final gamificationRepo = FakeGamificationRepository()..shouldThrow = true;
    await tester.pumpWidget(MaterialApp(
      home: ReviewSessionScreen(
        exercises: _exercises(),
        srsRepository: repo,
        gamificationRepository: gamificationRepo,
      ),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['li-1']);
    expect(find.text('¡Repaso completado!'), findsOneWidget);
  });

  testWidgets('shows an empty state when there is nothing due', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReviewSessionScreen(
        exercises: const [],
        srsRepository: FakeSrsRepository(),
        gamificationRepository: FakeGamificationRepository(),
      ),
    ));

    expect(find.text('No hay nada para repasar ahora mismo.'), findsOneWidget);
  });

  testWidgets('shows an error if the SRS update fails', (tester) async {
    final repo = FakeSrsRepository()..shouldFail = true;
    await tester.pumpWidget(MaterialApp(
      home: ReviewSessionScreen(
        exercises: _exercises(),
        srsRepository: repo,
        gamificationRepository: FakeGamificationRepository(),
      ),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();

    expect(find.text('¡Repaso completado!'), findsNothing);
    expect(find.textContaining('No se pudo'), findsOneWidget);
  });

  testWidgets('reaching the error limit ends the review session before it completes', (tester) async {
    final srsRepo = FakeSrsRepository();
    final gamificationRepo = FakeGamificationRepository();
    await tester.pumpWidget(MaterialApp(
      home: ReviewSessionScreen(
        exercises: _exercisesForErrorLimit(),
        srsRepository: srsRepo,
        gamificationRepository: gamificationRepo,
      ),
    ));

    await tester.tap(find.text('Goodbye'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goodbye'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goodbye'));
    await tester.pumpAndSettle();

    expect(find.text('Alcanzaste el límite de errores para esta sesión.'), findsOneWidget);
    expect(find.text('p4'), findsNothing);
    expect(gamificationRepo.activityRecorded, false);
  });
}
