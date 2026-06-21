import 'package:flutter/material.dart';

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
  final String fareLabel;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4EA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E0D6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1E4620),
                ),
                child: Center(
                  child: Text(
                    driverName.isNotEmpty ? driverName[0] : 'D',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverName,
                      key: const Key('driver_name'),
                      style: const TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      driverRating,
                      key: const Key('driver_rating'),
                      style: const TextStyle(
                        color: Color(0xFF111111),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            vehicleDescription,
            key: const Key('vehicle_description'),
            style: const TextStyle(color: Color(0xFF111111), fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'License: $licensePlate',
            key: const Key('license_plate'),
            style: const TextStyle(color: Color(0xFF111111), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'CATA Sticker: $cataSticker',
            key: const Key('cata_sticker'),
            style: const TextStyle(color: Color(0xFF111111), fontSize: 12),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              key: const Key('accept_button'),
              onPressed: onAccept,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E4620),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                fareLabel,
                key: const Key('fare_label'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
