import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'features/auth/auth_repository.dart';
import 'features/content/content_cache.dart';
import 'features/content/content_remote_data_source.dart';
import 'features/content/content_repository.dart';
import 'features/lesson/progress_repository.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_URL / SUPABASE_ANON_KEY. Run with '
      '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
    );
  }
  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );
  final client = Supabase.instance.client;
  runApp(App(
    authRepository: SupabaseAuthRepository(client),
    contentRepository: ContentRepository(
      remoteDataSource: SupabaseContentRemoteDataSource(client),
      cache: SharedPreferencesContentCache(),
    ),
    progressRepository: SupabaseProgressRepository(client),
  ));
}
