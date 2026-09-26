import 'package:flutter/material.dart';

const _midnightTealSeed = Color(0xFF0F3D3E);

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _midnightTealSeed,
    brightness: Brightness.dark,
  ),
  scaffoldBackgroundColor: const Color(0xFF0A1F22),
);
