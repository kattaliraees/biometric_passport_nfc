/// Read ICAO 9303 biometric passports (ePassports / eMRTDs) over NFC.
///
/// ```dart
/// final reader = BiometricPassportNfc();
/// reader.events.listen((e) => print(e.message));
/// final data = await reader.readPassport(
///   documentNumber: 'L898902C3',
///   dateOfBirth: '740812', // YYMMDD
///   dateOfExpiry: '120415', // YYMMDD
/// );
/// ```
///
/// The three access-key fields come from the passport's MRZ. Typing them in
/// works; the example app shows how to capture them with the camera (ML Kit).
library;

import 'package:flutter/services.dart';

import 'biometric_passport_nfc_platform_interface.dart';
import 'src/passport_data.dart';
import 'src/passport_read_exception.dart';
import 'src/passport_scan_event.dart';

export 'src/passport_data.dart';
export 'src/passport_read_exception.dart';
export 'src/passport_scan_event.dart';

class BiometricPassportNfc {
  BiometricPassportNfcPlatform get _platform => BiometricPassportNfcPlatform.instance;

  /// Progress updates for the current read. Broadcast; listen before calling
  /// [readPassport] to receive the first events.
  Stream<PassportScanEvent> get events => _platform.events.map(PassportScanEvent.fromMap);

  /// Starts an NFC session and reads DG1 (identity) and DG2 (portrait).
  ///
  /// The access key is derived from the MRZ: [documentNumber] (without `<`
  /// filler), [dateOfBirth] and [dateOfExpiry] as `YYMMDD`. Completes when the
  /// read finishes. Connection drops are retried automatically; throws
  /// [PassportReadException] on failure or cancellation.
  Future<PassportData> readPassport({
    required String documentNumber,
    required String dateOfBirth,
    required String dateOfExpiry,
  }) async {
    final doc = documentNumber.trim().toUpperCase();
    final dob = dateOfBirth.trim();
    final expiry = dateOfExpiry.trim();
    if (doc.isEmpty || dob.isEmpty || expiry.isEmpty) {
      throw const PassportReadException(
        PassportReadErrorCode.invalidArguments,
        'Document number, date of birth and expiry date are required',
      );
    }
    try {
      final map = await _platform.readPassport(documentNumber: doc, dateOfBirth: dob, dateOfExpiry: expiry);
      return PassportData.fromMap(map);
    } on PlatformException catch (e) {
      throw PassportReadException(e.code, e.message ?? 'NFC reading failed', e.details);
    }
  }

  /// Cancels the current read; [readPassport] then throws with
  /// [PassportReadErrorCode.scanCancelled]. On iOS the system NFC sheet is
  /// modal, so this mainly stops further automatic retries.
  Future<void> cancel() async {
    try {
      await _platform.cancel();
    } on PlatformException {
      // Nothing to cancel.
    }
  }
}
