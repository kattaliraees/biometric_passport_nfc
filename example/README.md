# biometric_passport_nfc example

A complete passport-reading app:

1. **Scan the MRZ with the camera** (`lib/mrz/`) to fill in the document number, date of birth and expiry, or type them in.
2. **Read the chip over NFC** with `biometric_passport_nfc`, showing live status, photo progress and connection-lost prompts.
3. **Show the result**: name, document details, MRZ and portrait.

## MRZ scanner

The scanner is part of the example, not the package, so apps can choose their own OCR. It uses [`camera`](https://pub.dev/packages/camera) and [`google_mlkit_text_recognition`](https://pub.dev/packages/google_mlkit_text_recognition):

- `mrz_parser.dart` finds MRZ line 2 in OCR text. It only accepts a read when all three ICAO 9303 check digits are valid, and corrects common OCR confusions (`O`/`0`, `«` for `<`, `<` read as `K`).
- `mrz_scanner_screen.dart` streams camera frames to ML Kit and closes automatically after two identical valid reads.

Copy both files into your app if they suit you.

## Running

A real device with NFC is required; simulators and emulators can't read passports.

```bash
flutter run
```

- **iOS:** set your development team in Xcode. The NFC capability (`Runner.entitlements`) and the `Info.plist` keys are already configured. The deployment target is 15.5 because ML Kit needs it.
- **Android:** release builds use `android/app/proguard-rules.pro`, which holds the ML Kit rules. The NFC rules come from the package.
