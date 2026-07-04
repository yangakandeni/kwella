import 'package:dio/dio.dart';

import '../auth/token_vault.dart';

// ── Custom exception types ────────────────────────────────────────────────

/// Raised when AWS returns a `ThrottlingException` on any Kwella API call.
///
/// This is a [DioException] subclass so it survives Dio v5's internal
/// re-throw pipeline when emitted from an [ErrorInterceptorHandler.reject]
/// call inside [onError].
///
/// Consumers should display a user-friendly "too many requests" message and
/// implement an exponential back-off retry strategy.
class KwellaNetworkThrottlingException extends DioException {
  /// The original AWS error message extracted from the response body.
  final String awsMessage;

  KwellaNetworkThrottlingException({
    required super.requestOptions,
    super.response,
    this.awsMessage =
        'The request was throttled by the server. Please try again shortly.',
  }) : super(
          type: DioExceptionType.badResponse,
          message: awsMessage,
        );

  @override
  String toString() => 'KwellaNetworkThrottlingException: $awsMessage';
}

/// Raised when a Cognito token refresh attempt fails during automatic
/// 401 recovery, indicating the user's session cannot be silently renewed.
///
/// This is a [DioException] subclass so it survives Dio v5's internal
/// re-throw pipeline when emitted from an [ErrorInterceptorHandler.reject]
/// call inside [onError].
///
/// Consumers should redirect the user to the sign-in screen.
class KwellaAuthExpiredException extends DioException {
  KwellaAuthExpiredException({required super.requestOptions})
      : super(
          type: DioExceptionType.unknown,
          message: 'Session has expired. Please sign in again.',
        );

  @override
  String toString() =>
      'KwellaAuthExpiredException: Session has expired. Please sign in again.';
}

// ── Interceptor ───────────────────────────────────────────────────────────

/// A Dio [Interceptor] that guards against raw AWS error payloads leaking to
/// the application layer.
///
/// Responsibilities:
///
/// 1. **401 Unauthorized → Automatic Token Refresh**
///    Reads the stored Cognito refresh token from [TokenVault], invokes the
///    provided [onRefreshNeeded] callback (which should call
///    `KwellaAuthNotifier.refreshSession()`), then retries the original
///    request with the newly issued `AccessToken` from the vault.
///    If refresh fails, a [KwellaAuthExpiredException] is propagated.
///
/// 2. **ThrottlingException → Standardized Client Error**
///    Inspects the AWS response body for the `ThrottlingException` type
///    string and maps it to [KwellaNetworkThrottlingException], preventing
///    raw server stack traces from surfacing in the UI.
///
/// Example registration:
/// ```dart
/// dio.interceptors.add(AwsErrorInterceptor(
///   tokenVault: tokenVault,
///   onRefreshNeeded: () => authNotifier.refreshSession(),
/// ));
/// ```
class AwsErrorInterceptor extends Interceptor {
  final TokenVault _tokenVault;

  /// Callback invoked when a 401 is received. Should execute the Cognito
  /// REFRESH_TOKEN_AUTH flow and persist the new tokens into [_tokenVault].
  /// Returns `true` if the refresh was successful.
  final Future<bool> Function() onRefreshNeeded;

  AwsErrorInterceptor({
    required TokenVault tokenVault,
    required this.onRefreshNeeded,
  }) : _tokenVault = tokenVault;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;

    // ── 1. Throttling Guard ──────────────────────────────────────────────
    if (_isThrottlingError(response)) {
      final awsMessage = _extractAwsMessage(response?.data);
      handler.reject(
        KwellaNetworkThrottlingException(
          requestOptions: err.requestOptions,
          response: response,
          awsMessage: awsMessage,
        ),
      );
      return;
    }

    // ── 2. Token Refresh on 401 ──────────────────────────────────────────
    if (response?.statusCode == 401) {
      try {
        final refreshed = await onRefreshNeeded();

        if (!refreshed) {
          handler.reject(
            KwellaAuthExpiredException(
              requestOptions: err.requestOptions,
            ),
          );
          return;
        }

        // Refresh succeeded — retry the original request with the new token.
        final newAccessToken = await _tokenVault.readAccessToken();
        if (newAccessToken == null) {
          handler.reject(
            KwellaAuthExpiredException(
              requestOptions: err.requestOptions,
            ),
          );
          return;
        }

        // Clone the original request options and inject the refreshed token.
        final retryOptions = err.requestOptions.copyWith(
          headers: {
            ...err.requestOptions.headers,
            'Authorization': 'Bearer $newAccessToken',
          },
        );

        // Re-execute the request via the same Dio instance.
        final dio = Dio(
          BaseOptions(
            baseUrl: retryOptions.baseUrl,
            connectTimeout: retryOptions.connectTimeout,
            receiveTimeout: retryOptions.receiveTimeout,
          ),
        );
        final retryResponse = await dio.fetch(retryOptions);
        handler.resolve(retryResponse);
        return;
      } catch (e) {
        handler.reject(
          KwellaAuthExpiredException(
            requestOptions: err.requestOptions,
          ),
        );
        return;
      }
    }

    // Pass all other errors through unchanged.
    handler.next(err);
  }

  // ── Private helpers ────────────────────────────────────────────────────

  /// Returns `true` if the response body contains an AWS `ThrottlingException`
  /// type indicator in either its `__type` field or raw string body.
  bool _isThrottlingError(Response<dynamic>? response) {
    if (response == null) return false;
    final data = response.data;
    if (data is Map) {
      final type = data['__type']?.toString() ?? '';
      final code = data['code']?.toString() ?? '';
      return type.contains('ThrottlingException') ||
          code.contains('ThrottlingException');
    }
    if (data is String) {
      return data.contains('ThrottlingException');
    }
    return false;
  }

  /// Extracts a human-readable message from an AWS JSON error body.
  String _extractAwsMessage(dynamic data) {
    if (data is Map) {
      return data['message']?.toString() ??
          data['Message']?.toString() ??
          'AWS request was throttled.';
    }
    return 'AWS request was throttled.';
  }
}
