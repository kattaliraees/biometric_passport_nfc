## 1.0.2

* iOS: Swift Package Manager support (CocoaPods still supported).
* Code formatted with `dart format`.

## 1.0.1

* Added homepage and repository links.

## 1.0.0

* Initial release.
* Read ICAO 9303 passports over NFC on Android (JMRTD) and iOS (NFCPassportReader).
* PACE with automatic BAC fallback.
* Reads DG1 (identity / MRZ) and DG2 (portrait image).
* Typed progress events, including DG2 read progress.
* Recovers from dropped chip connections: Android resumes mid-read on re-tap
  (including a partially read DG2); iOS reopens the NFC session automatically.
* Consumer R8 rules bundled for Android release builds.
