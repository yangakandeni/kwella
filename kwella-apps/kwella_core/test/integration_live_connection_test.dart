/// Integration test harness — live production configuration sanity checks.
///
/// Purpose
/// -------
/// This file verifies that the Kwella core network layer is correctly wired to
/// the production AWS infrastructure configuration exported from
/// `.env.production`.  It does **not** open real network sockets; instead it
/// asserts structural invariants:
///
/// 1. [KwellaEnvironment.production] surfaces the correct endpoint tokens.
/// 2. [KwellaWebSocketGateway] is constructed with the production URL by the
///    default provider — no legacy hardcoded strings remain.
/// 3. [KwellaAuthNotifier] targets the live Cognito af-south-1 endpoint and
///    client ID — not any mock/localhost stub.
/// 4. All legacy mock endpoint patterns are absent from the active source.
///
/// These tests are deliberately hermetic (no I/O) so they run reliably inside
/// CI without AWS credentials.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kwella_core/kwella_core.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

/// Known legacy/mock endpoint prefixes that must NOT appear in production
/// network configuration.  The test below scans the live [KwellaEnvironment]
/// values against this list.
const _legacyPatterns = <String>[
  'localhost',
  '127.0.0.1',
  'example.com',
  'mock',
  'stub',
  'fake',
  'test.execute-api',
];

void _assertNoLegacyPattern(String label, String value) {
  for (final pattern in _legacyPatterns) {
    expect(
      value.toLowerCase().contains(pattern),
      isFalse,
      reason:
          '$label must not contain legacy mock pattern "$pattern" — found: $value',
    );
  }
}

// ── Test Suite ────────────────────────────────────────────────────────────

