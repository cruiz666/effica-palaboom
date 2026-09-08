import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/content_cache.dart';
import 'package:effica_palaboom/features/content/content_remote_data_source.dart';
import 'package:effica_palaboom/features/content/content_repository.dart';
import 'package:effica_palaboom/features/course/course_screen.dart';
import 'package:effica_palaboom/features/lesson/lesson_screen.dart';
import 'package:effica_palaboom/features/lesson/progress_repository.dart';

class FakeRemoteDataSource implements ContentRemoteDataSource {
  @override
  Future<Map<String, dynamic>> fetchActiveCourse() async => {
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
                    'content': {'prompt': 'Hola?', 'options': ['Hello', 'Goodbye']},
                    'correctAnswer': 'Hello',
                  },
                ],
              },
            ],
          },
        ],
      };
}

class FakeContentCache implements ContentCache {
  Map<String, dynamic>? stored;

  @override
  Future<Map<String, dynamic>?> loadActiveCourse() async => stored;

  @override
  Future<void> saveActiveCourse(Map<String, dynamic> courseJson) async {
    stored = courseJson;
  }
}

class FakeProgressRepository implements ProgressRepository {
  @override
  Future<void> submitLessonResult({required String lessonId, required double score}) async {}
}

void main() {
  testWidgets('shows lessons and navigates to LessonScreen on tap', (tester) async {
    final repository = ContentRepository(
      remoteDataSource: FakeRemoteDataSource(),
      cache: FakeContentCache(),
    );

    await tester.pumpWidget(MaterialApp(
      home: CourseScreen(
        contentRepository: repository,
        progressRepository: FakeProgressRepository(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Saludos básicos'), findsOneWidget);
    expect(find.text('Saludar y despedirse'), findsOneWidget);

    await tester.tap(find.text('Saludar y despedirse'));
    await tester.pumpAndSettle();

    expect(find.byType(LessonScreen), findsOneWidget);
  });
}
