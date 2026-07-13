import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  static const _passwordKey = 'bnp_admin_password';

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<bool> isAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final enrolled = await _localAuth.getAvailableBiometrics();
      return supported && canCheck && enrolled.contains(BiometricType.face);
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasSavedPassword() async {
    try {
      return (await _storage.read(key: _passwordKey))?.isNotEmpty == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> savePassword(String password) async {
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<String?> readPassword() => _storage.read(key: _passwordKey);

  Future<void> clearPassword() => _storage.delete(key: _passwordKey);

  Future<bool> authenticate() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: '请使用 Face ID 登录轻小说打包器',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
