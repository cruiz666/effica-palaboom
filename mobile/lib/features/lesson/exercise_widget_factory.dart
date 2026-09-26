import 'package:flutter/widgets.dart';
import '../content/models/exercise.dart';
import 'widgets/fill_blank_exercise.dart';
import 'widgets/multiple_choice_exercise.dart';
import 'widgets/word_order_exercise.dart';

Widget buildExerciseWidget({
  required Exercise exercise,
  required void Function(bool correct) onAnswered,
}) {
  switch (exercise.type) {
    case 'fill_blank':
      return FillBlankExercise(
        key: ValueKey(exercise.id),
        exercise: exercise,
        onAnswered: onAnswered,
      );
    case 'word_order':
      return WordOrderExercise(
        key: ValueKey(exercise.id),
        exercise: exercise,
        onAnswered: onAnswered,
      );
    default:
      return MultipleChoiceExercise(
        key: ValueKey(exercise.id),
        exercise: exercise,
        onAnswered: onAnswered,
      );
  }
}
