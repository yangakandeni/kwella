import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Vault responsible for secure asynchronous persistent storage of OAuth2 / AWS Cognito JWTs.
class TokenVault {
  final FlutterSecureStorage _storage;

  TokenVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _accessTokenKey = 'kwella_access_token';
  static const String _idTokenKey = 'kwella_id_token';
  static const String _refreshTokenKey = 'kwella_refresh_token';

  /// Write the OAuth2 access token to secure storage.
  Future<void> writeAccessToken(String token) async {
    await _storage.write(key: _accessTokenKey, value: token);
  }

  /// Read the OAuth2 access token from secure storage.
  Future<String?> readAccessToken() async {
    return await _storage.read(key: _accessTokenKey);
  }

  /// Delete the OAuth2 access token from secure storage.
  Future<void> deleteAccessToken() async {
    await _storage.delete(key: _accessTokenKey);
  }

  /// Write the ID token to secure storage.
  Future<void> writeIdToken(String token) async {
    await _storage.write(key: _idTokenKey, value: token);
  }

  /// Read the ID token from secure storage.
  Future<String?> readIdToken() async {
    return await _storage.read(key: _idTokenKey);
  }

  /// Delete the ID token from secure storage.
  Future<void> deleteIdToken() async {
    await _storage.delete(key: _idTokenKey);
  }

  /// Write the refresh token to secure storage.
  Future<void> writeRefreshToken(String token) async {
    await _storage.write(key: _refreshTokenKey, value: token);
  }

  /// Read the refresh token from secure storage.
  Future<String?> readRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }

  /// Delete the refresh token from secure storage.
  Future<void> deleteRefreshToken() async {
    await _storage.delete(key: _refreshTokenKey);
  }

  /// Clears all tokens stored in the secure vault.
  Future<void> clearAll() async {
    await deleteAccessToken();
    await deleteIdToken();
    await deleteRefreshToken();
  }
}
