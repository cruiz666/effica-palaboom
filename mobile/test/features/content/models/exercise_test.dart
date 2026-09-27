import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';

void main() {
  test('Exercise.fromJson parses learningItemIds when present', () {
    final exercise = Exercise.fromJson({
      'id': 'ex-1',
      'sortOrder': 1,
      'type': 'fill_blank',
      'content': {'prompt': 'x', 'options': <String>[]},
      'correctAnswer': 'x',
      'learningItemIds': ['li-1', 'li-2'],
    });

    expect(exercise.learningItemIds, ['li-1', 'li-2']);
  });

  test('Exercise.fromJson defaults learningItemIds to empty when absent', () {
    final exercise = Exercise.fromJson({
      'id': 'ex-1',
      'sortOrder': 1,
      'type': 'multiple_choice',
      'content': {'prompt': 'x', 'options': <String>[]},
      'correctAnswer': 'x',
    });

    expect(exercise.learningItemIds, isEmpty);
  });
}
