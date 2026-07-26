import XCTest
@testable import NineBotCore

/// The power and charging state machines, extracted out of the string-producing
/// properties so the ordering can actually be verified.
final class ChargingStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func state(
        battery: Int? = nil,
        isCharging: Bool? = nil,
        isPoweredOn: Bool? = nil,
        remainingChargeTime: Double? = nil,
        estimatedFullAt: Date? = nil
    ) -> NinebotVehicleState {
        let prediction: NinebotServerPrediction? = estimatedFullAt.map { date in
            NinebotServerPrediction(
                range: NinebotServerRangePrediction(),
                charging: NinebotServerChargingPrediction(estimatedFullAt: date)
            )
        }
        return NinebotVehicleState(
            battery: battery,
            isCharging: isCharging,
            isPoweredOn: isPoweredOn,
            remainingChargeTime: remainingChargeTime,
            updatedAt: now,
            serverPrediction: prediction
        )
    }

    // MARK: - Power status ordering
    //
    // This ordering is the whole reason the enum exists. Getting it wrong is
    // invisible until someone notices their moving vehicle says "已充满".

    func testFullyChargedOutranksEverything() {
        // Riding at 100% still reports fully charged, not powered on.
        XCTAssertEqual(state(battery: 100, isPoweredOn: true).powerStatus, .fullyCharged)
        XCTAssertEqual(state(battery: 100, isCharging: true).powerStatus, .fullyCharged)
        XCTAssertEqual(state(battery: 101, isPoweredOn: false).powerStatus, .fullyCharged)
    }

    func testChargingOutranksThePowerFlag() {
        XCTAssertEqual(state(battery: 50, isCharging: true, isPoweredOn: true).powerStatus, .charging)
        XCTAssertEqual(state(battery: 50, isCharging: true, isPoweredOn: false).powerStatus, .charging)
    }

    func testMissingPowerFlagIsOfflineNotPoweredOff() {
        // "offline" here means the field is absent, not that the network is down.
        XCTAssertEqual(state(battery: 50).powerStatus, .offline)
        XCTAssertEqual(state(battery: 50, isCharging: false).powerStatus, .offline)
    }

    func testPowerFlagMapsWhenNothingElseApplies() {
        XCTAssertEqual(state(battery: 50, isPoweredOn: true).powerStatus, .poweredOn)
        XCTAssertEqual(state(battery: 50, isPoweredOn: false).powerStatus, .poweredOff)
    }

    func testPowerTextMatchesTheStatus() {
        XCTAssertEqual(state(battery: 100, isPoweredOn: true).powerText, "已充满")
        XCTAssertEqual(state(battery: 50, isCharging: true).powerText, "充电中")
        XCTAssertEqual(state(battery: 50).powerText, "离线")
        XCTAssertEqual(state(battery: 50, isPoweredOn: true).powerText, "已上电")
        XCTAssertEqual(state(battery: 50, isPoweredOn: false).powerText, "已熄火")
    }

    // MARK: - Charging state

    func testChargingStateIgnoresThePowerFlag() {
        XCTAssertEqual(state(battery: 100).chargingState, .fullyCharged)
        XCTAssertEqual(state(battery: 50, isCharging: true).chargingState, .charging)
        XCTAssertEqual(state(battery: 50, isCharging: false).chargingState, .notCharging)
        XCTAssertEqual(state(battery: 50).chargingState, .unknown)
    }

    func testChargingStateTextMatches() {
        XCTAssertEqual(state(battery: 100).chargingStateText, "已充满")
        XCTAssertEqual(state(battery: 50, isCharging: true).chargingStateText, "充电中")
        XCTAssertEqual(state(battery: 50, isCharging: false).chargingStateText, "未充电")
        XCTAssertEqual(state(battery: 50).chargingStateText, "未知")
    }

    /// The unknown case has its own wording here — "充电未知", not "未知".
    func testChargeSummaryHasADistinctUnknownWording() {
        XCTAssertEqual(state(battery: 50).chargeSummaryText, "充电未知")
        XCTAssertEqual(state(battery: 100).chargeSummaryText, "已充满")
        XCTAssertEqual(state(battery: 50, isCharging: false).chargeSummaryText, "未充电")
        XCTAssertTrue(state(battery: 50, isCharging: true).chargeSummaryText.hasPrefix("充电中 · 约 "))
    }

    // MARK: - Charge estimates

    func testEstimateIsNotChargingWhenIdle() {
        XCTAssertEqual(state(battery: 50).fullChargeEstimate, .notCharging)
        XCTAssertEqual(state(battery: 50, isCharging: false).fullChargeEstimate, .notCharging)
        XCTAssertEqual(state(battery: 50).chargeTo80Estimate, .notCharging)
    }

    func testEstimateIsCalculatingWithoutAMinuteFigure() {
        // Charging with no battery reading: no minutes can be derived.
        XCTAssertEqual(state(isCharging: true).fullChargeEstimate, .calculating)
        XCTAssertEqual(state(isCharging: true).chargeTo80Estimate, .calculating)
    }

    func testEstimateIsReachedAtTheTarget() {
        XCTAssertEqual(state(battery: 85, isCharging: true).chargeTo80Estimate, .reached)
        XCTAssertEqual(state(battery: 80, isCharging: true).chargeTo80Estimate, .reached)
        // 100% is fully charged, which short-circuits to zero minutes.
        XCTAssertEqual(state(battery: 100, isCharging: true).fullChargeEstimate, .reached)
    }

    func testEstimateCarriesTheMinuteFigure() {
        // 50% → (80-50) x 4 = 120 minutes to 80%.
        XCTAssertEqual(state(battery: 50, isCharging: true).chargeTo80Estimate, .minutes(120))
        // 50% → 30x4 fast + 20x7 taper = 260 minutes to full.
        XCTAssertEqual(state(battery: 50, isCharging: true).fullChargeEstimate, .minutes(260))
    }

    func testEstimateTextMatches() {
        XCTAssertEqual(state(battery: 50).estimatedFullChargeTimeText, "未充电")
        XCTAssertEqual(state(isCharging: true).estimatedFullChargeTimeText, "计算中")
        XCTAssertEqual(state(battery: 100, isCharging: true).estimatedFullChargeTimeText, "已充满")
        XCTAssertEqual(state(battery: 85, isCharging: true).estimatedChargeTo80TimeText, "已超过 80%")
    }

    // MARK: - Clocks

    func testClockIsUnavailableWhenThereIsNothingToProject() {
        XCTAssertEqual(state(battery: 50).fullChargeClock, .unavailable)
        XCTAssertEqual(state(isCharging: true).fullChargeClock, .unavailable)
        XCTAssertEqual(state(battery: 50).estimatedFullChargeClockText, "--")
    }

    func testClockReportsReachedRatherThanATime() {
        XCTAssertEqual(state(battery: 100, isCharging: true).fullChargeClock, .reached)
        XCTAssertEqual(state(battery: 85, isCharging: true).chargeTo80Clock, .reached)
        XCTAssertEqual(state(battery: 85, isCharging: true).estimatedChargeTo80ClockText, "已超过 80%")
    }

    func testClockProjectsFromUpdatedAt() {
        // 120 minutes from updatedAt.
        let expected = now.addingTimeInterval(120 * 60)
        XCTAssertEqual(state(battery: 50, isCharging: true).chargeTo80Clock, .at(expected))
    }

    /// When the server supplies its own completion timestamp it wins over
    /// adding minutes to `updatedAt` — but only for the full-charge clock.
    ///
    /// The timestamp has to be genuinely in the future: the minute figure is
    /// derived with `timeIntervalSinceNow`, so a past instant collapses to zero
    /// and the estimate reports `.reached` instead.
    func testFullChargeClockPrefersTheServerTimestamp() {
        let serverTime = Date().addingTimeInterval(2 * 3_600)
        let s = state(battery: 50, isCharging: true, estimatedFullAt: serverTime)
        XCTAssertEqual(s.fullChargeClock, .at(serverTime))

        // The 80% clock has no server equivalent, so it still uses updatedAt.
        XCTAssertEqual(s.chargeTo80Clock, .at(now.addingTimeInterval(120 * 60)))
    }

    /// A worth-knowing quirk: the server's completion time is measured against
    /// *now*, not against `updatedAt`. So a cached snapshot whose predicted
    /// completion time has already passed reports "已充满" at 50% battery.
    ///
    /// Android will inherit this unless it measures against `updatedAt`
    /// instead. Flagged rather than changed — fixing it alters behaviour.
    func testStaleServerTimestampReadsAsFullyCharged() {
        let past = Date().addingTimeInterval(-3_600)
        let s = state(battery: 50, isCharging: true, estimatedFullAt: past)
        XCTAssertEqual(s.fullChargeEstimate, .reached)
        XCTAssertEqual(s.estimatedFullChargeTimeText, "已充满")
        // The 80% path does not consult the server, so it stays sane.
        XCTAssertEqual(s.chargeTo80Estimate, .minutes(120))
    }

    func testMinuteValueAccessor() {
        XCTAssertEqual(NinebotChargeEstimate.minutes(42).minuteValue, 42)
        XCTAssertNil(NinebotChargeEstimate.reached.minuteValue)
        XCTAssertNil(NinebotChargeEstimate.notCharging.minuteValue)
        XCTAssertNil(NinebotChargeEstimate.calculating.minuteValue)
    }
}
