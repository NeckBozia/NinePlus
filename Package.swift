// swift-tools-version: 5.9
import PackageDescription

// Test harness for the platform-independent layer under mini-ninebot/Shared.
// The Xcode project compiles those files directly; this package exists so the
// same sources can be unit-tested from the command line and in CI without
// building the app or booting a simulator.
//
// NinebotChargingActivityAttributes.swift is guarded by `#if canImport(ActivityKit)`
// and compiles to nothing off iOS, so it needs no exclusion here.
let package = Package(
    name: "NineBotCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    targets: [
        .target(
            name: "NineBotCore",
            path: "mini-ninebot/Shared"
        ),
        .testTarget(
            name: "NineBotCoreTests",
            dependencies: ["NineBotCore"],
            path: "Tests/NineBotCoreTests"
        ),
    ]
)
