import XCTest
@testable import NineBotCore

/// The dashboard warning list. These were four Chinese strings rendered with
/// `ForEach(warnings, id: \.self)`, so the wording was the list identity.
final class VehicleWarningTests: XCTestCase {

    private func state(battery: Int? = nil, isPoweredOn: Bool? = nil, isLocked: Bool? = nil) -> NinebotVehicleState {
        NinebotVehicleState(
            battery: battery,
            isPoweredOn: isPoweredOn,
            isLocked: isLocked,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Battery thresholds
    //
    // The two battery cases are exclusive — an `else if` — so a very low
    // battery must not also report the softer warning.

    func testBatteryThresholdsAreExclusive() {
        XCTAssertEqual(state(battery: 14).warnings, [.batteryVeryLow])
        XCTAssertEqual(state(battery: 0).warnings, [.batteryVeryLow])
    }

    func testFifteenIsLowNotVeryLow() {
        // `< 15` is very low, so 15 itself falls through to the `< 25` branch.
        XCTAssertEqual(state(battery: 15).warnings, [.batteryLow])
        XCTAssertEqual(state(battery: 24).warnings, [.batteryLow])
    }

    func testTwentyFiveIsClear() {
        XCTAssertEqual(state(battery: 25).warnings, [])
        XCTAssertEqual(state(battery: 100).warnings, [])
    }

    func testMissingBatteryWarnsAboutNothing() {
        XCTAssertEqual(state().warnings, [])
    }

    // MARK: - The power and lock flags
    //
    // Both compare against `false` explicitly, so a missing flag is silent.

    func testFlagsOnlyWarnWhenExplicitlyFalse() {
        XCTAssertEqual(state(isPoweredOn: false).warnings, [.poweredOff])
        XCTAssertEqual(state(isPoweredOn: true).warnings, [])
        XCTAssertEqual(state(isLocked: false).warnings, [.unlocked])
        XCTAssertEqual(state(isLocked: true).warnings, [])
    }

    func testWarningsAccumulateInAFixedOrder() {
        let all = state(battery: 10, isPoweredOn: false, isLocked: false).warnings
        XCTAssertEqual(all, [.batteryVeryLow, .poweredOff, .unlocked])
    }

    // MARK: - Identity

    /// The whole point of the enum: identity is ASCII and independent of wording.
    func testRawValuesAreStableAscii() {
        XCTAssertEqual(NinebotVehicleWarning.batteryVeryLow.id, "battery_very_low")
        XCTAssertEqual(NinebotVehicleWarning.batteryLow.id, "battery_low")
        XCTAssertEqual(NinebotVehicleWarning.poweredOff.id, "powered_off")
        XCTAssertEqual(NinebotVehicleWarning.unlocked.id, "unlocked")
        XCTAssertEqual(Set(NinebotVehicleWarning.allCases.map(\.id)).count, 4)
    }

    func testThresholdsAreNamed() {
        XCTAssertEqual(NinebotVehicleState.lowBatteryPercent, 15)
        XCTAssertEqual(NinebotVehicleState.guardedBatteryPercent, 25)
    }
}
