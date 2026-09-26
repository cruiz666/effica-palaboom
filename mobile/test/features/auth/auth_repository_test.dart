import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:effica_palaboom/features/auth/auth_repository.dart';

void main() {
  group('isInvalidCredentialsError', () {
    test('a real AuthRetryableFetchException (network failure) is NOT classified '
        'as invalid credentials', () {
      final error = AuthRetryableFetchException(message: 'timeout');

      expect(isInvalidCredentialsError(error), isFalse);
    });

    test('a real AuthApiException (e.g. wrong password) IS classified as invalid '
        'credentials', () {
      const error = AuthApiException('invalid', statusCode: '400');

      expect(isInvalidCredentialsError(error), isTrue);
    });

    test('a non-auth error is NOT classified as invalid credentials', () {
      final error = Exception('some unrelated failure');

      expect(isInvalidCredentialsError(error), isFalse);
    });
  });
}
