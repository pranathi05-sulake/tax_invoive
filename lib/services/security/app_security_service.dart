import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

enum SecurityAuthResult {
  success,
  failed,
  notAvailable,
  disabled,
}

class AppSecurityService {
  static final AppSecurityService instance = AppSecurityService();

  final LocalAuthentication auth;
  final FlutterSecureStorage secureStorage;

  static const String _keySecurityEnabled = 'sec_enabled';
  static const String _keyBiometricEnabled = 'sec_biometric_enabled';
  static const String _keyLastAuthTimestamp = 'sec_last_auth_time';

  AppSecurityService({
    LocalAuthentication? auth,
    FlutterSecureStorage? secureStorage,
  })  : auth = auth ?? LocalAuthentication(),
        secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Checks if local biometric or device lock hardware is available on the device.
  Future<bool> isHardwareSupported() async {
    try {
      final canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final isDeviceSupported = await auth.isDeviceSupported();
      return canAuthenticateWithBiometrics || isDeviceSupported;
    } on PlatformException catch (e) {
      debugPrint('[AppSecurityService] Hardware check exception: $e');
      return false;
    }
  }

  /// Returns true ONLY if local security authentication is currently enabled by user.
  Future<bool> isSecurityEnabled() async {
    try {
      final value = await secureStorage.read(key: _keySecurityEnabled);
      return value == 'true';
    } catch (e) {
      debugPrint('[AppSecurityService] Error reading security preference: $e');
      return false;
    }
  }

  /// Enables or disables local security authentication.
  Future<void> setSecurityEnabled(bool enabled) async {
    await secureStorage.write(key: _keySecurityEnabled, value: enabled ? 'true' : 'false');
  }

  /// Prompts the user for local biometric or device passcode authentication.
  Future<SecurityAuthResult> authenticate({
    String reason = 'Authenticate to access TaxInvoice AI (Helicopter Division)',
  }) async {
    final enabled = await isSecurityEnabled();
    if (!enabled) {
      return SecurityAuthResult.disabled;
    }

    try {
      final isSupported = await isHardwareSupported();
      if (!isSupported) {
        return SecurityAuthResult.notAvailable;
      }

      final authenticated = await auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );

      if (authenticated) {
        await recordAuthSuccess();
        return SecurityAuthResult.success;
      } else {
        return SecurityAuthResult.failed;
      }
    } on PlatformException catch (e) {
      debugPrint('[AppSecurityService] Authentication exception: $e');
      return SecurityAuthResult.failed;
    }
  }

  /// Records the timestamp of last successful authentication.
  Future<void> recordAuthSuccess() async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    await secureStorage.write(key: _keyLastAuthTimestamp, value: now);
  }

  /// Evaluates whether re-authentication is required when resuming from background.
  Future<bool> shouldReauthenticate({int timeoutSeconds = 60}) async {
    final enabled = await isSecurityEnabled();
    if (!enabled) return false;

    final lastAuthStr = await secureStorage.read(key: _keyLastAuthTimestamp);
    if (lastAuthStr == null) return true;

    final lastAuthMs = int.tryParse(lastAuthStr) ?? 0;
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastAuthMs;
    return elapsedMs > (timeoutSeconds * 1000);
  }
}
