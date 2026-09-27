import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/progress/progress_screen.dart';
import 'package:effica_palaboom/features/progress/progress_summary_repository.dart';
import 'package:effica_palaboom/features/progress/unit_progress_summary.dart';

class FakeProgressSummaryRepository implements ProgressSummaryRepository {
  FakeProgressSummaryRepository(this.summaries);
  final List<UnitProgressSummary> summaries;

  @override
  Future<List<UnitProgressSummary>> getUnitProgressSummaries() async => summaries;
}

void main() {
  testWidgets('shows a summary row per unit', (tester) async {
    final repo = FakeProgressSummaryRepository([
      const UnitProgressSummary(
        unitId: 'u1',
        unitTitle: 'Saludos básicos',
        totalLessons: 2,
        completedLessons: 1,
        totalLearningItems: 4,
        learnedItems: 2,
        dueTodayItems: 1,
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: ProgressScreen(progressSummaryRepository: repo),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Saludos básicos'), findsOneWidget);
    expect(find.textContaining('1/2 lecciones'), findsOneWidget);
    expect(find.textContaining('2/4 aprendidas'), findsOneWidget);
    expect(find.textContaining('1 para repasar hoy'), findsOneWidget);
  });
}
