import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_core/kwella_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────

/// Minimal in-memory FlutterSecureStorage mock.
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

/// Captures the result of [ErrorInterceptorHandler.reject], [.resolve], or
/// [.next] so tests can inspect what the interceptor emitted without
/// going through Dio's internal chain plumbing.
class _CapturingErrorHandler extends ErrorInterceptorHandler {
  DioException? rejected;
  Response<dynamic>? resolved;

  @override
  void reject(DioException err, [bool callFollowingErrorInterceptor = false]) {
    rejected = err;
  }

  @override
  void resolve(Response<dynamic> response) {
    resolved = response;
  }

  @override
  void next(DioException err) {
    // Pass-through — store as rejected so tests can inspect unchanged errors.
    rejected = err;
  }
}

// ── AwsErrorInterceptor unit tests ────────────────────────────────────────

void main() {
  group('AwsErrorInterceptor — ThrottlingException guard', () {
    late TokenVault tokenVault;
    int refreshCallCount = 0;

    setUp(() {
      refreshCallCount = 0;
      tokenVault = TokenVault(storage: MockFlutterSecureStorage());
    });

    AwsErrorInterceptor buildInterceptor({bool refreshResult = true}) {
      return AwsErrorInterceptor(
        tokenVault: tokenVault,
        onRefreshNeeded: () async {
          refreshCallCount++;
          return refreshResult;
        },
      );
    }

    RequestOptions makeOpts() =>
        RequestOptions(path: '/test', baseUrl: 'https://example.com');

    test(
        'maps AWS ThrottlingException in JSON body to KwellaNetworkThrottlingException',
        () async {
      final interceptor = buildInterceptor();
      final opts = makeOpts();
      final err = DioException(
        requestOptions: opts,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: opts,
          statusCode: 429,
          data: {'__type': 'ThrottlingException', 'message': 'Rate exceeded'},
        ),
      );

      final handler = _CapturingErrorHandler();
      await interceptor.onError(err, handler);

      expect(handler.rejected, isA<KwellaNetworkThrottlingException>());
      // Throttling is NOT a 401 — refresh must NOT be triggered.
      expect(refreshCallCount, 0);
    });

    test(
        'maps ThrottlingException in raw string body to KwellaNetworkThrottlingException',
        () async {
      final interceptor = buildInterceptor();
      final opts = makeOpts();
      final err = DioException(
        requestOptions: opts,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: opts,
          statusCode: 429,
          data: 'ThrottlingException: Rate exceeded for this resource.',
        ),
      );

      final handler = _CapturingErrorHandler();
      await interceptor.onError(err, handler);

      expect(handler.rejected, isA<KwellaNetworkThrottlingException>());
      expect(refreshCallCount, 0);
    });

    test('AWS code field ThrottlingException is also caught', () async {
      final interceptor = buildInterceptor();
      final opts = makeOpts();
      final err = DioException(
        requestOptions: opts,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: opts,
          statusCode: 400,
          data: {'code': 'ThrottlingException', 'message': 'Too many requests'},
        ),
      );

      final handler = _CapturingErrorHandler();
      await interceptor.onError(err, handler);

      expect(handler.rejected, isA<KwellaNetworkThrottlingException>());
    });
  });

  group('AwsErrorInterceptor — 401 Token Refresh hook', () {
    late MockFlutterSecureStorage mockStorage;
    late TokenVault tokenVault;

    setUp(() {
      mockStorage = MockFlutterSecureStorage();
      tokenVault = TokenVault(storage: mockStorage);
    });

    RequestOptions makeOpts() =>
        RequestOptions(path: '/protected', baseUrl: 'https://example.com');

    DioException make401(RequestOptions opts) => DioException(
          requestOptions: opts,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: opts,
            statusCode: 401,
            data: {'message': 'Unauthorized'},
          ),
        );

    test('calls onRefreshNeeded callback exactly once on 401', () async {
      int callCount = 0;
      final interceptor = AwsErrorInterceptor(
        tokenVault: tokenVault,
        onRefreshNeeded: () async {
          callCount++;
          await tokenVault.writeAccessToken('refreshed_access_token');
          return true;
        },
      );
      final opts = makeOpts();

      final handler = _CapturingErrorHandler();
      await interceptor.onError(make401(opts), handler);

      expect(callCount, 1);
    });

    test(
        'emits KwellaAuthExpiredException when refresh callback returns false',
        () async {
      final interceptor = AwsErrorInterceptor(
        tokenVault: tokenVault,
        onRefreshNeeded: () async => false,
      );
      final opts = makeOpts();

      final handler = _CapturingErrorHandler();
      await interceptor.onError(make401(opts), handler);

      expect(handler.rejected, isA<KwellaAuthExpiredException>());
    });

    test(
        'emits KwellaAuthExpiredException when vault has no AccessToken after refresh',
        () async {
      // Refresh succeeds but writes no new access token.
      final interceptor = AwsErrorInterceptor(
        tokenVault: tokenVault,
        onRefreshNeeded: () async => true, // Returns true but writes nothing.
      );
      final opts = makeOpts();

      final handler = _CapturingErrorHandler();
      await interceptor.onError(make401(opts), handler);

      expect(handler.rejected, isA<KwellaAuthExpiredException>());
    });

    test('passes non-401 / non-throttle errors through via next()', () async {
      final interceptor = AwsErrorInterceptor(
        tokenVault: tokenVault,
        onRefreshNeeded: () async => true,
      );
      final opts = makeOpts();
      final err = DioException(
        requestOptions: opts,
        type: DioExceptionType.badResponse,
        response:
            Response(requestOptions: opts, statusCode: 500, data: 'error'),
      );

      final handler = _CapturingErrorHandler();
      await interceptor.onError(err, handler);

      // The handler's next() stores the error as rejected — but it's the
      // original unmodified DioException.
      expect(handler.rejected, isNotNull);
      expect(handler.rejected, isNot(isA<KwellaNetworkThrottlingException>()));
      expect(handler.rejected, isNot(isA<KwellaAuthExpiredException>()));
      expect(handler.rejected!.response?.statusCode, 500);
    });
  });

  // ── KwellaWebSocketGateway unit contract ──────────────────────────────────

  group('KwellaWebSocketGateway — unit contract', () {
    test('isConnected is false before connect() is called', () {
      final gateway = KwellaWebSocketGateway();
      expect(gateway.isConnected, isFalse);
    });

    test('dataStream throws StateError before connect() is called', () {
      final gateway = KwellaWebSocketGateway();
      expect(() => gateway.dataStream, throwsStateError);
    });

    test('disconnect() is idempotent when already disconnected', () async {
      final gateway = KwellaWebSocketGateway();
      // Must not throw when called without a prior connect().
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

    test('status starts as disconnected and is exposed via statusStream', () {
      final gateway = KwellaWebSocketGateway();
      expect(gateway.status, WebSocketStatus.disconnected);
      expect(gateway.statusStream, isA<Stream<WebSocketStatus>>());
    });

    test('disconnect() keeps status at disconnected', () async {
      final gateway = KwellaWebSocketGateway();
      await gateway.disconnect();
      expect(gateway.status, WebSocketStatus.disconnected);
    });
  });
}
