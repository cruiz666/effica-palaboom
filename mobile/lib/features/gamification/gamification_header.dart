import 'package:flutter/material.dart';
import 'gamification_state.dart';

class GamificationHeader extends StatelessWidget {
  const GamificationHeader({super.key, required this.state});

  final GamificationState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Racha: ${state.currentStreak} días · ${state.xpTotal} XP · Nivel ${state.level}',
      ),
    );
  }
}
