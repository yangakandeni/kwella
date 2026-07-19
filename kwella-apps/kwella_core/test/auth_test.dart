import 'dart:convert';

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
  otpChallengeIssued,
  failRequestOtpUnknownPhone,
  otpVerifyCorrectRider,
  otpVerifyCorrectDriver,
  otpVerifyIncorrectRetry,
  otpVerifyLockedOut,
  successRefresh,
  failRefreshInvalid,
}

/// Interceptor that simulates the Cognito CUSTOM_AUTH JSON endpoint contract
/// (`InitiateAuth` + `RespondToAuthChallenge`), matching on `X-Amz-Target`.
///
/// Request/response bodies are JSON-encoded strings, not raw `Map`s — this
/// mirrors the real wire contract, since Dio's transformer only auto
/// encodes/decodes JSON for the `application/json` MIME type, not Cognito's
/// `application/x-amz-json-1.1`. A mock that skipped this string round-trip
/// previously masked a bug where the request body was sent URL-encoded
/// instead of as JSON, and the response body was never parsed at all.
class MockCognitoInterceptor extends Interceptor {
  MockMode mode;

  MockCognitoInterceptor(this.mode);

  /// The raw `options.data` seen by the most recent request, captured so
  /// tests can assert it's a JSON string rather than a `Map` — a `Map`
  /// would mean Dio silently URL-encoded it instead of sending JSON, since
  /// Dio only auto-encodes `Map` data for the `application/json` MIME type,
  /// not Cognito's `application/x-amz-json-1.1`.
  dynamic lastRequestBody;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastRequestBody = options.data;
    final target = options.headers['X-Amz-Target'] as String? ?? '';
    final rawData = options.data;
    final body = rawData is String
        ? jsonDecode(rawData) as Map<String, dynamic>
        : (rawData as Map<String, dynamic>? ?? {});
    final authFlow = body['AuthFlow'] as String? ?? '';

    if (target == 'AWSCognitoIdentityProviderService.InitiateAuth') {
      if (authFlow == 'REFRESH_TOKEN_AUTH') {
        _handleRefresh(options, handler);
        return;
      }
      _handleRequestOtp(options, handler);
      return;
    }

    if (target == 'AWSCognitoIdentityProviderService.RespondToAuthChallenge') {
      _handleVerifyOtp(options, handler);
      return;
    }

