#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint biometric_passport_nfc.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'biometric_passport_nfc'
  s.version          = '1.0.0'
  s.summary          = 'Read ICAO 9303 biometric passports over NFC (PACE/BAC, DG1 identity, DG2 photo) on Android and iOS, with a live camera MRZ scanner.'
  s.description      = <<-DESC
Read ICAO 9303 biometric passports over NFC (PACE/BAC, DG1 identity, DG2 photo) on Android and iOS, with a live camera MRZ scanner.
                       DESC
  s.homepage         = 'https://pub.dev/packages/biometric_passport_nfc'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'Raees Kattali'
  s.source           = { :path => '.' }
  s.source_files = 'biometric_passport_nfc/Sources/biometric_passport_nfc/**/*'
  s.dependency 'Flutter'
  s.dependency 'NFCPassportReader', '~> 2.3.1'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'biometric_passport_nfc_privacy' => ['biometric_passport_nfc/Sources/biometric_passport_nfc/PrivacyInfo.xcprivacy']}
end
