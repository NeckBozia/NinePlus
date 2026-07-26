# Contributing

## Running the tests locally

The platform-independent layer under `mini-ninebot/Shared` is exposed as a Swift
package (`Package.swift` at the repository root) so it can be tested from the
command line — no simulator, no signing identity, no Xcode scheme required:

```sh
swift test
```

Useful variants:

```sh
swift build --build-tests            # compile only, to check for build breaks
swift test --filter SharedStoreTests # run a single test class
swift test --filter SharedStoreTests/testDashboardRoundTrips
```

This needs a macOS machine with Xcode installed. The package declares
`swift-tools-version: 5.9` and targets macOS 13+ / iOS 17+.

The SPM package is a *test harness only*. The Xcode project compiles the files
in `mini-ninebot/Shared` directly, so the package and the app always build the
same sources. Building or running the app itself still goes through
`mini-ninebot/mini-ninebot.xcodeproj` (see the Build section of `README.md`).

## Where tests go

All tests live in `Tests/NineBotCoreTests/`. Add a new `XCTestCase` file there
and SwiftPM will pick it up automatically — there is no manifest to update.

Conventions used by the existing suites:

- **XCTest, not swift-testing.** Use `final class Foo: XCTestCase` with
  `func testSomething()`, not the `@Test` macro.
- **`@testable import NineBotCore`** at the top of the file. Note that this
  exposes `internal` members only; `private` members stay unreachable, so
  private keys and helpers have to be mirrored in the test (see the constants at
  the top of `SharedStoreTests.swift`).
- **Isolate persistent state.** `NinebotSharedStore` writes to `UserDefaults`.
  Construct it with a per-test suite name and tear the suite down afterwards:

  ```swift
  override func setUp() {
      super.setUp()
      suiteName = "com.nineplus.tests.\(UUID().uuidString)"
      store = NinebotSharedStore(suiteName: suiteName)
  }

  override func tearDown() {
      UserDefaults().removePersistentDomain(forName: suiteName)
      super.tearDown()
  }
  ```

  Two kinds of data escape the defaults suite and land on the file system in the
  shared container: recorded ride tracks (`RideTracks/`) and cached vehicle
  images (`VehicleImages/`). Use unique ride IDs and serial numbers (a `UUID`
  works) so concurrent or repeated tests cannot collide, and clean the files up
  in `tearDown`.

Current suites:

| File | Covers |
| --- | --- |
| `CoordinateTransformTests.swift` | `NinebotCoordinateTransform` |
| `JSONValueTests.swift` | `JSONValue` coding and accessors |
| `RecordedRideTests.swift` | `NinebotRecordedRide` |
| `RideDetailParsingTests.swift` | `NinebotRideDetail` track extraction |
| `ServerClientTests.swift` | `NinebotServerClient`, against a stubbed `URLProtocol` |
| `VehicleStateTests.swift` | `NinebotVehicleState` derived values |
| `SharedStoreTests.swift` | `NinebotSharedStore` — config, login, dashboard, history, interface rides, tokens, images |
| `SharedStoreTrackStorageTests.swift` | `NinebotSharedStore` — recorded rides and track point files |

## What CI runs

`.github/workflows/ci.yml` runs on every push to any branch and on every pull
request.

- **`unit-tests`** — the gate. Runs `swift build --build-tests` followed by
  `swift test` on a `macos-26` runner. The build and test steps are separate so
  a compile failure surfaces as raw compiler diagnostics rather than being
  buried in test output. If this job is red, the change is not ready.
- **`xcode-build`** — advisory, marked `continue-on-error: true`. It attempts an
  `xcodebuild` of the `mini-ninebot` app target against the iOS simulator SDK
  with code signing disabled. It cannot be a gate: the project has no shared
  schemes, no `DEVELOPMENT_TEAM`, placeholder bundle IDs, and an App Group
  entitlement that a hosted runner cannot provision. Treat a failure here as
  something to look at, not as a blocker.

Both jobs run on `macos-26` and select Xcode 26.6 when present, falling back to
the image default with a warning. The project sets
`IPHONEOS_DEPLOYMENT_TARGET = 26.5`, which only Xcode 26.5+ can satisfy, so
older runner images (`macos-15` tops out at Xcode 26.3) are not usable.

There are no third-party dependencies, so nothing is fetched during a build; the
cache step only preserves incremental build artifacts.
