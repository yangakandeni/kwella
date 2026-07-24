import 'package:flutter/material.dart';

/// Styled text field used for the pickup/dropoff location inputs across the
/// booking flow (home screen's active-trip editor and the destination
/// selection screen).
class LocationInputField extends StatelessWidget {
  const LocationInputField({
    super.key,
    required this.label,
    required this.controller,
    required this.fieldKey,
    required this.onChanged,
    required this.prefixIcon,
    required this.dotColor,
    this.isLoading = false,
  });

  final String label;
  final TextEditingController controller;
  final Key fieldKey;
  final ValueChanged<String> onChanged;
  final IconData prefixIcon;
  final Color dotColor;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2C2C2C)),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Icon(prefixIcon, color: dotColor, size: 18),
          ),
          Expanded(
            child: TextField(
              key: fieldKey,
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: isLoading ? 'Locating your position…' : label,
                hintStyle: const TextStyle(
                  color: Color(0xFF606060),
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                filled: false,
              ),
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: SizedBox(
                width: 14,
                height: 14,
                child: TickerMode(
                  enabled: false,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFDFFF00),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
