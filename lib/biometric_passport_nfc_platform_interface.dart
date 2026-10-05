import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'biometric_passport_nfc_method_channel.dart';

/// Platform interface for biometric_passport_nfc. Swap [instance] in tests to
/// fake the native reader.
abstract class BiometricPassportNfcPlatform extends PlatformInterface {
  BiometricPassportNfcPlatform() : super(token: _token);

  static final Object _token = Object();

  static BiometricPassportNfcPlatform _instance = MethodChannelBiometricPassportNfc();

  static BiometricPassportNfcPlatform get instance => _instance;

  static set instance(BiometricPassportNfcPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Raw progress events: maps with `step`, `message` and optional `progress`.
  Stream<Map<dynamic, dynamic>> get events {
    throw UnimplementedError('events has not been implemented.');
  }

  /// Reads the passport and returns the raw result map.
  Future<Map<dynamic, dynamic>> readPassport({
    required String documentNumber,
    required String dateOfBirth,
    required String dateOfExpiry,
  }) {
    throw UnimplementedError('readPassport() has not been implemented.');
  }

  Future<void> cancel() {
    throw UnimplementedError('cancel() has not been implemented.');
  }
}
