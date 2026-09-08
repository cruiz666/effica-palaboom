import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/app.dart';
import 'package:effica_palaboom/features/auth/auth_repository.dart';
import 'package:effica_palaboom/features/content/content_cache.dart';
import 'package:effica_palaboom/features/content/content_remote_data_source.dart';
import 'package:effica_palaboom/features/content/content_repository.dart';
import 'package:effica_palaboom/features/course/course_screen.dart';
import 'package:effica_palaboom/features/lesson/progress_repository.dart';

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
    ));

    authRepository.emit(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('emailField')), findsOneWidget);

    authRepository.emit(true);
    await tester.pumpAndSettle();
    expect(find.byType(CourseScreen), findsOneWidget);
  });
}
