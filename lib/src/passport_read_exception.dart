/// Error codes reported by [BiometricPassportNfc.readPassport].
abstract final class PassportReadErrorCode {
  /// The device has no NFC hardware (Android).
  static const nfcNotAvailable = 'NFC_NOT_AVAILABLE';

  /// NFC is switched off in system settings (Android).
  static const nfcDisabled = 'NFC_DISABLED';

  /// A read is already running.
  static const scanInProgress = 'SCAN_IN_PROGRESS';

  /// The user cancelled, or [BiometricPassportNfc.cancel] was called.
  static const scanCancelled = 'SCAN_CANCELLED';

  /// A required access-key field was empty.
  static const invalidArguments = 'INVALID_ARGUMENTS';

  /// Authentication failed, retries were exhausted, or the session timed out.
  /// See [PassportReadException.message].
  static const readError = 'READ_ERROR';
}

/// Thrown by [BiometricPassportNfc.readPassport] when a read fails.
class PassportReadException implements Exception {
  /// One of [PassportReadErrorCode].
  final String code;
  final String message;
  final Object? details;

  const PassportReadException(this.code, this.message, [this.details]);

  bool get isCancelled => code == PassportReadErrorCode.scanCancelled;

  @override
  String toString() => 'PassportReadException($code): $message';
}
