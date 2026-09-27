class EntitlementState {
  const EntitlementState({
    required this.isPremium,
    required this.freeLessonsUsedToday,
    required this.freeLessonsLimit,
  });

  final bool isPremium;
  final int freeLessonsUsedToday;
  final int freeLessonsLimit;

  bool get limitReached => !isPremium && freeLessonsUsedToday >= freeLessonsLimit;

  factory EntitlementState.fromJson(Map<String, dynamic> json) {
    return EntitlementState(
      isPremium: json['isPremium'] as bool,
      freeLessonsUsedToday: json['freeLessonsUsedToday'] as int,
      freeLessonsLimit: json['freeLessonsLimit'] as int,
    );
  }
}
