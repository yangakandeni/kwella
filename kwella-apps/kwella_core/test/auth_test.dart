import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';

// Simple in-memory mock for FlutterSecureStorage
class MockFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
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
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

// Simple interceptor to mock Dio responses
class MockDioInterceptor extends Interceptor {
  bool shouldFail = false;
  String mockRole = 'rider';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (shouldFail) {
      handler.reject(
        DioException(
          requestOptions: options,
          error: 'Cognito authentication rejected credentials.',
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 400,
            data: {
              'error': 'NotAuthorizedException',
              'message': 'Incorrect username or password.'
            },
          ),
        ),
      );
    } else {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'AuthenticationResult': {
              'IdToken': 'mock_id_token_$mockRole',
              'AccessToken': 'mock_access_token_$mockRole',
              'RefreshToken': 'mock_refresh_token_$mockRole',
              'ExpiresIn': 3600,
              'TokenType': 'Bearer'
            }
          },
        ),
      );
    }
  }
}

void main() {
  group('Auth Layer Tests', () {
    late MockFlutterSecureStorage mockSecureStorage;
    late TokenVault tokenVault;
    late Dio mockDio;
    late MockDioInterceptor mockInterceptor;

    setUp(() {
      mockSecureStorage = MockFlutterSecureStorage();
      tokenVault = TokenVault(storage: mockSecureStorage);

      mockDio = Dio();
      mockInterceptor = MockDioInterceptor();
      mockDio.interceptors.add(mockInterceptor);
    });

    test('Initial Auth State is Unauthenticated', () {
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);
      expect(notifier.state.status, KwellaAuthStatus.unauthenticated);
      expect(notifier.state.userId, isNull);
      expect(notifier.state.email, isNull);
      expect(notifier.state.role, isNull);
    });

    test('Successful Sign In as Rider', () async {
      mockInterceptor.mockRole = 'rider';
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      await notifier.signInWithEmailAndPassword('rider@kwella.com', 'pass123');

      expect(notifier.state.status, KwellaAuthStatus.authenticated);
      expect(notifier.state.role, 'rider');
      expect(notifier.state.email, 'rider@kwella.com');
      expect(notifier.state.userId, 'usr-mock-rider-12345');

      // Verify token storage
      expect(await tokenVault.readIdToken(), 'mock_id_token_rider');
      expect(await tokenVault.readAccessToken(), 'mock_access_token_rider');
      expect(await tokenVault.readRefreshToken(), 'mock_refresh_token_rider');
    });

    test('Successful Sign In as Driver', () async {
      mockInterceptor.mockRole = 'driver';
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      await notifier.signInWithEmailAndPassword('driver@kwella.com', 'pass123');

      expect(notifier.state.status, KwellaAuthStatus.authenticated);
      expect(notifier.state.role, 'driver');
      expect(notifier.state.email, 'driver@kwella.com');
      expect(notifier.state.userId, 'usr-mock-driver-12345');

      expect(await tokenVault.readIdToken(), 'mock_id_token_driver');
    });

    test('Failed Sign In propagates error', () async {
      mockInterceptor.shouldFail = true;
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      await notifier.signInWithEmailAndPassword('wrong@kwella.com', 'wrong_pass');

      expect(notifier.state.status, KwellaAuthStatus.failure);
      expect(notifier.state.error, contains('Cognito authentication rejected credentials.'));
      expect(notifier.state.userId, isNull);
    });

    test('Sign Out clears tokens and resets state', () async {
      mockInterceptor.mockRole = 'rider';
      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      await notifier.signInWithEmailAndPassword('rider@kwella.com', 'pass123');
      expect(notifier.state.status, KwellaAuthStatus.authenticated);

      await notifier.signOut();

      expect(notifier.state.status, KwellaAuthStatus.unauthenticated);
      expect(await tokenVault.readIdToken(), isNull);
      expect(await tokenVault.readAccessToken(), isNull);
    });

    test('Check Persisted Session on Startup', () async {
      // Simulate stored tokens
      await tokenVault.writeIdToken('mock_id_token_driver');
      await tokenVault.writeAccessToken('mock_access_token_driver');

      final notifier = KwellaAuthNotifier(tokenVault: tokenVault, dio: mockDio);

      // Give event loop time to run the async initialization check
      await Future<void>.delayed(Duration.zero);

      expect(notifier.state.status, KwellaAuthStatus.authenticated);
      expect(notifier.state.role, 'driver');
      expect(notifier.state.userId, 'usr-mock-driver-12345');
    });
  });
}
