import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/content_cache.dart';
import 'package:effica_palaboom/features/content/content_remote_data_source.dart';
import 'package:effica_palaboom/features/content/content_repository.dart';

class FakeRemoteDataSource implements ContentRemoteDataSource {
  FakeRemoteDataSource({this.shouldThrow = false, required this.json});
  final bool shouldThrow;
  final Map<String, dynamic> json;

  @override
  Future<Map<String, dynamic>> fetchActiveCourse() async {
    if (shouldThrow) throw Exception('network error');
    return json;
  }
}

class FakeContentCache implements ContentCache {
  Map<String, dynamic>? stored;

  @override
  Future<Map<String, dynamic>?> loadActiveCourse() async => stored;

  @override
  Future<void> saveActiveCourse(Map<String, dynamic> courseJson) async {
    stored = courseJson;
  }
}

Map<String, dynamic> _fixture(String title) => {
      'id': 'course-1',
      'title': title,
      'units': <dynamic>[],
    };

void main() {
  test('getActiveCourse fetches remotely and caches the result', () async {
    final cache = FakeContentCache();
    final repository = ContentRepository(
      remoteDataSource: FakeRemoteDataSource(json: _fixture('Curso remoto')),
      cache: cache,
    );

    final course = await repository.getActiveCourse();

    expect(course.title, 'Curso remoto');
    expect(cache.stored?['title'], 'Curso remoto');
  });

  test('getActiveCourse falls back to cache when the fetch fails', () async {
    final cache = FakeContentCache()..stored = _fixture('Curso cacheado');
    final repository = ContentRepository(
      remoteDataSource: FakeRemoteDataSource(shouldThrow: true, json: _fixture('no usado')),
      cache: cache,
    );

    final course = await repository.getActiveCourse();

    expect(course.title, 'Curso cacheado');
  });
}
