import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/auth/auth_repository.dart';
import 'package:effica_palaboom/features/auth/login_screen.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.failureMode = FailureMode.none});
  final FailureMode failureMode;
  String? lastEmail;
  String? lastPassword;

  @override
  Stream<bool> get authStateChanges => const Stream.empty();

  @override
  Future<void> signIn({required String email, required String password}) async {
    lastEmail = email;
    lastPassword = password;
    switch (failureMode) {
      case FailureMode.none:
        break;
      case FailureMode.invalidCredentials:
        throw InvalidCredentialsException();
      case FailureMode.connectivity:
        throw Exception('Connection timeout');
    }
  }
}

enum FailureMode { none, invalidCredentials, connectivity }

void main() {
  testWidgets('successful login calls signIn with entered credentials', (tester) async {
    final repo = FakeAuthRepository();
    await tester.pumpWidget(MaterialApp(home: LoginScreen(authRepository: repo)));

    await tester.enterText(find.byKey(const Key('emailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret123');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(repo.lastEmail, 'user@example.com');
    expect(repo.lastPassword, 'secret123');
    expect(find.text('Correo o contraseña incorrectos'), findsNothing);
  });

  testWidgets('failed login shows credential error message', (tester) async {
    final repo = FakeAuthRepository(failureMode: FailureMode.invalidCredentials);
    await tester.pumpWidget(MaterialApp(home: LoginScreen(authRepository: repo)));

    await tester.enterText(find.byKey(const Key('emailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'wrong');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
  });

  testWidgets('connectivity error shows network error message', (tester) async {
    final repo = FakeAuthRepository(failureMode: FailureMode.connectivity);
    await tester.pumpWidget(MaterialApp(home: LoginScreen(authRepository: repo)));

    await tester.enterText(find.byKey(const Key('emailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'secret123');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo conectar. Revisa tu conexión e intenta de nuevo.'), findsOneWidget);
  });
}
