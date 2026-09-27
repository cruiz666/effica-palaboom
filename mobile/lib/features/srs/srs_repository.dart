import 'package:supabase_flutter/supabase_flutter.dart';
import '../content/models/exercise.dart';

abstract class SrsRepository {
  Future<int> getDueCount();
  Future<List<Exercise>> getDueExercises();
  Future<void> submitReviewResult({required String learningItemId, required bool correct});
}

class SupabaseSrsRepository implements SrsRepository {
  SupabaseSrsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<int> getDueCount() async => (await getDueExercises()).length;

  @override
  Future<List<Exercise>> getDueExercises() async {
    final result = await _client.rpc('get_due_learning_items');
    final list = List<Map<String, dynamic>>.from(
      (result as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    return list.map(Exercise.fromJson).toList();
  }

  @override
  Future<void> submitReviewResult({required String learningItemId, required bool correct}) async {
    await _client.rpc('update_learning_item_progress', params: {
      'p_learning_item_id': learningItemId,
      'p_correct': correct,
    });
  }
}
