import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/lesson/widgets/fill_blank_exercise.dart';

Exercise _exercise() => const Exercise(
      id: 'ex-1',
      sortOrder: 1,
      type: 'fill_blank',
      content: {
        'prompt': 'What is your ___?',
        'options': ['name', 'goodbye'],
      },
      correctAnswer: 'name',
    );

void main() {
  testWidgets('selecting the correct option reports true and shows feedback', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: FillBlankExercise(exercise: _exercise(), onAnswered: (r) => result = r),
    ));

    await tester.tap(find.text('name'));
    await tester.pump();

    expect(result, true);
    expect(find.text('¡Correcto!'), findsOneWidget);
  });

  testWidgets('selecting the wrong option reports false and shows feedback', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: FillBlankExercise(exercise: _exercise(), onAnswered: (r) => result = r),
    ));

    await tester.tap(find.text('goodbye'));
    await tester.pump();

    expect(result, false);
    expect(find.text('Incorrecto'), findsOneWidget);
  });
}
