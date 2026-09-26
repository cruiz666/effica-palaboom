import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/lesson/exercise_widget_factory.dart';
import 'package:effica_palaboom/features/lesson/widgets/fill_blank_exercise.dart';
import 'package:effica_palaboom/features/lesson/widgets/multiple_choice_exercise.dart';
import 'package:effica_palaboom/features/lesson/widgets/word_order_exercise.dart';

Exercise _exercise(String type) => Exercise(
      id: 'ex-1',
      sortOrder: 1,
      type: type,
      content: type == 'word_order' ? {'words': <String>[]} : {'prompt': 'x', 'options': <String>[]},
      correctAnswer: 'x',
    );

void main() {
  testWidgets('multiple_choice builds MultipleChoiceExercise', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: buildExerciseWidget(exercise: _exercise('multiple_choice'), onAnswered: (_) {}),
    ));
    expect(find.byType(MultipleChoiceExercise), findsOneWidget);
  });

  testWidgets('fill_blank builds FillBlankExercise', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: buildExerciseWidget(exercise: _exercise('fill_blank'), onAnswered: (_) {}),
    ));
    expect(find.byType(FillBlankExercise), findsOneWidget);
  });

  testWidgets('word_order builds WordOrderExercise', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: buildExerciseWidget(exercise: _exercise('word_order'), onAnswered: (_) {}),
    ));
    expect(find.byType(WordOrderExercise), findsOneWidget);
  });
}
