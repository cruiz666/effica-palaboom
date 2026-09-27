import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/content_cache.dart';
import 'package:effica_palaboom/features/content/content_remote_data_source.dart';
import 'package:effica_palaboom/features/content/content_repository.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/course/course_screen.dart';
import 'package:effica_palaboom/features/entitlement/entitlement_repository.dart';
import 'package:effica_palaboom/features/entitlement/entitlement_state.dart';
import 'package:effica_palaboom/features/entitlement/paywall_screen.dart';
import 'package:effica_palaboom/features/entitlement/purchase_gateway.dart';
import 'package:effica_palaboom/features/gamification/gamification_header.dart';
import 'package:effica_palaboom/features/gamification/gamification_repository.dart';
import 'package:effica_palaboom/features/gamification/gamification_state.dart';
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
  FakeSrsRepository({this.due = const [], this.throwOnDueCount = false});
  final calls = <(String, bool)>[];
  final List<Exercise> due;
  final bool throwOnDueCount;

  @override
  Future<int> getDueCount() async {
    if (throwOnDueCount) {
      throw Exception('RPC unavailable');
    }
    return due.length;
  }

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

class FakeGamificationRepository implements GamificationRepository {
  FakeGamificationRepository({this.state = const GamificationState(xpTotal: 0, currentStreak: 0, longestStreak: 0, level: 1)});
  final GamificationState state;
  final xpAwards = <int>[];
  bool activityRecorded = false;

  @override
  Future<GamificationState> getState() async => state;

  @override
  Future<void> awardXp(int amount) async {
    xpAwards.add(amount);
  }

  @override
  Future<void> recordActivity() async {
    activityRecorded = true;
  }
}

class FakeEntitlementRepository implements EntitlementRepository {
  FakeEntitlementRepository({
    this.state = const EntitlementState(isPremium: false, freeLessonsUsedToday: 0, freeLessonsLimit: 3),
    this.throwOnGetState = false,
  });
  final EntitlementState state;
  final bool throwOnGetState;

  @override
  Future<EntitlementState> getState() async {
    if (throwOnGetState) {
      throw Exception('entitlement check unavailable');
    }
    return state;
  }
}

class FakePurchaseGateway implements PurchaseGateway {
  @override
  Future<bool> purchaseMonthly() async => true;

  @override
  Future<void> restorePurchases() async {}
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
        gamificationRepository: FakeGamificationRepository(),
        entitlementRepository: FakeEntitlementRepository(),
        purchaseGateway: FakePurchaseGateway(),
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
        gamificationRepository: FakeGamificationRepository(),
        entitlementRepository: FakeEntitlementRepository(),
        purchaseGateway: FakePurchaseGateway(),
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
    const dueExercise = Exercise(
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
        gamificationRepository: FakeGamificationRepository(),
        entitlementRepository: FakeEntitlementRepository(),
        purchaseGateway: FakePurchaseGateway(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 para repasar'), findsOneWidget);

    await tester.tap(find.text('Repaso'));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewSessionScreen), findsOneWidget);
  });

  testWidgets(
      'a due-count RPC failure shows an error message instead of the misleading '
      '"Sin repasos pendientes hoy"', (tester) async {
    final repository = ContentRepository(
      remoteDataSource: FakeRemoteDataSource(),
      cache: FakeContentCache(),
    );

    await tester.pumpWidget(MaterialApp(
      home: CourseScreen(
        contentRepository: repository,
        progressRepository: FakeProgressRepository(),
        srsRepository: FakeSrsRepository(throwOnDueCount: true),
        progressSummaryRepository: FakeProgressSummaryRepository(),
        gamificationRepository: FakeGamificationRepository(),
        entitlementRepository: FakeEntitlementRepository(),
        purchaseGateway: FakePurchaseGateway(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo cargar el repaso.'), findsOneWidget);
    expect(find.text('Sin repasos pendientes hoy'), findsNothing);
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
        gamificationRepository: FakeGamificationRepository(),
        entitlementRepository: FakeEntitlementRepository(),
        purchaseGateway: FakePurchaseGateway(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();

    expect(find.byType(ProgressScreen), findsOneWidget);
  });

  testWidgets('shows the gamification header with real state', (tester) async {
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
        gamificationRepository: FakeGamificationRepository(
          state: const GamificationState(xpTotal: 50, currentStreak: 2, longestStreak: 4, level: 1),
        ),
        entitlementRepository: FakeEntitlementRepository(),
        purchaseGateway: FakePurchaseGateway(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(GamificationHeader), findsOneWidget);
    expect(find.text('Racha: 2 días · 50 XP · Nivel 1'), findsOneWidget);
  });

  testWidgets('opens PaywallScreen instead of LessonScreen when the daily limit is reached',
      (tester) async {
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
        gamificationRepository: FakeGamificationRepository(),
        entitlementRepository: FakeEntitlementRepository(
          state: const EntitlementState(isPremium: false, freeLessonsUsedToday: 3, freeLessonsLimit: 3),
        ),
        purchaseGateway: FakePurchaseGateway(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saludar y despedirse'));
    await tester.pumpAndSettle();

    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.byType(LessonScreen), findsNothing);
  });

  testWidgets('opens LessonScreen even past the daily limit when the user is premium',
      (tester) async {
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
        gamificationRepository: FakeGamificationRepository(),
        entitlementRepository: FakeEntitlementRepository(
          state: const EntitlementState(isPremium: true, freeLessonsUsedToday: 5, freeLessonsLimit: 3),
        ),
        purchaseGateway: FakePurchaseGateway(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saludar y despedirse'));
    await tester.pumpAndSettle();

    expect(find.byType(LessonScreen), findsOneWidget);
    expect(find.byType(PaywallScreen), findsNothing);
  });

  testWidgets(
      'an entitlement-check failure shows an error message instead of silently doing '
      'nothing when a lesson is tapped', (tester) async {
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
        gamificationRepository: FakeGamificationRepository(),
        entitlementRepository: FakeEntitlementRepository(throwOnGetState: true),
        purchaseGateway: FakePurchaseGateway(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saludar y despedirse'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo abrir la lección. Intenta de nuevo.'), findsOneWidget);
    expect(find.byType(LessonScreen), findsNothing);
    expect(find.byType(PaywallScreen), findsNothing);
  });
}
