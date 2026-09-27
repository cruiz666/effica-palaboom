class GamificationState {
  const GamificationState({
    required this.xpTotal,
    required this.currentStreak,
    required this.longestStreak,
    required this.level,
  });

  final int xpTotal;
  final int currentStreak;
  final int longestStreak;
  final int level;

  factory GamificationState.fromJson(Map<String, dynamic> json) {
    return GamificationState(
      xpTotal: json['xpTotal'] as int,
      currentStreak: json['currentStreak'] as int,
      longestStreak: json['longestStreak'] as int,
      level: json['level'] as int,
    );
  }
}
