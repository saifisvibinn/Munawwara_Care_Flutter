import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Encrypted storage for JWT and session identifiers.
///
/// Non-sensitive prefs (call state, locale, FCM dedupe) stay in
/// [SharedPreferences]. [user_id] is mirrored to prefs for Android native
/// killed-state call decline only — never [auth_token].
class SecureSessionStore {
  SecureSessionStore._();

  static const String _keyToken = 'auth_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUserRole = 'user_role';
  static const String _keyUserFullName = 'user_full_name';
  static const String _keyDeviceBindingId = 'device_binding_id';

  static const String _migrationDoneKey = 'secure_session_migrated_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static Future<String?> getToken() => _storage.read(key: _keyToken);

  static Future<void> setToken(String token) =>
      _storage.write(key: _keyToken, value: token);

  static Future<void> deleteToken() => _storage.delete(key: _keyToken);

  static Future<String?> getUserId() => _storage.read(key: _keyUserId);

  static Future<void> setUserId(String userId) =>
      _storage.write(key: _keyUserId, value: userId);

  static Future<String?> getRole() => _storage.read(key: _keyUserRole);

  static Future<void> setRole(String role) =>
      _storage.write(key: _keyUserRole, value: role);

  static Future<String?> getFullName() => _storage.read(key: _keyUserFullName);

  static Future<void> setFullName(String fullName) =>
      _storage.write(key: _keyUserFullName, value: fullName);

  static Future<String?> getDeviceBindingId() =>
      _storage.read(key: _keyDeviceBindingId);

  static Future<void> setDeviceBindingId(String id) =>
      _storage.write(key: _keyDeviceBindingId, value: id);

  /// Removes all secure session keys and legacy plaintext prefs.
  static Future<void> clearSession() async {
    await Future.wait<void>([
      _storage.delete(key: _keyToken),
      _storage.delete(key: _keyUserId),
      _storage.delete(key: _keyUserRole),
      _storage.delete(key: _keyUserFullName),
    ]);
    final prefs = await SharedPreferences.getInstance();
    await Future.wait<void>([
      prefs.remove(_keyToken),
      prefs.remove(_keyUserId),
      prefs.remove(_keyUserRole),
      prefs.remove(_keyUserFullName),
    ]);
  }

  /// Persists role, user id, and display name in secure storage.
  static Future<void> setSessionProfile({
    required String role,
    required String userId,
    required String fullName,
  }) async {
    await Future.wait<void>([
      setRole(role),
      setUserId(userId),
      setFullName(fullName),
    ]);
  }

  /// One-time upgrade: move legacy plaintext prefs into secure storage.
  static Future<void> migrateFromSharedPreferencesIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migrationDoneKey) == true) {
      return;
    }

    final legacyToken = prefs.getString(_keyToken);
    final legacyUserId = prefs.getString(_keyUserId);
    final legacyRole = prefs.getString(_keyUserRole);
    final legacyFullName = prefs.getString(_keyUserFullName);
    final legacyDeviceId = prefs.getString(_keyDeviceBindingId);

    if (legacyToken != null && legacyToken.isNotEmpty) {
      final existing = await getToken();
      if (existing == null || existing.isEmpty) {
        await setToken(legacyToken);
      }
    }
    if (legacyUserId != null && legacyUserId.isNotEmpty) {
      final existing = await getUserId();
      if (existing == null || existing.isEmpty) {
        await setUserId(legacyUserId);
      }
    }
    if (legacyRole != null && legacyRole.isNotEmpty) {
      final existing = await getRole();
      if (existing == null || existing.isEmpty) {
        await setRole(legacyRole);
      }
    }
    if (legacyFullName != null && legacyFullName.isNotEmpty) {
      final existing = await getFullName();
      if (existing == null || existing.isEmpty) {
        await setFullName(legacyFullName);
      }
    }
    if (legacyDeviceId != null && legacyDeviceId.isNotEmpty) {
      final existing = await getDeviceBindingId();
      if (existing == null || existing.isEmpty) {
        await setDeviceBindingId(legacyDeviceId);
      }
    }

    await Future.wait<void>([
      prefs.remove(_keyToken),
      prefs.remove(_keyUserId),
      prefs.remove(_keyUserRole),
      prefs.remove(_keyUserFullName),
      prefs.remove(_keyDeviceBindingId),
    ]);
    await prefs.setBool(_migrationDoneKey, true);

    await syncNativeMirrorPrefs();
  }

  /// Mirrors [user_id] to [SharedPreferences] for Android native CallKit paths.
  static Future<void> syncNativeMirrorPrefs() async {
    final userId = await getUserId();
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId.isNotEmpty) {
      await prefs.setString(_keyUserId, userId);
    } else {
      await prefs.remove(_keyUserId);
    }
  }
}
