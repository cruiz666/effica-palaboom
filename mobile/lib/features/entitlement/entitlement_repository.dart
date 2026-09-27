import 'package:supabase_flutter/supabase_flutter.dart';
import 'entitlement_state.dart';

abstract class EntitlementRepository {
  Future<EntitlementState> getState();
}

class SupabaseEntitlementRepository implements EntitlementRepository {
  SupabaseEntitlementRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<EntitlementState> getState() async {
    final result = await _client.rpc('get_entitlement_state');
    return EntitlementState.fromJson(Map<String, dynamic>.from(result as Map));
  }
}
