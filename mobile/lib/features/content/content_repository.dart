import 'content_cache.dart';
import 'content_remote_data_source.dart';
import 'models/course.dart';

class ContentRepository {
  ContentRepository({required this.remoteDataSource, required this.cache});

  final ContentRemoteDataSource remoteDataSource;
  final ContentCache cache;

  Future<Course> getActiveCourse() async {
    try {
      final json = await remoteDataSource.fetchActiveCourse();
      await cache.saveActiveCourse(json);
      return Course.fromJson(json);
    } catch (_) {
      final cached = await cache.loadActiveCourse();
      if (cached == null) rethrow;
      return Course.fromJson(cached);
    }
  }
}
