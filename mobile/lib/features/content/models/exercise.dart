class Exercise {
  const Exercise({
    required this.id,
    required this.sortOrder,
    required this.type,
    required this.content,
    required this.correctAnswer,
    this.learningItemIds = const [],
  });

  final String id;
  final int sortOrder;
  final String type;
  final Map<String, dynamic> content;
  final dynamic correctAnswer;
  final List<String> learningItemIds;

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'] as String,
      sortOrder: json['sortOrder'] as int,
      type: json['type'] as String,
      content: Map<String, dynamic>.from(json['content'] as Map),
      correctAnswer: json['correctAnswer'],
      learningItemIds: json['learningItemIds'] == null
          ? const []
          : List<String>.from(json['learningItemIds'] as List),
    );
  }
}
