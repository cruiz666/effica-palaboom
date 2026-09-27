import 'package:flutter/material.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/login_screen.dart';
import 'features/content/content_repository.dart';
import 'features/course/course_screen.dart';
import 'features/gamification/gamification_repository.dart';
import 'features/lesson/progress_repository.dart';
import 'features/progress/progress_summary_repository.dart';
import 'features/srs/srs_repository.dart';
import 'theme/app_theme.dart';

class App extends StatelessWidget {
  const App({
    super.key,
    required this.authRepository,
    required this.contentRepository,
    required this.progressRepository,
    required this.srsRepository,
    required this.progressSummaryRepository,
    required this.gamificationRepository,
  });

  final AuthRepository authRepository;
  final ContentRepository contentRepository;
  final ProgressRepository progressRepository;
  final SrsRepository srsRepository;
  final ProgressSummaryRepository progressSummaryRepository;
  final GamificationRepository gamificationRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: appTheme,
      home: StreamBuilder<bool>(
        stream: authRepository.authStateChanges,
        builder: (context, snapshot) {
          final signedIn = snapshot.data ?? false;
          if (!signedIn) {
            return LoginScreen(authRepository: authRepository);
          }
          return CourseScreen(
            contentRepository: contentRepository,
            progressRepository: progressRepository,
            srsRepository: srsRepository,
            progressSummaryRepository: progressSummaryRepository,
            gamificationRepository: gamificationRepository,
          );
        },
      ),
    );
  }
}
