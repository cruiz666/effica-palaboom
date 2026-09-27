import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class PurchaseGateway {
  Future<bool> purchaseMonthly();
  Future<void> restorePurchases();
}

class MockPurchaseGateway implements PurchaseGateway {
  MockPurchaseGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> purchaseMonthly() async {
    await _client.rpc('dev_mock_activate_subscription');
    return true;
  }

  @override
  Future<void> restorePurchases() async {}
}

class RevenueCatPurchaseGateway implements PurchaseGateway {
  RevenueCatPurchaseGateway({required this.apiKey});

  final String apiKey;
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await Purchases.configure(PurchasesConfiguration(apiKey));
    _configured = true;
  }

  @override
  Future<bool> purchaseMonthly() async {
    await _ensureConfigured();
    try {
      final offerings = await Purchases.getOfferings();
      final package = offerings.current?.monthly;
      if (package == null) return false;
      await Purchases.purchase(PurchaseParams.package(package));
      return true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> restorePurchases() async {
    await _ensureConfigured();
    await Purchases.restorePurchases();
  }
}
