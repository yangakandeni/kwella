import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_core/kwella_core.dart';

/// In-memory [FlutterSecureStorage] stand-in so [KwellaAuthNotifier] never
/// touches the real secure-storage platform channel in widget tests.
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

/// Controls how the mock Cognito endpoint responds to
/// `RespondToAuthChallenge` — `InitiateAuth` always succeeds immediately,
/// since these tests only exercise the phone-entry/OTP screens, not
/// sign-up provisioning (already covered by kwella_core's auth_test.dart).
enum MockOtpVerifyMode { correct, incorrectRetry }

/// Minimal stand-in for the Cognito `CUSTOM_AUTH` JSON endpoint, scoped to
/// just what the rider auth screens need: issuing an OTP challenge and
/// resolving `RespondToAuthChallenge` per [mode].
class MockCognitoInterceptor extends Interceptor {
  MockOtpVerifyMode mode;

  MockCognitoInterceptor(this.mode);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final target = options.headers['X-Amz-Target'] as String? ?? '';

    if (target == 'AWSCognitoIdentityProviderService.InitiateAuth') {
      handler.resolve(Response(
        requestOptions: options,
        statusCode: 200,
        data: jsonEncode({
          'ChallengeName': 'CUSTOM_CHALLENGE',
          'Session': 'mock_session_1',
          'ChallengeParameters': <String, dynamic>{},
        }),
      ));
      return;
    }

    if (target == 'AWSCognitoIdentityProviderService.RespondToAuthChallenge') {
      if (mode == MockOtpVerifyMode.correct) {
        handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: jsonEncode({
            'AuthenticationResult': {
              'IdToken': 'mock_id_token_rider',
              'AccessToken': 'mock_access_token_rider',
              'RefreshToken': 'mock_refresh_token_rider',
              'ExpiresIn': 3600,
              'TokenType': 'Bearer',
            },
          }),
        ));
      } else {
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
      }
      return;
    }

    handler.reject(DioException(
      requestOptions: options,
      error: 'Unexpected X-Amz-Target header: $target',
    ));
  }
}

/// Builds a real [KwellaAuthNotifier] wired to the mock Cognito endpoint —
/// used to override [kwellaAuthNotifierProvider] in widget tests so the
/// screens exercise their real request/response handling without hitting
/// the network or secure storage.
KwellaAuthNotifier buildMockAuthNotifier(MockCognitoInterceptor interceptor) {
  final dio = Dio();
  dio.interceptors.add(interceptor);
  return KwellaAuthNotifier(
    tokenVault: TokenVault(storage: MockFlutterSecureStorage()),
    dio: dio,
  );
}
