import 'dart:async';

import 'package:biometric_passport_nfc/biometric_passport_nfc.dart';
import 'package:biometric_passport_nfc/biometric_passport_nfc_method_channel.dart';
import 'package:biometric_passport_nfc/biometric_passport_nfc_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakePlatform with MockPlatformInterfaceMixin implements BiometricPassportNfcPlatform {
  final events$ = StreamController<Map<dynamic, dynamic>>.broadcast();
  Map<String, String>? lastArgs;
  Object? error;
  bool cancelled = false;

  @override
  Stream<Map<dynamic, dynamic>> get events => events$.stream;

  @override
  Future<Map<dynamic, dynamic>> readPassport({
    required String documentNumber,
    required String dateOfBirth,
    required String dateOfExpiry,
  }) async {
    lastArgs = {'doc': documentNumber, 'dob': dateOfBirth, 'exp': dateOfExpiry};
    if (error != null) throw error!;
    return {
      'documentNumber': 'L898902C3',
      'surname': 'ERIKSSON',
      'givenNames': 'ANNA MARIA',
      'nationality': 'UTO',
      'dateOfBirth': '740812',
      'sex': 'F',
      'dateOfExpiry': '120415',
      'faceImage': Uint8List.fromList([1, 2, 3]),
      'paceSucceeded': true,
      'dg1Read': true,
      'dg2Read': true,
    };
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

void main() {
  late FakePlatform fake;
  final reader = BiometricPassportNfc();

  setUp(() {
    fake = FakePlatform();
    BiometricPassportNfcPlatform.instance = fake;
  });

  test('default instance uses method channels', () {
    expect(MethodChannelBiometricPassportNfc(), isA<BiometricPassportNfcPlatform>());
  });

  test('readPassport normalises input and parses the result', () async {
    final data = await reader.readPassport(documentNumber: ' l898902c3 ', dateOfBirth: '740812', dateOfExpiry: '120415');

    expect(fake.lastArgs, {'doc': 'L898902C3', 'dob': '740812', 'exp': '120415'});
    expect(data.fullName, 'ANNA MARIA ERIKSSON');
    expect(data.nationality, 'UTO');
    expect(data.faceImage, [1, 2, 3]);
    expect(data.paceSucceeded, isTrue);
    expect(data.bacSucceeded, isFalse);
  });

  test('rejects empty access-key fields without calling native', () async {
    await expectLater(
      reader.readPassport(documentNumber: '', dateOfBirth: '740812', dateOfExpiry: '120415'),
      throwsA(isA<PassportReadException>().having((e) => e.code, 'code', PassportReadErrorCode.invalidArguments)),
    );
    expect(fake.lastArgs, isNull);
  });

  test('maps PlatformException to PassportReadException', () async {
    fake.error = PlatformException(code: 'SCAN_CANCELLED', message: 'Scan was cancelled by user');
    await expectLater(
      reader.readPassport(documentNumber: 'L898902C3', dateOfBirth: '740812', dateOfExpiry: '120415'),
      throwsA(isA<PassportReadException>().having((e) => e.isCancelled, 'isCancelled', isTrue)),
    );
  });

  test('events are typed, with progress and unknown-step fallback', () async {
    final received = <PassportScanEvent>[];
    final sub = reader.events.listen(received.add);
    fake.events$
      ..add({'step': 'readingDg2', 'message': 'Reading photo', 'progress': 40})
      ..add({'step': 'connectionLost', 'message': 'Lost'})
      ..add({'step': 'somethingNew', 'message': 'x'});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(received.map((e) => e.step), [
      PassportScanStep.readingDg2,
      PassportScanStep.connectionLost,
      PassportScanStep.unknown,
    ]);
    expect(received.first.progress, 40);
  });

  test('cancel forwards to the platform', () async {
    await reader.cancel();
    expect(fake.cancelled, isTrue);
  });
}
