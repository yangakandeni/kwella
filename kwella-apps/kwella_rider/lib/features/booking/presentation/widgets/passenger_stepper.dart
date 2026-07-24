import 'package:flutter/material.dart';

/// Increment/decrement control for the rider's passenger count. Clamps to
/// [min]..[max] and disables the relevant button at each bound.
class PassengerStepper extends StatelessWidget {
  const PassengerStepper({
    super.key,
    required this.count,
    required this.onChanged,
    this.min = 1,
    this.max = 6,
  });

  final int count;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2C2C2C)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _StepperButton(
            key: const Key('passenger_decrement'),
            icon: Icons.remove_rounded,
            onTap: count > min ? () => onChanged(count - 1) : null,
          ),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          _StepperButton(
            key: const Key('passenger_increment'),
            icon: Icons.add_rounded,
            onTap: count < max ? () => onChanged(count + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.35,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2C2C2C)),
          ),
          child: Icon(icon, color: const Color(0xFFDFFF00), size: 22),
        ),
      ),
    );
  }
}
