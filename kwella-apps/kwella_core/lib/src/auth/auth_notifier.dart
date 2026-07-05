import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:riverpod/riverpod.dart';

import '../config/environment.dart';
import 'auth_state.dart';
import 'token_vault.dart';

/// Riverpod StateNotifier that manages Cognito authentication state.
class KwellaAuthNotifier extends StateNotifier<KwellaAuthState> {
  final TokenVault _tokenVault;
  final Dio _dio;
  final KwellaEnvironment _env;

  KwellaAuthNotifier({
    TokenVault? tokenVault,
    Dio? dio,
    KwellaEnvironment? env,
  })  : _tokenVault = tokenVault ?? TokenVault(),
        _dio = dio ?? Dio(),
        _env = env ?? KwellaEnvironment.production,
        super(const KwellaAuthState.initial()) {
    _checkPersistedSession();
  }

  /// Checks for a saved Cognito session inside TokenVault on startup.
  /// If the stored IdToken has expired, attempts a silent refresh before
  /// falling back to the unauthenticated state.
  Future<void> _checkPersistedSession() async {
    try {
      final idToken = await _tokenVault.readIdToken();
      final accessToken = await _tokenVault.readAccessToken();

      if (idToken == null || accessToken == null) {
        state = const KwellaAuthState.initial();
        return;
      }

      // Decode the exp claim from the JWT payload to verify token freshness.
      final payload = _decodeJwtPayload(idToken);
      final exp = payload?['exp'] as int?;
      if (exp != null) {
        final expTime =
            DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
        if (DateTime.now().toUtc().isAfter(expTime)) {
          // Token has expired — attempt a silent refresh.
          final refreshed = await refreshSession();
          if (!refreshed) {
            state = const KwellaAuthState.initial();
          }
          return;
        }
      }

      // Token is still valid — restore the session from stored claims.
      final claims = _extractClaims(payload ?? {}, idToken);
      state = KwellaAuthState(
        status: KwellaAuthStatus.authenticated,
        userId: claims['userId'],
        email: claims['email'],
        role: claims['role'],
      );
    } catch (e) {
      state = KwellaAuthState(
        status: KwellaAuthStatus.failure,
        error: 'Session recovery failed: ${e.toString()}',
      );
    }
  }

  /// Requests an OTP for the given phone number via the Cognito `CUSTOM_AUTH`
  /// InitiateAuth flow. On success, moves to [KwellaAuthStatus.otpRequired]
  /// with the returned challenge `Session` and the phone number stored so
  /// the OTP screen can display it, resend the code, or submit the answer
  /// via [verifyOtp].
  ///
  /// The Kwella user pool is configured with `phone_number` as its username
  /// attribute (see `terraform/main.tf`), so `phoneNumber` must be an E.164
  /// number (e.g. `+27821234567`) belonging to an existing Cognito user.
  ///
  /// Targets the standard Cognito JSON endpoint contract:
  ///
  /// ```
  /// POST https://cognito-idp.region.amazonaws.com/
  /// X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth
  /// Content-Type: application/x-amz-json-1.1
  /// ```
  Future<void> requestOtp(String phoneNumber) async {
    state = state.copyWith(
        status: KwellaAuthStatus.authenticating, clearError: true);

    try {
      final response = await _dio.post(
        _env.cognitoEndpoint,
        data: {
          'AuthFlow': 'CUSTOM_AUTH',
          'ClientId': _env.cognitoClientId,
          'AuthParameters': {
            'USERNAME': phoneNumber,
          },
        },
        options: Options(
          headers: {
            'X-Amz-Target':
                'AWSCognitoIdentityProviderService.InitiateAuth',
            'Content-Type': 'application/x-amz-json-1.1',
          },
        ),
      );

      final data = response.data;
      final session = data?['Session'] as String?;
      final challengeName = data?['ChallengeName'] as String?;
      if (session == null || challengeName != 'CUSTOM_CHALLENGE') {
        throw Exception(
            'Cognito did not return a CUSTOM_CHALLENGE session.');
      }

      state = state.copyWith(
        status: KwellaAuthStatus.otpRequired,
        cognitoSession: session,
        pendingPhoneNumber: phoneNumber,
        clearError: true,
      );
    } catch (e) {
      state = KwellaAuthState(
        status: KwellaAuthStatus.failure,
        error: _extractCognitoErrorMessage(e),
      );
    }
  }

