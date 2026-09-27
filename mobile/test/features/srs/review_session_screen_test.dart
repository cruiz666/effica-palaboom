import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
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

void main() {
  testWidgets('answering the only due exercise completes the session', (tester) async {
    final repo = FakeSrsRepository();
    await tester.pumpWidget(MaterialApp(
      home: ReviewSessionScreen(exercises: _exercises(), srsRepository: repo),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();

    expect(repo.calls, ['li-1']);
    expect(find.text('¡Repaso completado!'), findsOneWidget);
  });

  testWidgets('shows an empty state when there is nothing due', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReviewSessionScreen(exercises: const [], srsRepository: FakeSrsRepository()),
    ));

    expect(find.text('No hay nada para repasar ahora mismo.'), findsOneWidget);
  });

  testWidgets('shows an error if the SRS update fails', (tester) async {
    final repo = FakeSrsRepository()..shouldFail = true;
    await tester.pumpWidget(MaterialApp(
      home: ReviewSessionScreen(exercises: _exercises(), srsRepository: repo),
    ));

    await tester.tap(find.text('Hello'));
    await tester.pumpAndSettle();

    expect(find.text('¡Repaso completado!'), findsNothing);
    expect(find.textContaining('No se pudo'), findsOneWidget);
  });
}
