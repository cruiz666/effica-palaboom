class UnitProgressSummary {
  const UnitProgressSummary({
    required this.unitId,
    required this.unitTitle,
    required this.totalLessons,
    required this.completedLessons,
    required this.totalLearningItems,
    required this.learnedItems,
    required this.dueTodayItems,
  });

  final String unitId;
  final String unitTitle;
  final int totalLessons;
  final int completedLessons;
  final int totalLearningItems;
  final int learnedItems;
  final int dueTodayItems;

  factory UnitProgressSummary.fromJson(Map<String, dynamic> json) {
    return UnitProgressSummary(
      unitId: json['unitId'] as String,
      unitTitle: json['unitTitle'] as String,
      totalLessons: json['totalLessons'] as int,
      completedLessons: json['completedLessons'] as int,
      totalLearningItems: json['totalLearningItems'] as int,
      learnedItems: json['learnedItems'] as int,
      dueTodayItems: json['dueTodayItems'] as int,
    );
  }
}
