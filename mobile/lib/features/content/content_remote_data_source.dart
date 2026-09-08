import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ContentRemoteDataSource {
  Future<Map<String, dynamic>> fetchActiveCourse();
}

class SupabaseContentRemoteDataSource implements ContentRemoteDataSource {
  SupabaseContentRemoteDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>> fetchActiveCourse() async {
    final result = await _client.rpc('get_active_course');
    return Map<String, dynamic>.from(result as Map);
  }
}
