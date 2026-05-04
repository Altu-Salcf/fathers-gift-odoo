import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {

  // --- Singleton Pattern ---
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  // The actual FlutterSecureStorage instance
  final _secureStorage = const FlutterSecureStorage();

  // --- KEYS for Credentials (Permanent Secrets) ---
  static const _clientIdKey = 'oauth_client_id';
  static const _clientSecretKey = 'oauth_client_secret';

  // --- KEYS for Tokens (Short-lived Secrets) ---
  static const _accessTokenKey = 'access_token';
  static const _tokenExpiryKey = 'token_expiry';

  // --- Client ID/Secret Methods ---
  Future<void> saveClientId(String clientId) async {
    await _secureStorage.write(key: _clientIdKey, value: clientId);
  }

  Future<String?> getClientId() async {
    return await _secureStorage.read(key: _clientIdKey);
  }

  Future<void> saveClientSecret(String clientSecret) async {
    await _secureStorage.write(key: _clientSecretKey, value: clientSecret);
  }

  Future<String?> getClientSecret() async {
    return await _secureStorage.read(key: _clientSecretKey);
  }

  // --- Access Token Methods ---

  Future<void> saveAccessToken(String token, int expiryTimestamp) async {
    await _secureStorage.write(key: _accessTokenKey, value: token);
    // flutter_secure_storage only supports strings
    await _secureStorage.write(key: _tokenExpiryKey, value: expiryTimestamp.toString());
  }

  Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: _accessTokenKey);
  }

  Future<int?> getTokenExpiry() async {
    final expiryString = await _secureStorage.read(key: _tokenExpiryKey);
    // Attempt to parse the stored string back into an integer
    return expiryString != null ? int.tryParse(expiryString) : null;
  }
}