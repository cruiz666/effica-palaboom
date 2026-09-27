import 'package:flutter/material.dart';
import 'purchase_gateway.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    required this.freeLessonsUsedToday,
    required this.freeLessonsLimit,
    required this.purchaseGateway,
  });

  final int freeLessonsUsedToday;
  final int freeLessonsLimit;
  final PurchaseGateway purchaseGateway;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isPurchasing = false;
  bool _purchased = false;
  bool _purchaseFailed = false;

  Future<void> _purchase() async {
    setState(() {
      _isPurchasing = true;
      _purchaseFailed = false;
    });
    final success = await widget.purchaseGateway.purchaseMonthly();
    if (!mounted) return;
    setState(() {
      _isPurchasing = false;
      _purchased = success;
      _purchaseFailed = !success;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Suscripción')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_purchased) ...[
                const Text('¡Listo! Ya eres usuario premium.'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Volver al curso'),
                ),
              ] else ...[
                Text(
                  'Ya usaste tus ${widget.freeLessonsUsedToday} lecciones gratis de hoy '
                  '(límite: ${widget.freeLessonsLimit}).',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_purchaseFailed) ...[
                  const Text('No se pudo completar la suscripción. Intenta de nuevo.'),
                  const SizedBox(height: 16),
                ],
                ElevatedButton(
                  onPressed: _isPurchasing ? null : _purchase,
                  child: _isPurchasing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Suscribirse'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
