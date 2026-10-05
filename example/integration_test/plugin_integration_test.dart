import 'package:biometric_passport_nfc/biometric_passport_nfc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A real read needs a passport on the device, so this only checks the native
  // side is registered and rejects incomplete input.
  testWidgets('native plugin is registered', (tester) async {
    final reader = BiometricPassportNfc();
    await expectLater(
      reader.readPassport(documentNumber: '', dateOfBirth: '', dateOfExpiry: ''),
      throwsA(isA<PassportReadException>()),
    );
    await reader.cancel();
  });
}
