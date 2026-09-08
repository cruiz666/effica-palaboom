import 'package:flutter/material.dart';
import 'auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;

  Future<void> _submit() async {
    setState(() => _errorMessage = null);
    try {
      await widget.authRepository.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } catch (_) {
      setState(() => _errorMessage = 'Correo o contraseña incorrectos');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              key: const Key('emailField'),
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Correo'),
            ),
            TextField(
              key: const Key('passwordField'),
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              key: const Key('loginButton'),
              onPressed: _submit,
              child: const Text('Ingresar'),
            ),
            if (_errorMessage != null) Text(_errorMessage!),
          ],
        ),
      ),
    );
  }
}
