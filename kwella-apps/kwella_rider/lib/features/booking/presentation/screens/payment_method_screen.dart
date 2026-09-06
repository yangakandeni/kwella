import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/kwella_rider_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PaymentMethodScreen
// Minimal payment method selector shown after the fare offer step. Only
// "Cash" is actually selectable today — no payment gateway exists in this
// codebase yet, so "Card" is shown as a disabled "Coming soon" option.
// ─────────────────────────────────────────────────────────────────────────────

class PaymentMethodScreen extends ConsumerStatefulWidget {
  const PaymentMethodScreen({super.key, this.controller});

  final KwellaRiderController? controller;

  @override
  ConsumerState<PaymentMethodScreen> createState() =>
      _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends ConsumerState<PaymentMethodScreen> {
  String _selectedMethod = 'CASH';

  void _continue(KwellaRiderController controller) {
    controller.setPaymentMethod(_selectedMethod);
    Navigator.pushNamed(context, '/rider/fare-offer');
  }

  @override
  Widget build(BuildContext context) {
    final KwellaRiderController controller =
        widget.controller ?? ref.read(kwellaRiderControllerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  GestureDetector(
                    key: const Key('back_button'),
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E1E1E),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Payment method',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose how you want to pay for this ride.',
                style: TextStyle(
                  color: Color(0xFFA0A0A0),
                  fontSize: 13,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 24),
              _PaymentOptionTile(
                paymentKey: const Key('payment_method_cash'),
                icon: Icons.payments_rounded,
                label: 'Cash',
                subtitle: 'Pay your driver directly',
                selected: _selectedMethod == 'CASH',
                enabled: true,
                onTap: () => setState(() => _selectedMethod = 'CASH'),
              ),
              const SizedBox(height: 12),
              _PaymentOptionTile(
                paymentKey: const Key('payment_method_card'),
                icon: Icons.credit_card_rounded,
                label: 'Card',
                subtitle: 'Coming soon',
                selected: _selectedMethod == 'CARD',
                enabled: false,
                onTap: null,
              ),
              const Spacer(),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  key: const Key('payment_continue_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDFFF00),
                    foregroundColor: const Color(0xFF1A1A00),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _continue(controller),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentOptionTile extends StatelessWidget {
  const _PaymentOptionTile({
    required this.paymentKey,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Key paymentKey;
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        key: paymentKey,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? const Color(0xFFDFFF00) : const Color(0xFF2C2C2C),
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFDFFF00), size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFA0A0A0),
                        fontSize: 12,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? const Color(0xFFDFFF00) : const Color(0xFF606060),
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
