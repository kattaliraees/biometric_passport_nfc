import 'package:biometric_passport_nfc_example/mrz/mrz_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MrzParser', () {
    test('parses ICAO 9303 specimen line 2', () {
      final result = MrzParser.parse([
        'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
        'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
      ]);
      expect(
        result,
        const MrzResult(documentNumber: 'L898902C3', dateOfBirth: '740812', dateOfExpiry: '120415'),
      );
    });

    test('strips < filler from 8-character document numbers', () {
      final result = MrzParser.parse(['X1234567<7UTO8501019F3001019<<<<<<<<<<<<<<00']);
      expect(
        result,
        const MrzResult(documentNumber: 'X1234567', dateOfBirth: '850101', dateOfExpiry: '300101'),
      );
    });

    test('tolerates common OCR errors', () {
      // Spaces, letter O for zero in dates, K for the < filler, « for <.
      final result = MrzParser.parse(['X1234567K7UTO 85O1O19F30O1O19«<KK<<<<KK<<<<00']);
      expect(
        result,
        const MrzResult(documentNumber: 'X1234567', dateOfBirth: '850101', dateOfExpiry: '300101'),
      );
    });

    test('keeps a genuine trailing K when filler is read correctly', () {
      final result = MrzParser.parse(['X1234567K7UTO8501019F3001019<<<<<<<<<<<<<<00']);
      expect(result?.documentNumber, 'X1234567K');
    });

    test('joins an MRZ line split across two OCR lines', () {
      final result = MrzParser.parse(['L898902C36UTO740', '8122F1204159ZE184226B<<<<<10']);
      expect(result?.documentNumber, 'L898902C3');
    });

    test('rejects reads with a wrong check digit', () {
      // DOB check digit changed from 2 to 3.
      expect(MrzParser.parse(['L898902C36UTO7408123F1204159ZE184226B<<<<<10']), isNull);
    });

    test('ignores non-MRZ text', () {
      expect(MrzParser.parse(['PASSPORT', 'Surname / Nom', 'ERIKSSON']), isNull);
    });
  });
}
