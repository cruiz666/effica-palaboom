import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/content/models/exercise.dart';
import 'package:effica_palaboom/features/srs/srs_repository.dart';

class FakeSrsRepository implements SrsRepository {
  final List<Exercise> due;
  FakeSrsRepository(this.due);

  String? lastLearningItemId;
  bool? lastCorrect;

  @override
  Future<int> getDueCount() async => due.length;

  @override
  Future<List<Exercise>> getDueExercises() async => due;

  @override
  Future<void> submitReviewResult({required String learningItemId, required bool correct}) async {
    lastLearningItemId = learningItemId;
    lastCorrect = correct;
  }
}

void main() {
  test('getDueCount matches the number of due exercises', () async {
    final repo = FakeSrsRepository([
      const Exercise(id: 'e1', sortOrder: 1, type: 'multiple_choice', content: {}, correctAnswer: 'x'),
      const Exercise(id: 'e2', sortOrder: 2, type: 'multiple_choice', content: {}, correctAnswer: 'x'),
    ]);

    expect(await repo.getDueCount(), 2);
  });

  test('submitReviewResult records the learning item and result', () async {
    final repo = FakeSrsRepository(const []);

    await repo.submitReviewResult(learningItemId: 'li-1', correct: true);

    expect(repo.lastLearningItemId, 'li-1');
    expect(repo.lastCorrect, true);
  });
}
