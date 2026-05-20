import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _inspectorKey = 'inspector_id';
  static const _inspectorNameKey = 'inspector_name';
  static const _inspectorDeptKey = 'inspector_dept';

  final FlutterSecureStorage _storage;

  TokenStorage(this._storage);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required int inspectorId,
    required String inspectorName,
    String? inspectorDepartment,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
    await _storage.write(key: _inspectorKey, value: inspectorId.toString());
    await _storage.write(key: _inspectorNameKey, value: inspectorName);
    if (inspectorDepartment != null) {
      await _storage.write(key: _inspectorDeptKey, value: inspectorDepartment);
    }
  }

  Future<String?> getAccessToken() => _storage.read(key: _accessKey);
  Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);
  Future<int?> getInspectorId() async {
    final s = await _storage.read(key: _inspectorKey);
    return s == null ? null : int.parse(s);
  }
  Future<String?> getInspectorName() => _storage.read(key: _inspectorNameKey);
  Future<String?> getInspectorDepartment() => _storage.read(key: _inspectorDeptKey);

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _inspectorKey);
    await _storage.delete(key: _inspectorNameKey);
    await _storage.delete(key: _inspectorDeptKey);
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  return TokenStorage(storage);
});
