import 'exercise.dart';

class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.sortOrder,
    required this.exercises,
  });

  final String id;
  final String title;
  final int sortOrder;
  final List<Exercise> exercises;

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      id: json['id'] as String,
      title: json['title'] as String,
      sortOrder: json['sortOrder'] as int,
      exercises: (json['exercises'] as List)
          .map((e) => Exercise.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
