import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:effica_palaboom/features/entitlement/paywall_screen.dart';
import 'package:effica_palaboom/features/entitlement/purchase_gateway.dart';

class FakePurchaseGateway implements PurchaseGateway {
  FakePurchaseGateway({this.shouldSucceed = true, this.shouldThrow = false});
  final bool shouldSucceed;
  final bool shouldThrow;
  int purchaseCalls = 0;

  @override
  Future<bool> purchaseMonthly() async {
    purchaseCalls++;
    if (shouldThrow) {
      throw Exception('store unavailable');
    }
    return shouldSucceed;
  }

  @override
  Future<void> restorePurchases() async {}
}

void main() {
  testWidgets('shows how many free lessons were used today', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: PaywallScreen(
        freeLessonsUsedToday: 3,
        freeLessonsLimit: 3,
        purchaseGateway: FakePurchaseGateway(),
      ),
    ));

    expect(find.textContaining('Ya usaste tus 3 lecciones gratis de hoy'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Suscribirse'), findsOneWidget);
  });

  testWidgets('tapping Suscribirse calls purchaseMonthly and shows success', (tester) async {
    final gateway = FakePurchaseGateway();
    await tester.pumpWidget(MaterialApp(
      home: PaywallScreen(
        freeLessonsUsedToday: 3,
        freeLessonsLimit: 3,
        purchaseGateway: gateway,
      ),
    ));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Suscribirse'));
    await tester.pumpAndSettle();

    expect(gateway.purchaseCalls, 1);
    expect(find.text('¡Listo! Ya eres usuario premium.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Volver al curso'), findsOneWidget);
  });

  testWidgets('a failed purchase shows an error message and allows retry', (tester) async {
    final gateway = FakePurchaseGateway(shouldSucceed: false);
    await tester.pumpWidget(MaterialApp(
      home: PaywallScreen(
        freeLessonsUsedToday: 3,
        freeLessonsLimit: 3,
        purchaseGateway: gateway,
      ),
    ));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Suscribirse'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo completar la suscripción. Intenta de nuevo.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Suscribirse'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Suscribirse'));
    await tester.pumpAndSettle();

    expect(gateway.purchaseCalls, 2);
  });

  testWidgets(
      'a purchase that throws shows an error message and re-enables the button '
      'instead of spinning forever', (tester) async {
    final gateway = FakePurchaseGateway(shouldThrow: true);
    await tester.pumpWidget(MaterialApp(
      home: PaywallScreen(
        freeLessonsUsedToday: 3,
        freeLessonsLimit: 3,
        purchaseGateway: gateway,
      ),
    ));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Suscribirse'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No se pudo completar la suscripción. Intenta de nuevo.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Suscribirse'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Suscribirse'));
    await tester.pumpAndSettle();

    expect(gateway.purchaseCalls, 2);
  });
}
