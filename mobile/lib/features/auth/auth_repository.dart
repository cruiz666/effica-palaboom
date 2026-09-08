import 'package:supabase_flutter/supabase_flutter.dart';

class InvalidCredentialsException implements Exception {}

abstract class AuthRepository {
  Stream<bool> get authStateChanges;
  Future<void> signIn({required String email, required String password});
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<bool> get authStateChanges =>
      _client.auth.onAuthStateChange.map((state) => state.session != null);

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException {
      throw InvalidCredentialsException();
    }
  }
}
