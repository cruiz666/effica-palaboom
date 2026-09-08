import 'package:flutter/material.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const PlaceholderApp());
}

class PlaceholderApp extends StatelessWidget {
  const PlaceholderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: appTheme,
      home: const Scaffold(body: Center(child: Text('effica-palaboom'))),
    );
  }
}
