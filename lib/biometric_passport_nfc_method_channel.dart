import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'biometric_passport_nfc_platform_interface.dart';

/// [BiometricPassportNfcPlatform] implementation backed by method/event channels.
class MethodChannelBiometricPassportNfc extends BiometricPassportNfcPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('biometric_passport_nfc/method');

  @visibleForTesting
  final eventChannel = const EventChannel('biometric_passport_nfc/events');

  Stream<Map<dynamic, dynamic>>? _events;

  @override
  Stream<Map<dynamic, dynamic>> get events =>
      _events ??= eventChannel.receiveBroadcastStream().map((e) => e as Map<dynamic, dynamic>);

  @override
  Future<Map<dynamic, dynamic>> readPassport({
    required String documentNumber,
    required String dateOfBirth,
    required String dateOfExpiry,
  }) async {
    final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('readPassport', {
      'documentNumber': documentNumber,
      'dateOfBirth': dateOfBirth,
      'dateOfExpiry': dateOfExpiry,
    });
    if (result == null) {
      throw PlatformException(code: 'READ_ERROR', message: 'Empty response from native reader');
    }
    return result;
  }

  @override
  Future<void> cancel() => methodChannel.invokeMethod<void>('cancel');
}
