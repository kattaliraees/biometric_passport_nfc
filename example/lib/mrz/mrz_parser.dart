/// Extracts the NFC access-key fields from OCR'd text of a passport (TD3) MRZ.
///
/// Only the second MRZ line is needed: document number, date of birth and date
/// of expiry all live there, each protected by an ICAO 9303 check digit. A
/// result is only returned when all three check digits validate, which rejects
/// virtually all OCR misreads.
class MrzResult {
  final String documentNumber;
  final String dateOfBirth; // YYMMDD
  final String dateOfExpiry; // YYMMDD

  const MrzResult({
    required this.documentNumber,
    required this.dateOfBirth,
    required this.dateOfExpiry,
  });

  @override
  bool operator ==(Object other) =>
      other is MrzResult &&
      other.documentNumber == documentNumber &&
      other.dateOfBirth == dateOfBirth &&
      other.dateOfExpiry == dateOfExpiry;

  @override
  int get hashCode => Object.hash(documentNumber, dateOfBirth, dateOfExpiry);

  @override
  String toString() => 'MrzResult($documentNumber, $dateOfBirth, $dateOfExpiry)';
}

class MrzParser {
  // Line 2 layout (TD3): doc[0..9] check[9] nationality[10..13] dob[13..19]
  // check[19] sex[20] expiry[21..27] check[27] ...
  static const int _line2MinLength = 28;

  // Characters OCR commonly returns in place of digits.
  static const Map<String, String> _toDigit = {
    'O': '0', 'Q': '0', 'D': '0', 'U': '0',
    'I': '1', 'L': '1', 'T': '1',
    'Z': '2',
    'S': '5',
    'G': '6',
    'B': '8',
  };

  /// Returns the first line in [lines] that parses as a valid MRZ line 2.
  static MrzResult? parse(Iterable<String> lines) {
    final cleaned = lines.map(_clean).where((l) => l.isNotEmpty).toList();

    // ML Kit sometimes splits one MRZ line into several, so also try joining neighbours.
    final candidates = <String>[
      ...cleaned,
      for (var i = 0; i + 1 < cleaned.length; i++) cleaned[i] + cleaned[i + 1],
    ];

    for (final candidate in candidates) {
      if (candidate.length < _line2MinLength) continue;
      // The line may carry leading noise; slide over a few start offsets.
      for (var start = 0; start + _line2MinLength <= candidate.length && start <= 4; start++) {
        final result = _parseLine2(candidate.substring(start));
        if (result != null) return result;
      }
    }
    return null;
  }

  static String _clean(String line) => line
      .toUpperCase()
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll('«', '<')
      .replaceAll('‹', '<');

  static MrzResult? _parseLine2(String line) {
    // Line 1 starts with "P<" and has no check digits at these positions; skip it fast.
    if (line.startsWith('P<')) return null;

    final dob = _digits(line.substring(13, 19));
    final dobCheck = _digits(line.substring(19, 20));
    final expiry = _digits(line.substring(21, 27));
    final expiryCheck = _digits(line.substring(27, 28));
    if (dob == null || dobCheck == null || expiry == null || expiryCheck == null) return null;
    if (!_isValidDate(dob) || !_isValidDate(expiry)) return null;
    if (checkDigit(dob) != dobCheck || checkDigit(expiry) != expiryCheck) return null;

    final docCheck = _digits(line.substring(9, 10));
    if (docCheck == null) return null;
    // 'K' and '<' both weigh 0 mod 10 in the check digit, so a '<' filler misread as 'K'
    // still validates. If the optional-data area (normally all '<') also shows 'K's, this
    // frame is confusing the two, so treat trailing 'K's in the document number as filler.
    final optionalData = line.length > 28 ? line.substring(28, line.length.clamp(28, 42)) : '';
    final fillerReadAsK = optionalData.contains('K');
    for (final doc in _documentNumberVariants(line.substring(0, 9), preferStripTrailingK: fillerReadAsK)) {
      if (checkDigit(doc) == docCheck) {
        return MrzResult(
          documentNumber: doc.replaceAll('<', ''),
          dateOfBirth: dob,
          dateOfExpiry: expiry,
        );
      }
    }
    return null;
  }

  /// The document number is alphanumeric, so OCR fixes are ambiguous. Try the raw
  /// read plus common corrections; the check digit decides which (if any) is right.
  static Iterable<String> _documentNumberVariants(String raw, {required bool preferStripTrailingK}) sync* {
    if (!RegExp(r'^[A-Z0-9<]+$').hasMatch(raw)) return;
    final strippedK = raw.replaceFirst(RegExp(r'K+$'), '').padRight(9, '<');
    if (preferStripTrailingK && strippedK != raw) yield strippedK;
    yield raw;
    yield raw.replaceAll('O', '0');
    yield raw.replaceAll('0', 'O');
  }

  static String? _digits(String field) {
    final buffer = StringBuffer();
    for (final ch in field.split('')) {
      if (RegExp(r'\d').hasMatch(ch)) {
        buffer.write(ch);
      } else if (_toDigit.containsKey(ch)) {
        buffer.write(_toDigit[ch]);
      } else {
        return null;
      }
    }
    return buffer.toString();
  }

  static bool _isValidDate(String yymmdd) {
    final month = int.parse(yymmdd.substring(2, 4));
    final day = int.parse(yymmdd.substring(4, 6));
    return month >= 1 && month <= 12 && day >= 1 && day <= 31;
  }

  /// ICAO 9303 check digit (weights 7-3-1, A=10..Z=35, '<'=0).
  static String checkDigit(String value) {
    const weights = [7, 3, 1];
    var sum = 0;
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      int v;
      if (c >= 48 && c <= 57) {
        v = c - 48;
      } else if (c >= 65 && c <= 90) {
        v = c - 55;
      } else {
        v = 0;
      }
      sum += v * weights[i % 3];
    }
    return (sum % 10).toString();
  }
}
