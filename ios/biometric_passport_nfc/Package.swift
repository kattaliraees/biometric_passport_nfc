// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "biometric_passport_nfc",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "biometric-passport-nfc", targets: ["biometric_passport_nfc"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Same version range as the podspec's '~> 2.3.1'.
        .package(url: "https://github.com/AndyQ/NFCPassportReader.git", .upToNextMinor(from: "2.3.1")),
    ],
    targets: [
        .target(
            name: "biometric_passport_nfc",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "NFCPassportReader", package: "NFCPassportReader"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
