import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

import 'features/auth/presentation/screens/welcome_screen.dart';
import 'features/auth/presentation/screens/phone_entry_screen.dart';
import 'features/auth/presentation/screens/otp_verification_screen.dart';
import 'features/booking/presentation/screens/destination_selection_screen.dart';
import 'features/booking/presentation/screens/payment_method_screen.dart';
import 'features/booking/presentation/screens/rate_driver_screen.dart';
import 'features/booking/presentation/screens/rider_booking_screen.dart';
import 'features/booking/presentation/screens/ride_fare_offer_screen.dart';
import 'features/booking/presentation/screens/ride_tracking_screen.dart';
import 'features/profile/presentation/screens/rider_profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('Failed to load dotenv file: $e');
  }
  runApp(const ProviderScope(child: KwellaRiderApp()));
}

class KwellaRiderApp extends StatelessWidget {
  const KwellaRiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kwella Rider',
      debugShowCheckedModeBanner: false,
      theme: KwellaTheme.kwellaDarkTheme,
      initialRoute: '/welcome',
      routes: {
        '/welcome': (_) => const WelcomeScreen(),
        '/auth/phone': (_) => const PhoneEntryScreen(),
        '/auth/otp': (_) => const OtpVerificationScreen(),
        '/rider/home': (_) => const RiderBookingScreen(),
        '/rider/destination': (context) => DestinationSelectionScreen(
              initialDropoff:
                  ModalRoute.of(context)?.settings.arguments as String?,
            ),
        '/rider/payment-method': (_) => const PaymentMethodScreen(),
        '/rider/fare-offer': (_) => const RideFareOfferScreen(),
        '/rider/tracking': (_) => const RideTrackingScreen(),
        '/rider/rating': (_) => const RateDriverScreen(),
        '/rider/profile': (_) => const RiderProfileScreen(),
      },
    );
  }
}
