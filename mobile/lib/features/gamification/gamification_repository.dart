import 'package:supabase_flutter/supabase_flutter.dart';
import 'gamification_state.dart';

abstract class GamificationRepository {
  Future<GamificationState> getState();
  Future<void> awardXp(int amount);
  Future<void> recordActivity();
}

class SupabaseGamificationRepository implements GamificationRepository {
  SupabaseGamificationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<GamificationState> getState() async {
    final result = await _client.rpc('get_gamification_state');
    return GamificationState.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<void> awardXp(int amount) async {
    await _client.rpc('add_xp', params: {'p_amount': amount});
  }

  @override
  Future<void> recordActivity() async {
    await _client.rpc('record_activity');
  }
}
