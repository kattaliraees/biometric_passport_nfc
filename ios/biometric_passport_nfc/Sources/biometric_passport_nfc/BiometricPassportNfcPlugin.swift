import Flutter
import UIKit
import NFCPassportReader

/// Reads ICAO 9303 passports via CoreNFC + NFCPassportReader.
public class BiometricPassportNfcPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, PassportReaderTrackingDelegate {
  private var eventSink: FlutterEventSink?
  private var passportReader: PassportReader?

  // Each attempt is a fresh NFC session (the reader library invalidates its session when the chip
  // connection drops), so a dropped connection costs one sheet re-open instead of a full restart.
  private let maxScanAttempts = 4
  // Bytes requested per READ BINARY. The library defaults to 0xA0; 0xDF (what JMRTD uses) still fits
  // a short secure-messaging APDU and cuts DG2 round trips by ~30%. Dropped if a passport rejects it.
  private let fastReadAmount = 0xDF

  private var scanInProgress = false
  private var scanCancelled = false
  private var paceFailedThisAttempt = false
  private var bacFailedThisAttempt = false
  private var bacSucceededThisAttempt = false
  private var lastDg2Progress = -1

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BiometricPassportNfcPlugin()
    let methodChannel = FlutterMethodChannel(name: "biometric_passport_nfc/method", binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(name: "biometric_passport_nfc/events", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "readPassport":
      let args = call.arguments as? [String: Any]
      let docNumber = args?["documentNumber"] as? String ?? ""
      let dob = args?["dateOfBirth"] as? String ?? ""
      let expiry = args?["dateOfExpiry"] as? String ?? ""
      if docNumber.isEmpty || dob.isEmpty || expiry.isEmpty {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Document number, date of birth and expiry date are required", details: nil))
        return
      }
      startPassportScan(docNumber: docNumber, dob: dob, expiry: expiry, result: result)
    case "cancel":
      // The NFC sheet is modal, so this mostly stops further retry attempts.
      scanCancelled = true
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - FlutterStreamHandler
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  private func sendEvent(step: String, message: String, progress: Int? = nil) {
    #if DEBUG
    print("BiometricPassportNfc event: [\(step)] \(message)")
    #endif
    var event: [String: Any] = ["step": step, "message": message]
    if let progress = progress { event["progress"] = progress }
    DispatchQueue.main.async {
      self.eventSink?(event)
    }
  }

  // MARK: - PassportReaderTrackingDelegate
  public func nfcTagDetected() {
    sendEvent(step: "tagDiscovered", message: "NFC tag detected. Establishing secure connection...")
  }

  public func readCardAccess(cardAccess: CardAccess) {
    sendEvent(step: "authenticating", message: "Card access file read. Checking PACE/BAC...")
  }

  public func paceStarted() {
    sendEvent(step: "authenticating", message: "Attempting PACE authentication...")
  }

  public func paceSucceeded() {
    sendEvent(step: "paceSuccess", message: "PACE authentication succeeded")
  }

  public func paceFailed() {
    paceFailedThisAttempt = true
    sendEvent(step: "authenticating", message: "PACE failed. Falling back to BAC...")
  }

  public func bacStarted() {
    sendEvent(step: "authenticating", message: "Attempting BAC authentication...")
  }

  public func bacSucceeded() {
    bacSucceededThisAttempt = true
    sendEvent(step: "bacSuccess", message: "BAC authentication succeeded")
  }

  public func bacFailed() {
    bacFailedThisAttempt = true
    sendEvent(step: "authenticating", message: "BAC authentication failed")
  }

  // MARK: - Passport Reading
  private func startPassportScan(docNumber: String, dob: String, expiry: String, result: @escaping FlutterResult) {
    if scanInProgress {
      result(FlutterError(code: "SCAN_IN_PROGRESS", message: "A scan is already in progress", details: nil))
      return
    }
    scanInProgress = true
    scanCancelled = false

    let mrzKeyWithPad = getMRZKey(passportNumber: docNumber, dateOfBirth: dob, dateOfExpiry: expiry, padWithAngleBrackets: true)
    let mrzKeyNoPad = getMRZKey(passportNumber: docNumber, dateOfBirth: dob, dateOfExpiry: expiry, padWithAngleBrackets: false)

    sendEvent(step: "waitingForTag", message: "Hold the top of your iPhone flat against the passport...")

    Task {
      var mrzKey = mrzKeyWithPad
      var triedUnpaddedKey = mrzKeyWithPad == mrzKeyNoPad
      var skipPACE = false
      var readAmount: Int? = fastReadAmount
      var lastError: Error?
      var attempt = 0

      while attempt < maxScanAttempts {
        attempt += 1
        if scanCancelled {
          finishScan(result, FlutterError(code: "SCAN_CANCELLED", message: "Scan was cancelled by user", details: nil))
          return
        }
        if attempt > 1 {
          // Give CoreNFC time to tear down the previous session before starting a new one;
          // starting immediately can fail with "system resource unavailable".
          try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        paceFailedThisAttempt = false
        bacFailedThisAttempt = false
        bacSucceededThisAttempt = false
        lastDg2Progress = -1

        let reader = PassportReader()
        reader.trackingDelegate = self
        if let readAmount = readAmount {
          reader.overrideNFCDataAmountToRead(amount: readAmount)
        }
        passportReader = reader

        let isRetry = attempt > 1
        #if DEBUG
        print("BiometricPassportNfc: [Attempt \(attempt)] skipPACE: \(skipPACE), readAmount: \(readAmount.map { String($0) } ?? "default"), paddedKey: \(mrzKey == mrzKeyWithPad)")
        #endif
        do {
          let passport = try await reader.readPassport(
            mrzKey: mrzKey,
            tags: [.COM, .DG1, .DG2],
            skipSecureElements: true,
            skipCA: true,
            skipPACE: skipPACE,
            useExtendedMode: false,
            customDisplayMessage: { [weak self] message in
              self?.nfcSheetMessage(message, isRetry: isRetry)
            }
          )
          handlePassportSuccess(passport, docNumber: docNumber, dob: dob, expiry: expiry, result: result)
          return
        } catch {
          #if DEBUG
          print("BiometricPassportNfc: [Attempt \(attempt) Failed]: \(error)")
          #endif
          lastError = error
          let readerError = error as? NFCPassportReaderError

          // PACE didn't work but BAC did: go straight to BAC next time and save the PACE round trips.
          if paceFailedThisAttempt && bacSucceededThisAttempt {
            skipPACE = true
          }

          if case .UserCanceled? = readerError {
            finishScan(result, FlutterError(code: "SCAN_CANCELLED", message: "Scan was cancelled by user", details: nil))
            return
          }
          if case .TimeOutError? = readerError {
            finishScan(result, FlutterError(code: "READ_ERROR", message: "Timed out waiting for the passport. Please try again.", details: "\(error)"))
            return
          }

          if isCredentialFailure(readerError) {
            if !triedUnpaddedKey {
              // Some issuers' chips derive the key without '<' filler; worth one try before giving up.
              triedUnpaddedKey = true
              mrzKey = mrzKeyNoPad
              skipPACE = true
              continue
            }
            finishScan(result, FlutterError(code: "READ_ERROR", message: "Authentication failed. Please verify the passport number, date of birth and expiry date.", details: "\(error)"))
            return
          }

          if case .ResponseError? = readerError, readAmount != nil {
            // The chip may not accept larger reads; fall back to the library's conservative default.
            readAmount = nil
          }

          if attempt < maxScanAttempts {
            sendEvent(step: "connectionLost", message: "Connection lost. Hold your iPhone against the passport again and keep it still.")
          }
        }
      }

      let message = lastError.map { "Scan failed: \($0.localizedDescription)" } ?? "Scan failed"
      sendEvent(step: "error", message: message)
      finishScan(result, FlutterError(code: "READ_ERROR", message: message, details: lastError.map { "\($0)" }))
    }
  }

  /// Wrong document number / DOB / expiry, as opposed to the chip connection dropping mid-handshake.
  private func isCredentialFailure(_ error: NFCPassportReaderError?) -> Bool {
    if case .InvalidMRZKey? = error { return true }
    switch error {
    case .ConnectionError?, .UnexpectedError?, .Unknown?, .NoConnectedTag?, .TimeOutError?:
      return false
    default:
      return bacFailedThisAttempt
    }
  }

  private func finishScan(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async {
      self.scanInProgress = false
      self.passportReader = nil
      result(value)
    }
  }

  /// Text for the system NFC sheet. Also forwards DG2 progress to Flutter.
  private func nfcSheetMessage(_ message: NFCViewDisplayMessage, isRetry: Bool) -> String? {
    switch message {
    case .requestPresentPassport:
      return isRetry
        ? "Connection lost. Place the top of your iPhone back on the passport and keep it still."
        : "Place the top edge of your iPhone flat on the passport and keep it still.\nThe chip may be in the front cover, back cover or photo page."
    case .authenticatingWithPassport(let progress):
      return "Passport found. Keep still...\n\nAuthenticating \(progress)%"
    case .readingDataGroupProgress(let dataGroup, let progress):
      if dataGroup == .DG2 && progress >= lastDg2Progress + 5 {
        lastDg2Progress = progress
        sendEvent(step: "readingDg2", message: "Reading photo... Hold still.", progress: progress)
      }
      let label: String
      switch dataGroup {
      case .DG1: label = "personal details"
      case .DG2: label = "photo"
      default: label = "passport data"
      }
      return "Keep still...\n\nReading \(label) \(progress)%"
    case .error(let error):
      switch error {
      case .ConnectionError, .Unknown, .UnexpectedError:
        return "Connection lost."
      default:
        return nil
      }
    case .successfulRead:
      return "Passport read successfully"
    default:
      return nil
    }
  }

  private func handlePassportSuccess(_ passport: NFCPassportModel, docNumber: String, dob: String, expiry: String, result: @escaping FlutterResult) {
    #if DEBUG
    print("BiometricPassportNfc: SUCCESS reading passport! DG1 read: \(passport.dataGroupsRead[.DG1] != nil), DG2 read: \(passport.dataGroupsRead[.DG2] != nil)")
    #endif

    var imageBytes: FlutterStandardTypedData? = nil
    if let image = passport.passportImage, let data = image.jpegData(compressionQuality: 0.9) {
      imageBytes = FlutterStandardTypedData(bytes: data)
    }

    let paceSuccess = passport.PACEStatus == .success
    let bacSuccess = passport.BACStatus == .success
    let dg1Read = passport.dataGroupsRead[.DG1] != nil
    let dg2Read = passport.dataGroupsRead[.DG2] != nil

    let response: [String: Any?] = [
      "documentNumber": passport.documentNumber.isEmpty ? docNumber : passport.documentNumber,
      "surname": passport.lastName,
      "givenNames": passport.firstName,
      "nationality": passport.nationality,
      "dateOfBirth": passport.dateOfBirth.isEmpty ? dob : passport.dateOfBirth,
      "sex": passport.gender,
      "dateOfExpiry": passport.documentExpiryDate.isEmpty ? expiry : passport.documentExpiryDate,
      "faceImage": imageBytes,
      "paceSucceeded": paceSuccess,
      "bacSucceeded": bacSuccess,
      "dg1Read": dg1Read,
      "dg2Read": dg2Read,
      "passiveAuthentication": passport.passportCorrectlySigned,
      "rawMrz": passport.passportMRZ
    ]

    sendEvent(step: "completed", message: "Passport reading completed")
    finishScan(result, response)
  }

  private func computeCheckDigit(_ value: String) -> String {
    let weights = [7, 3, 1]
    var sum = 0
    for (i, char) in value.enumerated() {
      let weight = weights[i % 3]
      let val: Int
      if let d = char.wholeNumberValue {
        val = d
      } else if char >= "A" && char <= "Z" {
        val = Int(char.asciiValue! - Character("A").asciiValue!) + 10
      } else if char == "<" {
        val = 0
      } else {
        val = 0
      }
      sum += val * weight
    }
    return String(sum % 10)
  }

  private func getMRZKey(passportNumber: String, dateOfBirth: String, dateOfExpiry: String, padWithAngleBrackets: Bool) -> String {
    var pNum = passportNumber.replacingOccurrences(of: "<", with: "").uppercased()
    if padWithAngleBrackets {
      while pNum.count < 9 {
        pNum += "<"
      }
    }
    let pCheck = computeCheckDigit(pNum)
    let dobCheck = computeCheckDigit(dateOfBirth)
    let expCheck = computeCheckDigit(dateOfExpiry)
    return "\(pNum)\(pCheck)\(dateOfBirth)\(dobCheck)\(dateOfExpiry)\(expCheck)"
  }
}
