import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/gamification/gamification_header.dart';
import 'package:effica_palaboom/features/gamification/gamification_state.dart';

void main() {
  testWidgets('shows streak, xp, and level', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GamificationHeader(
        state: GamificationState(xpTotal: 120, currentStreak: 3, longestStreak: 5, level: 2),
      ),
    ));

    expect(find.text('Racha: 3 días · 120 XP · Nivel 2'), findsOneWidget);
  });
}