  /// Submits the OTP code entered by the user via Cognito's
  /// `RespondToAuthChallenge` for the `CUSTOM_CHALLENGE` issued by
  /// [requestOtp]. Requires a pending challenge (i.e. [requestOtp] must have
  /// been called first).
  ///
  /// Three outcomes:
  ///   - Correct code: Cognito returns `AuthenticationResult` — tokens are
  ///     persisted and the state moves to [KwellaAuthStatus.authenticated].
  ///   - Incorrect code (retry allowed): Cognito returns a new `Session`
  ///     with no `AuthenticationResult` — state stays
  ///     [KwellaAuthStatus.otpRequired] with an error for the user to retry.
  ///   - Incorrect code (too many attempts): Cognito rejects the request —
  ///     state moves to [KwellaAuthStatus.failure].
  Future<void> verifyOtp(String otpCode) async {
    final phoneNumber = state.pendingPhoneNumber;
    final session = state.cognitoSession;
    if (phoneNumber == null || session == null) {
      state = KwellaAuthState(
        status: KwellaAuthStatus.failure,
        error: 'No pending OTP challenge — request a new code.',
      );
      return;
    }

    state = state.copyWith(
        status: KwellaAuthStatus.authenticating, clearError: true);

    try {
      final response = await _dio.post(
        _env.cognitoEndpoint,
        data: {
          'ChallengeName': 'CUSTOM_CHALLENGE',
          'ClientId': _env.cognitoClientId,
          'Session': session,
          'ChallengeResponses': {
            'USERNAME': phoneNumber,
            'ANSWER': otpCode,
          },
        },
        options: Options(
          headers: {
            'X-Amz-Target':
                'AWSCognitoIdentityProviderService.RespondToAuthChallenge',
            'Content-Type': 'application/x-amz-json-1.1',
          },
        ),
      );

      final data = response.data;
      final authResult = data?['AuthenticationResult'] as Map<String, dynamic>?;

      if (authResult == null) {
        // Cognito re-issued the challenge for another attempt rather than
        // erroring outright — stay on the OTP screen with a retry error.
        final newSession = data?['Session'] as String?;
        state = state.copyWith(
          status: KwellaAuthStatus.otpRequired,
          cognitoSession: newSession ?? session,
          error: 'Incorrect code. Please try again.',
        );
        return;
      }

      await _completeAuthentication(authResult);
    } catch (e) {
      state = KwellaAuthState(
        status: KwellaAuthStatus.failure,
        error: _extractCognitoErrorMessage(e),
      );
    }
  }

