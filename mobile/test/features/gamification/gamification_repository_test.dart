import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/gamification/gamification_repository.dart';
import 'package:effica_palaboom/features/gamification/gamification_state.dart';

class FakeGamificationRepository implements GamificationRepository {
  FakeGamificationRepository({required this.state});
  GamificationState state;

  final xpAwards = <int>[];
  bool activityRecorded = false;

  @override
  Future<GamificationState> getState() async => state;

  @override
  Future<void> awardXp(int amount) async {
    xpAwards.add(amount);
  }

  @override
  Future<void> recordActivity() async {
    activityRecorded = true;
  }
}

void main() {
  test('GamificationState.fromJson parses all four fields', () {
    final state = GamificationState.fromJson({
      'xpTotal': 120,
      'currentStreak': 3,
      'longestStreak': 5,
      'level': 2,
    });

    expect(state.xpTotal, 120);
    expect(state.currentStreak, 3);
    expect(state.longestStreak, 5);
    expect(state.level, 2);
  });

  test('awardXp and recordActivity record their calls', () async {
    final repo = FakeGamificationRepository(
      state: const GamificationState(xpTotal: 0, currentStreak: 0, longestStreak: 0, level: 1),
    );

    await repo.awardXp(10);
    await repo.recordActivity();

    expect(repo.xpAwards, [10]);
    expect(repo.activityRecorded, true);
  });
}
