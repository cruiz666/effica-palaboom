import 'package:supabase_flutter/supabase_flutter.dart';

class InvalidCredentialsException implements Exception {}

/// Whether [error] represents genuinely bad credentials rather than a
/// connectivity failure.
///
/// AuthRetryableFetchException (network failures, timeouts, and 5xx
/// responses) extends AuthException, so it must be excluded explicitly here
/// or connectivity failures get misreported as "wrong password". Kept as a
/// standalone function so it can be unit-tested directly against real
/// gotrue exception types without needing a live/mocked SupabaseClient.
bool isInvalidCredentialsError(Object error) =>
    error is AuthException && error is! AuthRetryableFetchException;

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
    } catch (error) {
      if (isInvalidCredentialsError(error)) {
        throw InvalidCredentialsException();
      }
      rethrow;
    }
  }
}