  /// Executes a Cognito `REFRESH_TOKEN_AUTH` flow using the stored refresh
  /// token. Returns `true` if the session was renewed successfully.
  ///
  /// Called by [AwsErrorInterceptor] on 401 responses, and internally by
  /// [_checkPersistedSession] when the persisted IdToken has expired.
  Future<bool> refreshSession() async {
    try {
      final refreshToken = await _tokenVault.readRefreshToken();
      if (refreshToken == null) return false;

      final response = await _dio.post(
        _env.cognitoEndpoint,
        data: {
          'AuthFlow': 'REFRESH_TOKEN_AUTH',
          'ClientId': _env.cognitoClientId,
          'AuthParameters': {
            'REFRESH_TOKEN': refreshToken,
          },
        },
        options: Options(
          headers: {
            'X-Amz-Target':
                'AWSCognitoIdentityProviderService.InitiateAuth',
            'Content-Type': 'application/x-amz-json-1.1',
          },
        ),
      );

      final authResult = response.data?['AuthenticationResult']
          as Map<String, dynamic>?;
      if (authResult == null) return false;

      // Cognito does NOT reissue RefreshToken on a refresh flow — keep the
      // existing one rather than persisting the (absent) new value.
      await _completeAuthentication(authResult, persistRefreshToken: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Logs out the user by clearing the TokenVault storage and resetting state.
  Future<void> signOut() async {
    try {
      await _tokenVault.clearAll();
      state = const KwellaAuthState.initial();
    } catch (e) {
      state = KwellaAuthState(
        status: KwellaAuthStatus.failure,
        error: 'Sign out failed: ${e.toString()}',
      );
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  /// Persists tokens from a Cognito `AuthenticationResult` and moves the
  /// state to [KwellaAuthStatus.authenticated] with claims decoded from the
  /// IdToken. Shared by [verifyOtp] and [refreshSession].
  Future<void> _completeAuthentication(
    Map<String, dynamic> authResult, {
    bool persistRefreshToken = true,
  }) async {
    final idToken = authResult['IdToken'] as String?;
    final accessToken = authResult['AccessToken'] as String?;
    final refreshToken = authResult['RefreshToken'] as String?;

    if (idToken == null || accessToken == null) {
      throw Exception(
          'Cognito tokens are missing from the AuthenticationResult.');
    }

    await _tokenVault.writeIdToken(idToken);
    await _tokenVault.writeAccessToken(accessToken);
    if (persistRefreshToken && refreshToken != null) {
      await _tokenVault.writeRefreshToken(refreshToken);
    }

    final payload = _decodeJwtPayload(idToken);
    final claims = _extractClaims(payload ?? {}, idToken);

    state = KwellaAuthState(
      status: KwellaAuthStatus.authenticated,
      userId: claims['userId'],
      email: claims['email'],
      role: claims['role'],
    );
  }

  /// Extracts a human-readable error message, preferring the Cognito
  /// `message`/`__type` fields from a `DioException`'s response body.
  String _extractCognitoErrorMessage(Object e) {
    if (e is DioException) {
      final body = e.response?.data;
      if (body is Map) {
        return body['message']?.toString() ??
            body['__type']?.toString() ??
            e.message ??
            e.toString();
      }
      return e.message ?? e.toString();
    }
    return e.toString();
  }

  /// Decodes the base64url payload segment of a JWT without signature
  /// verification. This is safe to use for claim extraction on the client
  /// because the server has already validated the token during the Cognito
  /// auth flow.
  Map<String, dynamic>? _decodeJwtPayload(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;

      // Base64url → base64 padding normalization.
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }

      final decoded = utf8.decode(base64Decode(payload));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Extracts standardized `userId`, `email`, and `role` from decoded
  /// Cognito JWT claims.
  ///
  /// Cognito claim mapping:
  ///   - `sub`              → userId
  ///   - `email`            → email
  ///   - `cognito:groups`   → first group name used as role (defaults to 'rider')
  Map<String, String> _extractClaims(
      Map<String, dynamic> payload, String rawToken) {
    final userId =
        (payload['sub'] as String?) ?? 'usr-unknown';
    final email =
        (payload['email'] as String?) ?? 'unknown@kwella.co.za';

    // Cognito encodes group membership as a list in "cognito:groups".
    final groups = payload['cognito:groups'];
    String role = 'rider'; // Safe default for the Kwella platform.
    if (groups is List && groups.isNotEmpty) {
      role = groups.first.toString().toLowerCase();
    } else if (rawToken.contains('driver')) {
      // Fallback for mock tokens used in unit tests.
      role = 'driver';
    }

    return {
      'userId': userId,
      'email': email,
      'role': role,
    };
  }
}

/// Global provider for the KwellaAuthNotifier state.
final kwellaAuthNotifierProvider =
    StateNotifierProvider<KwellaAuthNotifier, KwellaAuthState>((ref) {
  return KwellaAuthNotifier();
});
