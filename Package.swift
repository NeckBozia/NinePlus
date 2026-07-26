// swift-tools-version: 5.9
import PackageDescription

// Test harness for the platform-independent layer under mini-ninebot/Shared.
// The Xcode project compiles those files directly; this package exists so the
// same sources can be unit-tested from the command line and in CI without
// building the app or booting a simulator.
let package = Package(
    name: "NineBotCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    targets: [
        .target(
            name: "NineBotCore",
            path: "mini-ninebot/Shared",
            // ActivityKit *is* importable on macOS, so the file's own
            // `#if canImport(ActivityKit)` guard does not exclude it there —
            // but `ActivityAttributes` is marked unavailable on macOS, so the
            // conformance fails to build. Live Activity payloads are iOS-only
            // and carry no logic worth testing, so drop the file from the
            // package. The Xcode project still builds it for iOS.
            exclude: ["NinebotChargingActivityAttributes.swift"]
        ),
        .testTarget(
            name: "NineBotCoreTests",
            dependencies: ["NineBotCore"],
            path: "Tests/NineBotCoreTests"
        ),
    ]
)
