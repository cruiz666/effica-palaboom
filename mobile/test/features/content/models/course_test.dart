import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/course.dart';

void main() {
  test('Course.fromJson parses the nested content tree', () {
    final json = {
      'id': 'course-1',
      'title': 'Inglés para hispanohablantes',
      'units': [
        {
          'id': 'unit-1',
          'title': 'Saludos básicos',
          'cefrLevel': 'A1',
          'sortOrder': 1,
          'lessons': [
            {
              'id': 'lesson-1',
              'title': 'Saludar y despedirse',
              'sortOrder': 1,
              'exercises': [
                {
                  'id': 'ex-1',
                  'sortOrder': 1,
                  'type': 'multiple_choice',
                  'content': {
                    'prompt': '¿Cómo se dice "Hola" en inglés?',
                    'options': ['Hello', 'Goodbye', 'Please'],
                  },
                  'correctAnswer': 'Hello',
                },
              ],
            },
          ],
        },
      ],
    };

    final course = Course.fromJson(json);

    expect(course.title, 'Inglés para hispanohablantes');
    expect(course.units, hasLength(1));
    expect(course.units.first.cefrLevel, 'A1');
    expect(course.units.first.lessons, hasLength(1));
    expect(course.units.first.lessons.first.exercises, hasLength(1));
    final exercise = course.units.first.lessons.first.exercises.first;
    expect(exercise.type, 'multiple_choice');
    expect(exercise.content['prompt'], '¿Cómo se dice "Hola" en inglés?');
    expect(exercise.correctAnswer, 'Hello');
  });
}
