import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:biometric_passport_nfc_example/main.dart';

void main() {
  testWidgets('Renders ePassport scan root screen with editable credentials', (WidgetTester tester) async {
    await tester.pumpWidget(const BiometricPassportNfcExampleApp());

    expect(find.text('Biometric Passport NFC'), findsOneWidget);
    expect(find.text('Scan Passport'), findsOneWidget);
    expect(find.text('Passport Credentials'), findsOneWidget);
    // Credential fields start empty
    for (final key in ['docNumberField', 'dobField', 'expiryField']) {
      final field = tester.widget<TextField>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField)),
      );
      expect(field.controller!.text, isEmpty);
    }
  });

  testWidgets('Validates input fields on scan attempt', (WidgetTester tester) async {
    await tester.pumpWidget(const BiometricPassportNfcExampleApp());

    final docFinder = find.byKey(const Key('docNumberField'));
    final dobFinder = find.byKey(const Key('dobField'));
    final expiryFinder = find.byKey(const Key('expiryField'));
    final scanButtonFinder = find.byKey(const Key('scanButton'));
    final resetButtonFinder = find.byKey(const Key('resetButton'));

    // 1. Clear document number -> required error
    await tester.enterText(docFinder, '');
    await tester.tap(scanButtonFinder);
    await tester.pump();
    expect(find.text('Document number is required'), findsOneWidget);

    // 2. Short document number -> length error
    await tester.enterText(docFinder, 'ABC');
    await tester.tap(scanButtonFinder);
    await tester.pump();
    expect(find.text('Length must be 5 to 12 characters'), findsOneWidget);

    // 3. Special characters filtered out by formatter (AB@# -> AB, length 2 -> error)
    await tester.enterText(docFinder, 'AB@#');
    await tester.tap(scanButtonFinder);
    await tester.pump();
    expect(find.text('Length must be 5 to 12 characters'), findsOneWidget);

    // Restore valid doc number
    await tester.enterText(docFinder, 'A1234567');

    // 4. Invalid month in date of birth
    await tester.enterText(dobFinder, '791325'); // Month 13 is invalid
    await tester.tap(scanButtonFinder);
    await tester.pump();
    expect(find.text('Month must be 01–12'), findsOneWidget);

    // 5. Invalid day in date of birth
    await tester.enterText(dobFinder, '790532'); // Day 32 is invalid
    await tester.tap(scanButtonFinder);
    await tester.pump();
    expect(find.text('Day must be 01–31'), findsOneWidget);

    // 6. Incomplete date (less than 6 digits)
    await tester.enterText(dobFinder, '7905');
    await tester.tap(scanButtonFinder);
    await tester.pump();
    expect(find.text('Must be 6 digits (YYMMDD)'), findsOneWidget);

    // Restore valid DOB
    await tester.enterText(dobFinder, '850115');

    // 7. Invalid month in expiry
    await tester.enterText(expiryFinder, '300015'); // Month 00 is invalid
    await tester.tap(scanButtonFinder);
    await tester.pump();
    expect(find.text('Month must be 01–12'), findsOneWidget);

    // 8. Reset button clears the fields
    await tester.tap(resetButtonFinder);
    await tester.pump();

    expect(find.text('A1234567'), findsNothing);
    expect(find.text('850115'), findsNothing);
    expect(find.text('300015'), findsNothing);
  });
}
