import 'unit.dart';

class Course {
  const Course({
    required this.id,
    required this.title,
    required this.units,
  });

  final String id;
  final String title;
  final List<Unit> units;

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as String,
      title: json['title'] as String,
      units: (json['units'] as List)
          .map((u) => Unit.fromJson(Map<String, dynamic>.from(u as Map)))
          .toList(),
    );
  }
}
