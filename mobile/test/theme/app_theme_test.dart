import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/theme/app_theme.dart';

void main() {
  test('appTheme uses a dark Midnight Teal color scheme', () {
    expect(appTheme.brightness, Brightness.dark);
    expect(appTheme.scaffoldBackgroundColor, const Color(0xFF0A1F22));
    expect(appTheme.colorScheme.brightness, Brightness.dark);
  });
}
