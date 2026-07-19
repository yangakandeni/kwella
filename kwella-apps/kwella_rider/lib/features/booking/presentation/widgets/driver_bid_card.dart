import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DriverBidCard — v2 Electric Lime Dark Mode
// ─────────────────────────────────────────────────────────────────────────────

class DriverBidCard extends StatelessWidget {
  const DriverBidCard({
    super.key,
    required this.driverId,
    required this.driverName,
    required this.driverRating,
    required this.vehicleDescription,
    required this.licensePlate,
    required this.cataSticker,
    required this.fareLabel,
    required this.onAccept,
  });

  final String driverId;
  final String driverName;
  final String driverRating;
  final String vehicleDescription;
  final String licensePlate;
  final String cataSticker;
  final dynamic fareLabel; // num or String
  final VoidCallback onAccept;

  String get _fareText {
    if (fareLabel is num) {
      return 'Accept  R${(fareLabel as num).toStringAsFixed(0)}';
    }
    final parsed = double.tryParse(fareLabel.toString());
    if (parsed != null) {
      return 'Accept  R${parsed.toStringAsFixed(0)}';
    }
    return fareLabel.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2C2C2C)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Driver header ──────────────────────────────────────────
          Row(
            children: [
              // Avatar with Electric Lime ring
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF242424),
                  border: Border.all(
                    color: const Color(0xFFDFFF00),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    driverName.isNotEmpty ? driverName[0].toUpperCase() : 'D',
                    style: const TextStyle(
                      color: Color(0xFFDFFF00),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverName,
                      key: const Key('driver_name'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    // Star rating row
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFDFFF00),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          driverRating,
                          key: const Key('driver_rating'),
                          style: const TextStyle(
                            color: Color(0xFFA0A0A0),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ── Divider ────────────────────────────────────────────────
          const Divider(color: Color(0xFF2C2C2C), height: 1),
          const SizedBox(height: 12),
          // ── Vehicle info ───────────────────────────────────────────
          Text(
            vehicleDescription,
            key: const Key('vehicle_description'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          _InfoRow(
            icon: Icons.credit_card_rounded,
            label: 'License: $licensePlate',
            widgetKey: const Key('license_plate'),
          ),
          const SizedBox(height: 4),
          _InfoRow(
            icon: Icons.verified_rounded,
            label: 'CATA Sticker: $cataSticker',
            widgetKey: const Key('cata_sticker'),
            iconColor: const Color(0xFF69FF47),
          ),
          const Spacer(),
          const SizedBox(height: 14),
          // ── Accept button with pulse animation ────────────────────
          _PulseButton(
            key: const Key('accept_button'),
            fareText: _fareText,
            onPressed: onAccept,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Row with icon + label
// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    this.iconColor = const Color(0xFF606060),
    this.widgetKey,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final Key? widgetKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            key: widgetKey,
            style: const TextStyle(
              color: Color(0xFF808080),
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Accept button with subtle pulsing glow
// ─────────────────────────────────────────────────────────────────────────────

class _PulseButton extends StatefulWidget {
  const _PulseButton({
    super.key,
    required this.fareText,
    required this.onPressed,
  });

  final String fareText;
  final VoidCallback onPressed;

  @override
  State<_PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<_PulseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _glow = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color:
                    Color.lerp(Colors.transparent, const Color(0x60DFFF00), _glow.value)!,
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: widget.onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDFFF00),
            foregroundColor: const Color(0xFF1A1A00),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Text(
            widget.fareText,
            key: const Key('fare_label'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
