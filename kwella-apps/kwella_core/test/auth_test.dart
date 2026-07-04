import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────

/// In-memory mock for FlutterSecureStorage.
class MockFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

/// Controls whether the mock Dio resolves or rejects, and what auth flow
/// scenario is being simulated.
enum MockMode {
  successRider,
  successDriver,
  successRefresh,
  failBadCredentials,
  failRefreshInvalid,
}

/// Interceptor that simulates the Cognito InitiateAuth JSON endpoint contract.
/// Matches on `X-Amz-Target` header to distinguish InitiateAuth from Refresh.
class MockCognitoInterceptor extends Interceptor {
  MockMode mode;

  MockCognitoInterceptor(this.mode);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final target = options.headers['X-Amz-Target'] as String? ?? '';
    final body = options.data as Map<String, dynamic>? ?? {};
    final authFlow = body['AuthFlow'] as String? ?? '';

    // ── Failure paths ──────────────────────────────────────────────────
    if (mode == MockMode.failBadCredentials) {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        error: 'Cognito authentication rejected credentials.',
        response: Response(
          requestOptions: options,
          statusCode: 400,
          data: {
            '__type': 'NotAuthorizedException',
            'message': 'Incorrect username or password.',
          },
        ),
      ));
      return;
    }

    if (mode == MockMode.failRefreshInvalid) {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        error: 'Refresh token is expired or revoked.',
        response: Response(
          requestOptions: options,
          statusCode: 400,
          data: {
            '__type': 'NotAuthorizedException',
            'message': 'Refresh Token has expired',
          },
        ),
      ));
      return;
    }

    // ── Success paths ──────────────────────────────────────────────────

    // Cognito InitiateAuth target must be set correctly.
    assert(
      target == 'AWSCognitoIdentityProviderService.InitiateAuth',
      'Wrong X-Amz-Target header: $target',
    );

    if (authFlow == 'REFRESH_TOKEN_AUTH' || mode == MockMode.successRefresh) {
      // Refresh flow — Cognito does NOT reissue RefreshToken.
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'AuthenticationResult': {
            'IdToken': 'refreshed_id_token_rider',
            'AccessToken': 'refreshed_access_token_rider',
            'ExpiresIn': 3600,
            'TokenType': 'Bearer',
          },
        },
      ));
      return;
    }

    final role =
        mode == MockMode.successDriver ? 'driver' : 'rider';
    handler.resolve(Response(
      requestOptions: options,
      statusCode: 200,
      data: {
        'AuthenticationResult': {
          'IdToken': 'mock_id_token_$role',
          'AccessToken': 'mock_access_token_$role',
          'RefreshToken': 'mock_refresh_token_$role',
          'ExpiresIn': 3600,
          'TokenType': 'Bearer',
        },
      },
    ));
  }
}

// ── Test Suite ────────────────────────────────────────────────────────────

void main() {
  group('Auth Layer Tests', () {
    late MockFlutterSecureStorage mockSecureStorage;
    late TokenVault tokenVault;
    late Dio mockDio;
    late MockCognitoInterceptor mockInterceptor;

    setUp(() {
      mockSecureStorage = MockFlutterSecureStorage();
      tokenVault = TokenVault(storage: mockSecureStorage);

      mockDio = Dio();
      mockInterceptor = MockCognitoInterceptor(MockMode.successRider);
      mockDio.interceptors.add(mockInterceptor);
    });

    test('Initial Auth State is Unauthenticated', () {
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);
      expect(notifier.state.status, KwellaAuthStatus.unauthenticated);
      expect(notifier.state.userId, isNull);
      expect(notifier.state.email, isNull);
      expect(notifier.state.role, isNull);
    });

    test('Successful Sign In as Rider — stores tokens and parses fallback role',
        () async {
      mockInterceptor.mode = MockMode.successRider;
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      await notifier.signInWithEmailAndPassword('rider@kwella.com', 'pass123');

      // The mock token contains 'rider' in the raw string — fallback role.
      expect(notifier.state.status, KwellaAuthStatus.authenticated);
      expect(notifier.state.role, 'rider');

      // All three tokens must be persisted.
      expect(await tokenVault.readIdToken(), 'mock_id_token_rider');
      expect(await tokenVault.readAccessToken(), 'mock_access_token_rider');
      expect(await tokenVault.readRefreshToken(), 'mock_refresh_token_rider');
    });

    test('Successful Sign In as Driver — role resolved from token string',
        () async {
      mockInterceptor.mode = MockMode.successDriver;
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      await notifier.signInWithEmailAndPassword('driver@kwella.com', 'pass123');

      expect(notifier.state.status, KwellaAuthStatus.authenticated);
      expect(notifier.state.role, 'driver');
      expect(await tokenVault.readIdToken(), 'mock_id_token_driver');
    });

    test('Failed Sign In propagates Cognito error message', () async {
      mockInterceptor.mode = MockMode.failBadCredentials;
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      await notifier.signInWithEmailAndPassword('wrong@kwella.com', 'wrong');

      expect(notifier.state.status, KwellaAuthStatus.failure);
      // The interceptor extracts the Cognito `message` field from the body.
      expect(notifier.state.error,
          contains('Incorrect username or password.'));
      expect(notifier.state.userId, isNull);
    });

    test('Sign Out clears tokens and resets state to unauthenticated',
        () async {
      mockInterceptor.mode = MockMode.successRider;
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      await notifier.signInWithEmailAndPassword('rider@kwella.com', 'pass123');
      expect(notifier.state.status, KwellaAuthStatus.authenticated);

      await notifier.signOut();

      expect(notifier.state.status, KwellaAuthStatus.unauthenticated);
      expect(await tokenVault.readIdToken(), isNull);
      expect(await tokenVault.readAccessToken(), isNull);
    });

    test('Check Persisted Session on Startup — restores driver session',
        () async {
      // Pre-populate vault with mock driver tokens.
      await tokenVault.writeIdToken('mock_id_token_driver');
      await tokenVault.writeAccessToken('mock_access_token_driver');

      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      // Give the event loop a tick to complete the async initializer.
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.status, KwellaAuthStatus.authenticated);
      // The fallback role extractor reads 'driver' from the raw token string.
      expect(notifier.state.role, 'driver');
    });

    test('refreshSession() writes new IdToken and AccessToken to vault',
        () async {
      // Pre-populate vault with a stored refresh token.
      await tokenVault.writeRefreshToken('stored_refresh_token_rider');

      mockInterceptor.mode = MockMode.successRefresh;
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      final result = await notifier.refreshSession();

      expect(result, isTrue);
      expect(await tokenVault.readIdToken(), 'refreshed_id_token_rider');
      expect(await tokenVault.readAccessToken(),
          'refreshed_access_token_rider');
      // Stored refresh token is unchanged — Cognito does not reissue it.
      expect(await tokenVault.readRefreshToken(), 'stored_refresh_token_rider');
    });

    test('refreshSession() returns false when refresh token is absent',
        () async {
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      final result = await notifier.refreshSession();

      expect(result, isFalse);
    });

    test('refreshSession() returns false when Cognito rejects the refresh token',
        () async {
      await tokenVault.writeRefreshToken('expired_refresh_token');

      mockInterceptor.mode = MockMode.failRefreshInvalid;
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      final result = await notifier.refreshSession();

      expect(result, isFalse);
    });
  });
}
