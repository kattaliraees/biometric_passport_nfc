import 'dart:typed_data';

/// Data read from a passport chip.
class PassportData {
  /// Document number from DG1, without `<` filler.
  final String documentNumber;
  final String surname;
  final String givenNames;

  /// Three-letter ICAO nationality code, e.g. `UTO`.
  final String nationality;

  /// Date of birth as `YYMMDD`.
  final String dateOfBirth;

  /// `M`, `F` or as encoded on the chip.
  final String sex;

  /// Date of expiry as `YYMMDD`.
  final String dateOfExpiry;

  /// Raw portrait from DG2, usually JPEG (iOS always returns JPEG; Android
  /// returns the chip's encoding, which may be JPEG 2000). Null if DG2 was
  /// not readable.
  final Uint8List? faceImage;

  final bool paceSucceeded;
  final bool bacSucceeded;
  final bool dg1Read;
  final bool dg2Read;

  /// Whether passive authentication (SOD signature) succeeded. Not performed
  /// yet; always `false` in this version.
  final bool passiveAuthentication;

  /// DG1 MRZ as reported by the native reader.
  final String? rawMrz;

  const PassportData({
    required this.documentNumber,
    required this.surname,
    required this.givenNames,
    required this.nationality,
    required this.dateOfBirth,
    required this.sex,
    required this.dateOfExpiry,
    this.faceImage,
    this.paceSucceeded = false,
    this.bacSucceeded = false,
    this.dg1Read = false,
    this.dg2Read = false,
    this.passiveAuthentication = false,
    this.rawMrz,
  });

  String get fullName {
    final parts = [givenNames.trim(), surname.trim()].where((s) => s.isNotEmpty);
    return parts.isEmpty ? 'Unknown' : parts.join(' ');
  }

  factory PassportData.fromMap(Map<dynamic, dynamic> map) {
    Uint8List? imageBytes;
    final rawImage = map['faceImage'];
    if (rawImage is Uint8List) {
      imageBytes = rawImage;
    } else if (rawImage is List) {
      imageBytes = Uint8List.fromList(rawImage.cast<int>());
    }

    String str(String key) => (map[key] as String?)?.trim() ?? '';

    return PassportData(
      documentNumber: str('documentNumber'),
      surname: str('surname'),
      givenNames: str('givenNames'),
      nationality: str('nationality'),
      dateOfBirth: str('dateOfBirth'),
      sex: str('sex'),
      dateOfExpiry: str('dateOfExpiry'),
      faceImage: imageBytes,
      paceSucceeded: map['paceSucceeded'] == true,
      bacSucceeded: map['bacSucceeded'] == true,
      dg1Read: map['dg1Read'] == true,
      dg2Read: map['dg2Read'] == true,
      passiveAuthentication: map['passiveAuthentication'] == true,
      rawMrz: map['rawMrz'] as String?,
    );
  }
}
