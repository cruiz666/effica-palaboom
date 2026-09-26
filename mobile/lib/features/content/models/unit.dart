import 'lesson.dart';

class Unit {
  const Unit({
    required this.id,
    required this.title,
    required this.cefrLevel,
    required this.sortOrder,
    required this.lessons,
  });

  final String id;
  final String title;
  final String cefrLevel;
  final int sortOrder;
  final List<Lesson> lessons;

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      id: json['id'] as String,
      title: json['title'] as String,
      cefrLevel: json['cefrLevel'] as String,
      sortOrder: json['sortOrder'] as int,
      lessons: (json['lessons'] as List)
          .map((l) => Lesson.fromJson(Map<String, dynamic>.from(l as Map)))
          .toList(),
    );
  }
}
