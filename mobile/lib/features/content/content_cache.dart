import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

abstract class ContentCache {
  Future<void> saveActiveCourse(Map<String, dynamic> courseJson);
  Future<Map<String, dynamic>?> loadActiveCourse();
}

class SharedPreferencesContentCache implements ContentCache {
  static const _key = 'cached_active_course';

  @override
  Future<void> saveActiveCourse(Map<String, dynamic> courseJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(courseJson));
  }

  @override
  Future<Map<String, dynamic>?> loadActiveCourse() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }
}
