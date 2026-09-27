import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/entitlement/entitlement_repository.dart';
import 'package:effica_palaboom/features/entitlement/entitlement_state.dart';

class FakeEntitlementRepository implements EntitlementRepository {
  FakeEntitlementRepository({required this.state});
  EntitlementState state;

  @override
  Future<EntitlementState> getState() async => state;
}

void main() {
  test('EntitlementState.fromJson parses all three fields', () {
    final state = EntitlementState.fromJson({
      'isPremium': false,
      'freeLessonsUsedToday': 2,
      'freeLessonsLimit': 3,
    });

    expect(state.isPremium, false);
    expect(state.freeLessonsUsedToday, 2);
    expect(state.freeLessonsLimit, 3);
  });

  test('limitReached is true only when not premium and usage has reached the limit', () {
    const underLimit = EntitlementState(isPremium: false, freeLessonsUsedToday: 2, freeLessonsLimit: 3);
    const atLimit = EntitlementState(isPremium: false, freeLessonsUsedToday: 3, freeLessonsLimit: 3);
    const pastLimitButPremium = EntitlementState(isPremium: true, freeLessonsUsedToday: 5, freeLessonsLimit: 3);

    expect(underLimit.limitReached, false);
    expect(atLimit.limitReached, true);
    expect(pastLimitButPremium.limitReached, false);
  });

  test('getState returns the fake repository state', () async {
    final repo = FakeEntitlementRepository(
      state: const EntitlementState(isPremium: true, freeLessonsUsedToday: 0, freeLessonsLimit: 3),
    );

    final state = await repo.getState();

    expect(state.isPremium, true);
  });
}
