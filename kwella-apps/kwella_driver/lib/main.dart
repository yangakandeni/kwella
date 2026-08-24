import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

import 'features/location/presentation/controllers/kwella_telemetry_controller.dart';
import 'features/bidding/presentation/screens/bidding_marketplace_screen.dart';
import 'features/bidding/presentation/screens/driver_onboarding_screen.dart';
import 'features/bidding/presentation/screens/driver_profile_setup_screen.dart';
import 'features/bidding/presentation/screens/trip_navigation_screen.dart';
import 'features/bidding/presentation/screens/post_trip_screen.dart';
import 'features/earnings/presentation/screens/earnings_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('Failed to load dotenv file: $e');
  }

  try {
    await Firebase.initializeApp();
    debugPrint('Firebase initialized successfully.');
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }

  final container = ProviderContainer();
  _setupFirebaseNotificationListeners(container);

  runApp(ProviderScope(parent: container, child: const KwellaDriverApp()));
}

void _setupFirebaseNotificationListeners(ProviderContainer container) {
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    final data = message.data;
    if (data['action'] == 'rideOfferAvailable') {
      debugPrint(
        '[Main] Push notification opened with rideOfferAvailable payload: $data',
      );
      container
          .read(telemetryControllerProvider.notifier)
          .handlePushNotificationClick(data);
    }
  });
}

class KwellaDriverApp extends StatelessWidget {
  const KwellaDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kwella Driver',
      debugShowCheckedModeBanner: false,
      theme: KwellaTheme.kwellaDarkTheme,
      home: const BiddingMarketplaceScreen(),
      routes: {
        '/driver/onboarding': (_) => const DriverOnboardingScreen(),
        '/driver/profile-setup': (_) => const DriverProfileSetupScreen(),
        '/driver/navigation': (_) => const TripNavigationScreen(),
        '/driver/post-trip': (_) => const PostTripScreen(),
        '/driver/earnings': (_) => const EarningsDashboardScreen(),
      },
    );
  }
}
