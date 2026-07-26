import XCTest
@testable import NineBotCore

final class VehicleStateTests: XCTestCase {
    private func state(
        battery: Int? = nil,
        isCharging: Bool? = nil,
        isPoweredOn: Bool? = nil,
        isLocked: Bool? = nil
    ) -> NinebotVehicleState {
        NinebotVehicleState(
            battery: battery,
            isCharging: isCharging,
            isPoweredOn: isPoweredOn,
            isLocked: isLocked,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Charge estimates

    func testChargeToEightyIsNilWhenNotCharging() {
        XCTAssertNil(state(battery: 40).estimatedChargeTo80Minutes)
        XCTAssertNil(state(battery: 40, isCharging: false).estimatedChargeTo80Minutes)
    }

    func testChargeToEightyIsNilWithoutABatteryReading() {
        XCTAssertNil(state(isCharging: true).estimatedChargeTo80Minutes)
    }

    func testChargeToEightyIsZeroPastTheThreshold() {
        XCTAssertEqual(state(battery: 80, isCharging: true).estimatedChargeTo80Minutes, 0)
        XCTAssertEqual(state(battery: 95, isCharging: true).estimatedChargeTo80Minutes, 0)
    }

    func testChargeToEightyUsesTheFallbackRate() {
        // No server prediction available: 4 min per percent, rounded up to 5.
        XCTAssertEqual(state(battery: 50, isCharging: true).estimatedChargeTo80Minutes, 120)
        XCTAssertEqual(state(battery: 60, isCharging: true).estimatedChargeTo80Minutes, 80)
    }

    func testChargeToEightyIsAlwaysAMultipleOfFive() {
        for battery in 0...79 {
            let minutes = state(battery: battery, isCharging: true).estimatedChargeTo80Minutes
            XCTAssertNotNil(minutes)
            XCTAssertEqual((minutes ?? 1).truncatingRemainder(dividingBy: 5), 0, "battery \(battery)")
        }
    }

    func testChargeEstimateDecreasesAsBatteryFills() {
        let low = state(battery: 20, isCharging: true).estimatedChargeTo80Minutes ?? 0
        let mid = state(battery: 50, isCharging: true).estimatedChargeTo80Minutes ?? 0
        let high = state(battery: 75, isCharging: true).estimatedChargeTo80Minutes ?? 0
        XCTAssertGreaterThan(low, mid)
        XCTAssertGreaterThan(mid, high)
    }

    // MARK: - Flags and text

    func testFullyChargedFlag() {
        XCTAssertFalse(state().isFullyCharged)
        XCTAssertFalse(state(battery: 99).isFullyCharged)
        XCTAssertTrue(state(battery: 100).isFullyCharged)
    }

    func testBatteryText() {
        XCTAssertEqual(state().batteryText, "--%")
        XCTAssertEqual(state(battery: 87).batteryText, "87%")
    }

    func testPowerTextPrefersChargingState() {
        XCTAssertEqual(state(battery: 100, isCharging: true).powerText, "已充满")
        XCTAssertEqual(state(battery: 60, isCharging: true).powerText, "充电中")
        XCTAssertEqual(state(battery: 60).powerText, "离线")
        XCTAssertEqual(state(battery: 60, isPoweredOn: true).powerText, "已上电")
        XCTAssertEqual(state(battery: 60, isPoweredOn: false).powerText, "已熄火")
    }

    func testLockText() {
        XCTAssertEqual(state().lockText, "未知")
        XCTAssertEqual(state(isLocked: true).lockText, "已锁")
        XCTAssertEqual(state(isLocked: false).lockText, "未锁")
    }
}
