import 'package:supabase_flutter/supabase_flutter.dart';

class NotAuthenticatedException implements Exception {}

abstract class ProgressRepository {
  Future<void> submitLessonResult({required String lessonId, required double score});
}

class SupabaseProgressRepository implements ProgressRepository {
  SupabaseProgressRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> submitLessonResult({required String lessonId, required double score}) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      throw NotAuthenticatedException();
    }
    final userId = currentUser.id;
    await _client.from('user_lesson_progress').insert({
      'user_id': userId,
      'lesson_id': lessonId,
      'score': score,
      'completed_at': DateTime.now().toIso8601String(),
    });
  }
}
