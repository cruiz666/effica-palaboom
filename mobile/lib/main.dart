import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'features/auth/auth_repository.dart';
import 'features/content/content_cache.dart';
import 'features/content/content_remote_data_source.dart';
import 'features/content/content_repository.dart';
import 'features/lesson/progress_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
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
