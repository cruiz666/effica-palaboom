import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/lesson/widgets/word_order_exercise.dart';

Exercise _exercise() => const Exercise(
      id: 'ex-1',
      sortOrder: 1,
      type: 'word_order',
      content: {
        'words': ['is', 'My', 'Ana', 'name'],
      },
      correctAnswer: 'My name is Ana',
    );

void main() {
  testWidgets('tapping words in the correct order reports true', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: WordOrderExercise(exercise: _exercise(), onAnswered: (r) => result = r),
    ));

    await tester.tap(find.text('My'));
    await tester.pump();
    await tester.tap(find.text('name'));
    await tester.pump();
    await tester.tap(find.text('is'));
    await tester.pump();
    await tester.tap(find.text('Ana'));
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Comprobar'));
    await tester.pump();

    expect(result, true);
    expect(find.text('¡Correcto!'), findsOneWidget);
  });

  testWidgets('placing all words does not answer until Comprobar is tapped', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: WordOrderExercise(exercise: _exercise(), onAnswered: (r) => result = r),
    ));

    await tester.tap(find.text('My'));
    await tester.pump();
    await tester.tap(find.text('name'));
    await tester.pump();
    await tester.tap(find.text('is'));
    await tester.pump();
    await tester.tap(find.text('Ana'));
    await tester.pump();

    expect(result, null);
    expect(find.widgetWithText(ElevatedButton, 'Comprobar'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Comprobar'));
    await tester.pump();

    expect(result, true);
  });

  testWidgets('tapping words in the wrong order reports false', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: WordOrderExercise(exercise: _exercise(), onAnswered: (r) => result = r),
    ));

    await tester.tap(find.text('is'));
    await tester.pump();
    await tester.tap(find.text('My'));
    await tester.pump();
    await tester.tap(find.text('Ana'));
    await tester.pump();
    await tester.tap(find.text('name'));
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Comprobar'));
    await tester.pump();

    expect(result, false);
    expect(find.text('Incorrecto'), findsOneWidget);
  });
}
