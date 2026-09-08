import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/auth/auth_repository.dart';
import 'package:effica_palaboom/features/auth/login_screen.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.shouldFail = false});
  final bool shouldFail;
  String? lastEmail;
  String? lastPassword;

  @override
  Stream<bool> get authStateChanges => const Stream.empty();

  @override
  Future<void> signIn({required String email, required String password}) async {
    lastEmail = email;
    lastPassword = password;
    if (shouldFail) throw Exception('invalid credentials');
  }
}

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

  testWidgets('failed login shows an error message', (tester) async {
    final repo = FakeAuthRepository(shouldFail: true);
    await tester.pumpWidget(MaterialApp(home: LoginScreen(authRepository: repo)));

    await tester.enterText(find.byKey(const Key('emailField')), 'user@example.com');
    await tester.enterText(find.byKey(const Key('passwordField')), 'wrong');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.pumpAndSettle();

    expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
  });
}
