# biometric_passport_nfc

Read ICAO 9303 biometric passports (ePassports / eMRTDs) over NFC on **Android** and **iOS**.

- **PACE** with automatic **BAC** fallback
- Reads **DG1** (name, document number, nationality, dates, sex) and **DG2** (portrait image)
- **Recovers from movement**: a dropped chip connection doesn't fail the read. Android resumes where it stopped (even mid-photo) when the phone is put back; iOS reopens the NFC sheet automatically
- Typed progress events, including photo download progress, for building your own UI
- Native implementations: [JMRTD](https://jmrtd.org) on Android, [NFCPassportReader](https://github.com/AndyQ/NFCPassportReader) on iOS
- Everything runs on-device; the package makes no network calls

| Platform | Minimum | Notes |
|----------|---------|-------|
| Android | API 24 | Device needs NFC |
| iOS | 15.0 | iPhone 7 or later; NFC entitlement required |

## How it works

A passport chip only unlocks with a key derived from three fields printed in the passport's **MRZ** (the two `<<<` lines at the bottom of the photo page):

- document number
- date of birth (`YYMMDD`)
- date of expiry (`YYMMDD`)

Your app collects these (typed in, or scanned with the camera), then passes them to `readPassport`. This package does not include OCR, so it adds no camera or ML dependencies. The [example app](example/) shows a live camera MRZ scanner built with `camera` and Google ML Kit, with ICAO check-digit validation.

## Installation

```yaml
dependencies:
  biometric_passport_nfc: ^1.0.0
```

### iOS setup

1. **Enable the capability.** In Xcode, add **Near Field Communication Tag Reading** to the Runner target. Your provisioning profile must include it. This creates `Runner.entitlements` with:

   ```xml
   <key>com.apple.developer.nfc.readersession.formats</key>
   <array>
       <string>TAG</string>
       <string>PACE</string>
   </array>
   ```

2. **Add these to `ios/Runner/Info.plist`:**

   ```xml
   <key>NFCReaderUsageDescription</key>
   <string>NFC is used to read the chip in your passport.</string>
   <key>com.apple.developer.nfc.readersession.iso7816.select-identifiers</key>
   <array>
       <string>A0000002471001</string>
       <string>A0000002472001</string>
       <string>00000000000000</string>
   </array>
   ```

3. **Set the platform** in `ios/Podfile` to at least 15.0: `platform :ios, '15.0'`.

### Android setup

- `minSdk` must be at least **24**.
- The `NFC` permission is merged in from the plugin's manifest automatically. NFC is declared as not required, so the app can still be installed on devices without NFC. `readPassport` then throws `NFC_NOT_AVAILABLE`.
- R8/ProGuard rules for JMRTD and the crypto providers are bundled and applied automatically.
- If your build fails with duplicate `META-INF` licence files, add this to `android/app/build.gradle.kts`:

  ```kotlin
  android {
      packaging {
          resources {
              excludes += listOf("META-INF/LICENSE", "META-INF/NOTICE", "META-INF/license.txt", "META-INF/notice.txt")
          }
      }
  }
  ```

## Usage

```dart
import 'package:biometric_passport_nfc/biometric_passport_nfc.dart';

final reader = BiometricPassportNfc();

// Listen before starting so you get the first events.
final sub = reader.events.listen((event) {
  print('${event.step.name}: ${event.message} ${event.progress ?? ''}');
});

try {
  final passport = await reader.readPassport(
    documentNumber: 'L898902C3', // without '<' filler
    dateOfBirth: '740812',       // YYMMDD
    dateOfExpiry: '120415',      // YYMMDD
  );
  print(passport.fullName);
  if (passport.faceImage != null) {
    // Image.memory(passport.faceImage!)
  }
} on PassportReadException catch (e) {
  if (!e.isCancelled) print('${e.code}: ${e.message}');
} finally {
  await sub.cancel();
}
```

On iOS the system NFC sheet appears and shows its own progress. On Android there is no system UI, so show your own using the events (see the example app).

### Progress events

`reader.events` emits a `PassportScanEvent` with a `step`, a user-facing `message` and, while the photo is read, a `progress` value from 0 to 100.

| Step | Meaning |
|------|---------|
| `waitingForTag` | Reader active, waiting for the passport |
| `tagDiscovered` / `tagConnected` | Chip detected / connected (also sent after an automatic reconnect) |
| `authenticating` | Running PACE or BAC |
| `paceSuccess` / `bacSuccess` | Authentication succeeded |
| `readingDg1` / `dg1Success` | Reading identity data |
| `readingDg2` / `dg2Success` | Reading the photo; carries `progress` |
| `connectionLost` | Connection dropped. **The read is still active**: tell the user to put the phone back on the passport |
| `completed` / `error` | Finished / failed |
| `unknown` | Step from a newer native version |

### Errors

`readPassport` throws `PassportReadException` with one of these codes (constants in `PassportReadErrorCode`):

| Code | When |
|------|------|
| `NFC_NOT_AVAILABLE` | Device has no NFC (Android) |
| `NFC_DISABLED` | NFC is off in settings (Android) |
| `INVALID_ARGUMENTS` | An access-key field is empty |
| `SCAN_IN_PROGRESS` | A read is already running |
| `SCAN_CANCELLED` | User cancelled, or `cancel()` was called |
| `READ_ERROR` | Wrong document number / dates, retries exhausted, or timeout. See `message` |

### Result

`PassportData` has `documentNumber`, `surname`, `givenNames`, `fullName`, `nationality`, `dateOfBirth`, `sex`, `dateOfExpiry`, `faceImage`, `rawMrz`, and the flags `paceSucceeded`, `bacSucceeded`, `dg1Read` and `dg2Read`.

`faceImage` is JPEG on iOS. On Android it is the chip's own encoding, usually JPEG but sometimes **JPEG 2000**, which Flutter's `Image` can't decode. Convert it if you need to display those.

## Reliability

Positioning the phone is the hardest part for users. The package tries to make it forgiving:

**Android**
- Reader mode stays on after a drop, and the next tap resumes the same read.
- Brief glitches are retried by reconnecting to the same tag before asking for a re-tap.
- DG1 is cached once read. DG2 is read in chunks, so a re-tap only fetches the rest of the photo.
- Remembers whether PACE or BAC worked and skips the other on retries.
- A wrong document number or wrong dates fail immediately instead of retrying.

**iOS**
- Up to 4 NFC sessions per read. A connection drop reopens the sheet; cancel or timeout stops.
- Reads larger chunks than the library default (falling back if a passport rejects them).
- If the chip rejects the key, tries the alternative document-number padding once.

**Tips for users:** the iPhone NFC antenna is at the top edge, near the camera; on most Android phones it's in the middle of the back. The passport chip may be in the front cover, the back cover or the photo page, depending on the issuing country. Hold still until the photo finishes.

## Limitations

- **No passive authentication yet.** The document signature (`EF.SOD`) is not verified, so `passiveAuthentication` is always `false`. Don't rely on the data being authentic without verifying it.
- No Chip Authentication or Active Authentication (clone detection).
- Passports (TD3) are the target. Other eMRTDs such as ID cards may work but haven't been tested.

## Licences

This package is MIT licensed. Its native dependencies have their own licences:

- Android: JMRTD and SCUBA (**LGPL-3.0**), Bouncy Castle / Spongy Castle (MIT-style).
- iOS: NFCPassportReader (MIT), OpenSSL (Apache-2.0).

The LGPL libraries are used unmodified as separate Maven artifacts. Check that this suits your distribution.
