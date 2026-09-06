import 'dart:convert';

import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:kwella_core/kwella_core.dart';

/// Seeds a pre-authenticated driver session so screens that read
/// [TokenVault] directly (with no dependency-injection seam — e.g.
/// `DriverProfileSetupScreen._submit()`) see a valid, unexpired Cognito
/// session exactly as they would after a real OTP sign-in.
///
/// The driver app has no signup/OTP screens of its own to drive through in
/// an E2E test, so this fixture starts the suite already signed in, per the
/// approved test plan.
///
/// Mechanics: [TokenVault] (and the [FlutterSecureStorage] it wraps) has no
/// constructor injection point in the screens under test, so the only way to
/// seed the *same* storage those screens read from — without modifying
/// production code — is via `flutter_secure_storage`'s own officially
/// supported test seam: swapping the global
/// [FlutterSecureStoragePlatform.instance] for the package's own
/// [TestFlutterSecureStoragePlatform] (an in-memory implementation shipped
/// specifically for this purpose under `package:flutter_secure_storage/test/`).
/// Every [FlutterSecureStorage]/[TokenVault] instance constructed anywhere
/// in the app afterwards — regardless of how deep in a widget it's created —
/// reads and writes through that same in-memory map.
///
/// Returns the [TokenVault] used to write the seeded tokens, in case a test
/// wants to read them back or mutate them further.
Future<TokenVault> seedPreAuthenticatedSession({
  String userId = 'drv-e2e-1',
  String phoneNumber = '+27821234567',
}) async {
  FlutterSecureStoragePlatform.instance =
      TestFlutterSecureStoragePlatform(<String, String>{});

  final tokenVault = TokenVault();
  final idToken = _fakeJwt({
    'sub': userId,
    'phone_number': phoneNumber,
    // Far-future expiry so KwellaAuthNotifier's persisted-session check
    // treats the session as fresh rather than attempting a (real, network-
    // bound) silent refresh.
    'exp': DateTime.now().toUtc().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
  });

  await tokenVault.writeIdToken(idToken);
  await tokenVault.writeAccessToken('fake-access-token-$userId');
  await tokenVault.writeRefreshToken('fake-refresh-token-$userId');

  return tokenVault;
}

/// Builds an unsigned JWT (`header.payload.signature`) carrying [claims] as
/// its payload. No signature verification happens client-side anywhere in
/// this app (see `KwellaAuthNotifier._decodeJwtPayload` and
/// `DriverProfileSetupScreen._decodeJwtPayload`), so a fake, unsigned token
/// is sufficient to exercise the claim-decoding paths those screens rely on.
String _fakeJwt(Map<String, dynamic> claims) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})));
  final payload = base64Url.encode(utf8.encode(jsonEncode(claims)));
  return '$header.$payload.fake-signature';
}
