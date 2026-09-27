import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/app.dart';
import 'package:effica_palaboom/features/auth/auth_repository.dart';
import 'package:effica_palaboom/features/content/content_cache.dart';
import 'package:effica_palaboom/features/content/content_remote_data_source.dart';
import 'package:effica_palaboom/features/content/content_repository.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/course/course_screen.dart';
import 'package:effica_palaboom/features/entitlement/entitlement_repository.dart';
import 'package:effica_palaboom/features/entitlement/entitlement_state.dart';
import 'package:effica_palaboom/features/entitlement/purchase_gateway.dart';
import 'package:effica_palaboom/features/gamification/gamification_repository.dart';
import 'package:effica_palaboom/features/gamification/gamification_state.dart';
import 'package:effica_palaboom/features/lesson/progress_repository.dart';
import 'package:effica_palaboom/features/progress/progress_summary_repository.dart';
import 'package:effica_palaboom/features/progress/unit_progress_summary.dart';
import 'package:effica_palaboom/features/srs/srs_repository.dart';

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<bool>.broadcast();

  @override
  Stream<bool> get authStateChanges => _controller.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {}

  void emit(bool signedIn) => _controller.add(signedIn);
}

class FakeRemoteDataSource implements ContentRemoteDataSource {
  @override
  Future<Map<String, dynamic>> fetchActiveCourse() async =>
      {'id': 'c1', 'title': 'Curso', 'units': <dynamic>[]};
}

class FakeContentCache implements ContentCache {
  @override
  Future<Map<String, dynamic>?> loadActiveCourse() async => null;

  @override
  Future<void> saveActiveCourse(Map<String, dynamic> courseJson) async {}
}

class FakeProgressRepository implements ProgressRepository {
  @override
  Future<void> submitLessonResult({required String lessonId, required double score}) async {}
}

class FakeSrsRepository implements SrsRepository {
  final calls = <(String, bool)>[];

  @override
  Future<int> getDueCount() async => 0;

  @override
  Future<List<Exercise>> getDueExercises() async => const [];

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
  final xpAwards = <int>[];
  bool activityRecorded = false;

  @override
  Future<GamificationState> getState() async =>
      const GamificationState(xpTotal: 0, currentStreak: 0, longestStreak: 0, level: 1);

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
  @override
  Future<EntitlementState> getState() async =>
      const EntitlementState(isPremium: false, freeLessonsUsedToday: 0, freeLessonsLimit: 3);
}

class FakePurchaseGateway implements PurchaseGateway {
  @override
  Future<bool> purchaseMonthly() async => true;
}

void main() {
  testWidgets('shows LoginScreen when signed out and CourseScreen when signed in', (tester) async {
    final authRepository = FakeAuthRepository();

    await tester.pumpWidget(App(
      authRepository: authRepository,
      contentRepository: ContentRepository(
        remoteDataSource: FakeRemoteDataSource(),
        cache: FakeContentCache(),
      ),
      progressRepository: FakeProgressRepository(),
      srsRepository: FakeSrsRepository(),
      progressSummaryRepository: FakeProgressSummaryRepository(),
      gamificationRepository: FakeGamificationRepository(),
      entitlementRepository: FakeEntitlementRepository(),
      purchaseGateway: FakePurchaseGateway(),
    ));

    authRepository.emit(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('emailField')), findsOneWidget);

    authRepository.emit(true);
    await tester.pumpAndSettle();
    expect(find.byType(CourseScreen), findsOneWidget);
  });
}
