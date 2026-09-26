import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/content_cache.dart';
import 'package:effica_palaboom/features/content/content_remote_data_source.dart';
import 'package:effica_palaboom/features/content/content_repository.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/course/course_screen.dart';
import 'package:effica_palaboom/features/lesson/lesson_screen.dart';
import 'package:effica_palaboom/features/lesson/progress_repository.dart';
import 'package:effica_palaboom/features/progress/progress_screen.dart';
import 'package:effica_palaboom/features/progress/progress_summary_repository.dart';
import 'package:effica_palaboom/features/progress/unit_progress_summary.dart';
import 'package:effica_palaboom/features/srs/review_session_screen.dart';
import 'package:effica_palaboom/features/srs/srs_repository.dart';

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

class FakeSrsRepository implements SrsRepository {
  FakeSrsRepository({this.due = const []});
  final calls = <(String, bool)>[];
  final List<Exercise> due;

  @override
  Future<int> getDueCount() async => due.length;

  @override
  Future<List<Exercise>> getDueExercises() async => due;

  @override
  Future<void> submitReviewResult({required String learningItemId, required bool correct}) async {
    calls.add((learningItemId, correct));
  }
}

class FakeProgressSummaryRepository implements ProgressSummaryRepository {
  @override
  Future<List<UnitProgressSummary>> getUnitProgressSummaries() async => const [];
}

class ThrowingRemoteDataSource implements ContentRemoteDataSource {
  int callCount = 0;

  @override
  Future<Map<String, dynamic>> fetchActiveCourse() async {
    callCount++;
    throw Exception('network error');
  }
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
        srsRepository: FakeSrsRepository(),
        progressSummaryRepository: FakeProgressSummaryRepository(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Saludos básicos'), findsOneWidget);
    expect(find.text('Saludar y despedirse'), findsOneWidget);

    await tester.tap(find.text('Saludar y despedirse'));
    await tester.pumpAndSettle();

    expect(find.byType(LessonScreen), findsOneWidget);
  });

  testWidgets('a fetch failure shows an error message with a retry affordance instead of '
      'spinning forever', (tester) async {
    final dataSource = ThrowingRemoteDataSource();
    final repository = ContentRepository(
      remoteDataSource: dataSource,
      cache: FakeContentCache(),
    );

    await tester.pumpWidget(MaterialApp(
      home: CourseScreen(
        contentRepository: repository,
        progressRepository: FakeProgressRepository(),
        srsRepository: FakeSrsRepository(),
        progressSummaryRepository: FakeProgressSummaryRepository(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No se pudo cargar el curso.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Reintentar'), findsOneWidget);

    expect(dataSource.callCount, 1);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reintentar'));
    await tester.pumpAndSettle();

    expect(dataSource.callCount, 2);
    expect(find.text('No se pudo cargar el curso.'), findsOneWidget);
  });

  testWidgets('shows the due count and navigates to ReviewSessionScreen on tap', (tester) async {
    final repository = ContentRepository(
      remoteDataSource: FakeRemoteDataSource(),
      cache: FakeContentCache(),
    );
    final dueExercise = const Exercise(
      id: 'ex-due',
      sortOrder: 1,
      type: 'multiple_choice',
      content: {'prompt': 'x', 'options': ['a']},
      correctAnswer: 'a',
      learningItemIds: ['li-1'],
    );

    await tester.pumpWidget(MaterialApp(
      home: CourseScreen(
        contentRepository: repository,
        progressRepository: FakeProgressRepository(),
        srsRepository: FakeSrsRepository(due: [dueExercise]),
        progressSummaryRepository: FakeProgressSummaryRepository(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 para repasar'), findsOneWidget);

    await tester.tap(find.text('Repaso'));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewSessionScreen), findsOneWidget);
  });

  testWidgets('AppBar has a button that opens ProgressScreen', (tester) async {
    final repository = ContentRepository(
      remoteDataSource: FakeRemoteDataSource(),
      cache: FakeContentCache(),
    );

    await tester.pumpWidget(MaterialApp(
      home: CourseScreen(
        contentRepository: repository,
        progressRepository: FakeProgressRepository(),
        srsRepository: FakeSrsRepository(),
        progressSummaryRepository: FakeProgressSummaryRepository(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();

    expect(find.byType(ProgressScreen), findsOneWidget);
  });
}
