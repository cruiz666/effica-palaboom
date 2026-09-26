import 'package:supabase_flutter/supabase_flutter.dart';
import 'unit_progress_summary.dart';

abstract class ProgressSummaryRepository {
  Future<List<UnitProgressSummary>> getUnitProgressSummaries();
}

class SupabaseProgressSummaryRepository implements ProgressSummaryRepository {
  SupabaseProgressSummaryRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<UnitProgressSummary>> getUnitProgressSummaries() async {
    final result = await _client.rpc('get_unit_progress_summary');
    final list = List<Map<String, dynamic>>.from(
      (result as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    return list.map(UnitProgressSummary.fromJson).toList();
  }
}
