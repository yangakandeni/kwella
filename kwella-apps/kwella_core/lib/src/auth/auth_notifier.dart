import 'package:dio/dio.dart';
import 'package:riverpod/riverpod.dart';

import 'auth_state.dart';
import 'token_vault.dart';

/// Riverpod StateNotifier that manages Cognito authentication state.
class KwellaAuthNotifier extends StateNotifier<KwellaAuthState> {
  final TokenVault _tokenVault;
  final Dio _dio;

  KwellaAuthNotifier({
    TokenVault? tokenVault,
    Dio? dio,
  })  : _tokenVault = tokenVault ?? TokenVault(),
        _dio = dio ?? Dio(),
        super(const KwellaAuthState.initial()) {
    _checkPersistedSession();
  }

  /// Internal initializer checking for any saved Cognito session inside TokenVault.
  Future<void> _checkPersistedSession() async {
    try {
      final idToken = await _tokenVault.readIdToken();
      final accessToken = await _tokenVault.readAccessToken();

      if (idToken != null && accessToken != null) {
        // =====================================================================
        // STRUCTURAL PLACEHOLDER: JWT EXPIRATION CHECK
        // =====================================================================
        // TODO: Implement parsing of the JWT expiration (exp) claim to check validity.
        // Steps to add here in production:
        // 1. Extract the payload segment from [idToken] (splitting on '.' and base64url-decoding the second part).
        // 2. Parse the payload as JSON to retrieve the 'exp' integer value (UTC Unix timestamp).
        // 3. Compare with the current timestamp:
        //    final expTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
        //    if (DateTime.now().toUtc().isAfter(expTime)) {
        //      // Access token has expired; attempt refresh flow using the stored RefreshToken
        //      // or transition state back to unauthenticated if refresh fails.
        //      // await _refreshSession();
        //      // return;
        //    }
        // =====================================================================

        // Recover user attributes from the verified token
        final claims = _decodeMockClaims(idToken);
        state = KwellaAuthState(
          status: KwellaAuthStatus.authenticated,
          userId: claims['userId'],
          email: claims['email'],
          role: claims['role'],
        );
      } else {
        state = const KwellaAuthState.initial();
      }
    } catch (e) {
      state = KwellaAuthState(
        status: KwellaAuthStatus.failure,
        error: 'Session recovery failed: ${e.toString()}',
      );
    }
  }

  /// Signs in the user using their email and password.
  /// Mocks a call targeting our AWS Cognito auth flow endpoint contract.
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    state = state.copyWith(status: KwellaAuthStatus.authenticating, clearError: true);

    try {
      // Make a request targeting our authentication endpoint contract using Dio.
      final response = await _dio.post(
        'https://auth.kwella.com/oauth2/token',
        data: {
          'grant_type': 'password',
          'username': email,
          'password': password,
        },
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      final data = response.data;
      if (data == null) {
        throw Exception("Auth endpoint returned an empty body.");
      }

      // Support Cognito direct nested format (AuthenticationResult) or flat format
      final authResult = data['AuthenticationResult'] as Map<String, dynamic>? ?? data;

      final idToken = authResult['IdToken'] as String?;
      final accessToken = authResult['AccessToken'] as String?;
      final refreshToken = authResult['RefreshToken'] as String?;

      if (idToken == null || accessToken == null) {
        throw Exception("Received credentials did not contain standard Cognito tokens.");
      }

      // Persist the AWS Cognito tokens securely
      await _tokenVault.writeIdToken(idToken);
      await _tokenVault.writeAccessToken(accessToken);
      if (refreshToken != null) {
        await _tokenVault.writeRefreshToken(refreshToken);
      }

      // Mock the extraction of user attributes/groups/role from Cognito token claims
      final claims = _decodeMockClaims(idToken);

      state = KwellaAuthState(
        status: KwellaAuthStatus.authenticated,
        userId: claims['userId'],
        email: claims['email'],
        role: claims['role'],
      );
    } catch (e) {
      String errMsg = e.toString();
      if (e is DioException) {
        errMsg = e.message ?? e.toString();
      }
      state = KwellaAuthState(
        status: KwellaAuthStatus.failure,
        error: errMsg,
      );
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

  /// Mocks the extraction of user properties and standard AWS Cognito user groups/roles
  /// from the payload of a parsed ID Token.
  Map<String, String> _decodeMockClaims(String idToken) {
    // AWS Cognito maps groups (e.g. cognito:groups) to determine roles like 'driver' or 'rider'.
    // Here we inspect token metadata patterns or fallback to sensible defaults.
    String role = 'rider';
    String email = 'user@kwella.com';
    String userId = 'usr-mock-cognito-id-12345';

    if (idToken.contains('driver')) {
      role = 'driver';
      email = 'driver@kwella.com';
      userId = 'usr-mock-driver-12345';
    } else if (idToken.contains('rider')) {
      role = 'rider';
      email = 'rider@kwella.com';
      userId = 'usr-mock-rider-12345';
    } else if (idToken.contains('admin')) {
      role = 'admin';
      email = 'admin@kwella.com';
      userId = 'usr-mock-admin-12345';
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