    throw StateError('Unexpected X-Amz-Target header: $target');
  }

  void _handleRequestOtp(
      RequestOptions options, RequestInterceptorHandler handler) {
    if (mode == MockMode.failRequestOtpUnknownPhone) {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        error: 'Cognito rejected the InitiateAuth request.',
        response: Response(
          requestOptions: options,
          statusCode: 400,
          data: jsonEncode({
            '__type': 'UserNotFoundException',
            'message': 'User does not exist.',
          }),
        ),
      ));
      return;
    }

    handler.resolve(Response(
      requestOptions: options,
      statusCode: 200,
      data: jsonEncode({
        'ChallengeName': 'CUSTOM_CHALLENGE',
        'Session': 'mock_session_1',
        'ChallengeParameters': <String, dynamic>{},
      }),
    ));
  }

  void _handleVerifyOtp(
      RequestOptions options, RequestInterceptorHandler handler) {
    switch (mode) {
      case MockMode.otpVerifyCorrectRider:
      case MockMode.otpVerifyCorrectDriver:
        final role =
            mode == MockMode.otpVerifyCorrectDriver ? 'driver' : 'rider';
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: jsonEncode({
            'AuthenticationResult': {
              'IdToken': 'mock_id_token_$role',
              'AccessToken': 'mock_access_token_$role',
              'RefreshToken': 'mock_refresh_token_$role',
              'ExpiresIn': 3600,
              'TokenType': 'Bearer',
            },
          }),
        ));
        return;
      case MockMode.otpVerifyIncorrectRetry:
        // Cognito re-issues the challenge with a new Session rather than
        // erroring outright, so the user can retry.
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: jsonEncode({
            'ChallengeName': 'CUSTOM_CHALLENGE',
            'Session': 'mock_session_2',
            'ChallengeParameters': <String, dynamic>{},
          }),
        ));
        return;
      case MockMode.otpVerifyLockedOut:
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          error: 'Cognito locked out the challenge after too many attempts.',
          response: Response(
            requestOptions: options,
            statusCode: 400,
            data: jsonEncode({
              '__type': 'NotAuthorizedException',
              'message': 'Incorrect username or password.',
            }),
          ),
        ));
        return;
      default:
        throw StateError('Unexpected MockMode for RespondToAuthChallenge: $mode');
    }
  }

  void _handleRefresh(
      RequestOptions options, RequestInterceptorHandler handler) {
    if (mode == MockMode.failRefreshInvalid) {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        error: 'Refresh token is expired or revoked.',
        response: Response(
          requestOptions: options,
          statusCode: 400,
          data: jsonEncode({
            '__type': 'NotAuthorizedException',
            'message': 'Refresh Token has expired',
          }),
        ),
      ));
      return;
    }

    handler.resolve(Response(
      requestOptions: options,
      statusCode: 200,
      data: jsonEncode({
        'AuthenticationResult': {
          'IdToken': 'refreshed_id_token_rider',
          'AccessToken': 'refreshed_access_token_rider',
          'ExpiresIn': 3600,
          'TokenType': 'Bearer',
        },
      }),
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
      mockInterceptor = MockCognitoInterceptor(MockMode.otpChallengeIssued);
      mockDio.interceptors.add(mockInterceptor);
    });

    test('Initial Auth State is Unauthenticated', () {
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);
      expect(notifier.state.status, KwellaAuthStatus.unauthenticated);
      expect(notifier.state.userId, isNull);
      expect(notifier.state.email, isNull);
      expect(notifier.state.role, isNull);
    });

    test(
        'requestOtp() success — transitions to otpRequired with session and phone number',
        () async {
      mockInterceptor.mode = MockMode.otpChallengeIssued;
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      await notifier.requestOtp('+27821234567');

      expect(notifier.state.status, KwellaAuthStatus.otpRequired);
      expect(notifier.state.cognitoSession, 'mock_session_1');
      expect(notifier.state.pendingPhoneNumber, '+27821234567');
    });

    test(
        'requestOtp() sends a JSON-encoded string body, not a raw Map '
        '(Cognito\'s application/x-amz-json-1.1 content type is not '
        'auto-encoded by Dio)', () async {
      mockInterceptor.mode = MockMode.otpChallengeIssued;
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      await notifier.requestOtp('+27821234567');

      expect(mockInterceptor.lastRequestBody, isA<String>());
      final decoded = jsonDecode(mockInterceptor.lastRequestBody as String)
          as Map<String, dynamic>;
      expect(decoded['AuthFlow'], 'CUSTOM_AUTH');
      expect(decoded['AuthParameters']['USERNAME'], '+27821234567');
    });

    test('requestOtp() failure — unknown phone number surfaces Cognito error',
        () async {
      mockInterceptor.mode = MockMode.failRequestOtpUnknownPhone;
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      await notifier.requestOtp('+27000000000');

      expect(notifier.state.status, KwellaAuthStatus.failure);
      expect(notifier.state.error, contains('User does not exist.'));
    });

    test('verifyOtp() correct code as rider — authenticates and persists tokens',
        () async {
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);
      await notifier.requestOtp('+27821234567');

      mockInterceptor.mode = MockMode.otpVerifyCorrectRider;
      await notifier.verifyOtp('123456');

      expect(notifier.state.status, KwellaAuthStatus.authenticated);
      expect(notifier.state.role, 'rider');
      expect(await tokenVault.readIdToken(), 'mock_id_token_rider');
      expect(await tokenVault.readAccessToken(), 'mock_access_token_rider');
      expect(await tokenVault.readRefreshToken(), 'mock_refresh_token_rider');
    });

    test(
        'verifyOtp() correct code as driver — role resolved from token string',
        () async {
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);
      await notifier.requestOtp('+27831234567');

      mockInterceptor.mode = MockMode.otpVerifyCorrectDriver;
      await notifier.verifyOtp('123456');

      expect(notifier.state.status, KwellaAuthStatus.authenticated);
      expect(notifier.state.role, 'driver');
      expect(await tokenVault.readIdToken(), 'mock_id_token_driver');
    });

    test(
        'verifyOtp() incorrect code — stays otpRequired with a retry error and persists no tokens',
        () async {
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);
      await notifier.requestOtp('+27821234567');

      mockInterceptor.mode = MockMode.otpVerifyIncorrectRetry;
      await notifier.verifyOtp('000000');

      expect(notifier.state.status, KwellaAuthStatus.otpRequired);
      expect(notifier.state.error, isNotNull);
      expect(notifier.state.cognitoSession, 'mock_session_2');
      expect(await tokenVault.readIdToken(), isNull);
    });

    test(
        'verifyOtp() locked out after repeated failures — transitions to failure',
        () async {
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);
      await notifier.requestOtp('+27821234567');

      mockInterceptor.mode = MockMode.otpVerifyLockedOut;
      await notifier.verifyOtp('000000');

      expect(notifier.state.status, KwellaAuthStatus.failure);
      expect(notifier.state.error, contains('Incorrect username or password.'));
    });

    test(
        'verifyOtp() with no pending challenge fails gracefully without crashing',
        () async {
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      await notifier.verifyOtp('123456');

      expect(notifier.state.status, KwellaAuthStatus.failure);
      expect(notifier.state.error, isNotNull);
    });

    test('Sign Out clears tokens and resets state to unauthenticated',
        () async {
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);
      await notifier.requestOtp('+27821234567');

      mockInterceptor.mode = MockMode.otpVerifyCorrectRider;
      await notifier.verifyOtp('123456');
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