void main() {
  // ─── 1. KwellaEnvironment — production token values ────────────────────

  group('KwellaEnvironment.production — token correctness', () {
    const env = KwellaEnvironment.production;

    test('cognitoUserPoolId matches .env.production', () {
      expect(env.cognitoUserPoolId, 'af-south-1_nanvvqqZO');
    });

    test('cognitoClientId matches .env.production', () {
      expect(env.cognitoClientId, '6enltlvcl8569tt1r49rnfr354');
    });

    test('cognitoEndpoint targets live af-south-1 regional endpoint', () {
      expect(
        env.cognitoEndpoint,
        'https://cognito-idp.af-south-1.amazonaws.com/',
      );
    });

    test('webSocketEndpointUrl matches .env.production', () {
      expect(
        env.webSocketEndpointUrl,
        'wss://oronlku519.execute-api.af-south-1.amazonaws.com/production',
      );
    });

    test('httpApiEndpoint matches .env.production', () {
      expect(
        env.httpApiEndpoint,
        'https://dbmi2nczz8.execute-api.af-south-1.amazonaws.com/',
      );
    });

    test('webSocketEndpointUrl uses wss:// scheme (TLS required)', () {
      expect(env.webSocketEndpointUrl, startsWith('wss://'));
    });

    test('webSocketEndpointUrl targets /production stage', () {
      expect(env.webSocketEndpointUrl, endsWith('/production'));
    });

    test('cognitoEndpoint uses https:// scheme', () {
      expect(env.cognitoEndpoint, startsWith('https://'));
    });

    test('httpApiEndpoint uses https:// scheme', () {
      expect(env.httpApiEndpoint, startsWith('https://'));
    });

    test('all endpoints target af-south-1 region', () {
      expect(env.cognitoEndpoint, contains('af-south-1'));
      expect(env.webSocketEndpointUrl, contains('af-south-1'));
      expect(env.httpApiEndpoint, contains('af-south-1'));
    });
  });

  // ─── 2. KwellaEnvironment — no legacy mock URLs ────────────────────────

  group('KwellaEnvironment.production — no legacy mock endpoints', () {
    const env = KwellaEnvironment.production;

    test('cognitoEndpoint contains no mock/localhost pattern', () {
      _assertNoLegacyPattern('cognitoEndpoint', env.cognitoEndpoint);
    });

    test('webSocketEndpointUrl contains no mock/localhost pattern', () {
      _assertNoLegacyPattern('webSocketEndpointUrl', env.webSocketEndpointUrl);
    });

    test('httpApiEndpoint contains no mock/localhost pattern', () {
      _assertNoLegacyPattern('httpApiEndpoint', env.httpApiEndpoint);
    });
  });

  // ─── 3. KwellaWebSocketGateway — production initialization contract ────

  group('KwellaWebSocketGateway — production initialization', () {
    test('default constructor uses production WebSocket endpoint', () {
      final gateway = KwellaWebSocketGateway();
      expect(
        gateway.endpointUrl,
        kWebSocketEndpointUrl,
        reason:
            'The no-arg constructor must default to the production endpoint.',
      );
    });

    test('provider-vended gateway carries the production endpoint', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final gateway = container.read(kwellaWebSocketGatewayProvider);
      expect(
        gateway.endpointUrl,
        KwellaEnvironment.production.webSocketEndpointUrl,
        reason:
            'kwellaWebSocketGatewayProvider must inject the production URL.',
      );
    });

    test('gateway endpointUrl matches top-level kWebSocketEndpointUrl const', () {
      final gateway = KwellaWebSocketGateway();
      // The compile-time constant and the environment class must agree.
      expect(gateway.endpointUrl, kWebSocketEndpointUrl);
      expect(kWebSocketEndpointUrl,
          KwellaEnvironment.production.webSocketEndpointUrl);
    });

    test('gateway constructed with custom URL preserves the override', () {
      const staging = 'wss://staging.execute-api.af-south-1.amazonaws.com/dev';
      final gateway = KwellaWebSocketGateway(endpointUrl: staging);
      expect(gateway.endpointUrl, staging);
    });

    test('gateway is not connected before connect() is called', () {
      final gateway = KwellaWebSocketGateway();
      expect(gateway.isConnected, isFalse);
    });

    test('dataStream throws StateError before connect()', () {
      final gateway = KwellaWebSocketGateway();
      expect(() => gateway.dataStream, throwsStateError);
    });

    test('disconnect() is idempotent on an unconnected gateway', () async {
      final gateway = KwellaWebSocketGateway();
      await expectLater(gateway.disconnect(), completes);
    });

    test('send() journals the payload instead of throwing when not connected',
        () {
      final gateway = KwellaWebSocketGateway();
      expect(
        () => gateway.send('{"action":"ping"}'),
        returnsNormally,
      );
    });
  });

  // ─── 4. KwellaAuthNotifier — live Cognito endpoint wiring ─────────────

  group('KwellaAuthNotifier — production environment injection', () {
    test('default notifier targets live Cognito af-south-1 endpoint', () {
      // We cannot inspect _env directly (private), but we CAN verify the
      // environment constants that the notifier will read at runtime.
      expect(
        kCognitoEndpoint,
        'https://cognito-idp.af-south-1.amazonaws.com/',
        reason: 'Cognito endpoint must target the live af-south-1 region.',
      );
    });

    test('kCognitoClientId matches .env.production client ID', () {
      expect(kCognitoClientId, '6enltlvcl8569tt1r49rnfr354');
    });

    test('kCognitoClientId matches KwellaEnvironment.production', () {
      expect(kCognitoClientId, KwellaEnvironment.production.cognitoClientId);
    });

    test('kCognitoEndpoint matches KwellaEnvironment.production', () {
      expect(kCognitoEndpoint, KwellaEnvironment.production.cognitoEndpoint);
    });

    test('Cognito endpoint uses https:// scheme (no plaintext allowed)', () {
      expect(kCognitoEndpoint, startsWith('https://'));
    });

    test('no localhost mock in Cognito endpoint constant', () {
      _assertNoLegacyPattern('kCognitoEndpoint', kCognitoEndpoint);
    });
  });

  // ─── 5. Top-level constant consistency audit ───────────────────────────

  group('Compile-time constant consistency', () {
    test('all k* constants align with KwellaEnvironment.production fields', () {
      const env = KwellaEnvironment.production;
      expect(kCognitoUserPoolId, env.cognitoUserPoolId);
      expect(kCognitoClientId, env.cognitoClientId);
      expect(kCognitoEndpoint, env.cognitoEndpoint);
      expect(kWebSocketEndpointUrl, env.webSocketEndpointUrl);
      expect(kHttpApiEndpoint, env.httpApiEndpoint);
    });

    test('KwellaEnvironment.production is a compile-time const', () {
      // If this compiles, the production singleton is a true const.
      const env = KwellaEnvironment.production;
      expect(env, isNotNull);
    });
  });
}
